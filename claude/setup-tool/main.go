// ferm-setup is a one-shot provisioning tool for Fermrad developers.
//
// It authenticates with GitHub via Device Flow, verifies that the user is a
// member of the fermrad org, sets up their local machine (SSH key, ssh/config,
// Claude Code skills), and triggers the server-side provisioning workflow.
//
// Build-time variables (set via -ldflags):
//
//	-X main.githubClientID=<OAuth App Client ID>
package main

import (
	"bufio"
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
)

// githubClientID is the OAuth App Client ID, injected at build time.
// The app must request scopes: read:org, workflow.
var githubClientID = "PLACEHOLDER_OAUTH_CLIENT_ID"

const (
	fermradOrg        = "fermrad"
	devServerHost     = "claude-dev.ferm.dk"
	infraRepo         = "fermrad/infrastructure"
	provisionWorkflow = "provision-claude-user.yml"
	aiToolsRepo       = "fermrad/AI-tools"
)

// ── GitHub API helpers ────────────────────────────────────────────────────────

func apiGet(token, path string, out interface{}) error {
	req, _ := http.NewRequest("GET", "https://api.github.com"+path, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return fmt.Errorf("GitHub API %s → %d: %s", path, resp.StatusCode, body)
	}
	if out != nil {
		return json.Unmarshal(body, out)
	}
	return nil
}

func apiPost(token, path string, payload interface{}) (int, []byte, error) {
	data, _ := json.Marshal(payload)
	req, _ := http.NewRequest("POST", "https://api.github.com"+path, bytes.NewReader(data))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, body, nil
}

// ── GitHub Device Flow auth ───────────────────────────────────────────────────

type deviceFlowResp struct {
	DeviceCode      string `json:"device_code"`
	UserCode        string `json:"user_code"`
	VerificationURI string `json:"verification_uri"`
	ExpiresIn       int    `json:"expires_in"`
	Interval        int    `json:"interval"`
}

type tokenResp struct {
	AccessToken string `json:"access_token"`
	Error       string `json:"error"`
	ErrorDesc   string `json:"error_description"`
}

func authenticate() (token string, username string, err error) {
	// Step 1: request device + user codes
	resp, err := http.PostForm("https://github.com/login/device/code", url.Values{
		"client_id": {githubClientID},
		"scope":     {"read:org workflow"},
	})
	if err != nil {
		return "", "", fmt.Errorf("starting device flow: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	// GitHub returns form-encoded or JSON depending on Accept header.
	// We sent no Accept, so it returns form-encoded.
	vals, _ := url.ParseQuery(string(body))
	df := deviceFlowResp{
		DeviceCode:      vals.Get("device_code"),
		UserCode:        vals.Get("user_code"),
		VerificationURI: vals.Get("verification_uri"),
		Interval:        5,
	}
	if df.UserCode == "" {
		// Try JSON
		json.Unmarshal(body, &df)
	}
	if df.DeviceCode == "" {
		return "", "", fmt.Errorf("no device_code in response: %s", body)
	}

	interval := df.Interval
	if interval == 0 {
		interval = 5
	}

	fmt.Printf("\n┌─────────────────────────────────────────┐\n")
	fmt.Printf("│  Visit: %-31s  │\n", df.VerificationURI)
	fmt.Printf("│  Code:  %-31s  │\n", df.UserCode)
	fmt.Printf("└─────────────────────────────────────────┘\n\n")
	fmt.Print("Waiting for authorisation... ")

	// Step 2: poll for token
	deadline := time.Now().Add(time.Duration(df.ExpiresIn) * time.Second)
	for time.Now().Before(deadline) {
		time.Sleep(time.Duration(interval) * time.Second)

		pollResp, err := http.PostForm("https://github.com/login/oauth/access_token", url.Values{
			"client_id":   {githubClientID},
			"device_code": {df.DeviceCode},
			"grant_type":  {"urn:ietf:params:oauth:grant-type:device_code"},
		})
		if err != nil {
			continue
		}
		pollBody, _ := io.ReadAll(pollResp.Body)
		pollResp.Body.Close()

		pollVals, _ := url.ParseQuery(string(pollBody))
		var tr tokenResp
		if pollVals.Get("access_token") != "" {
			tr.AccessToken = pollVals.Get("access_token")
		} else {
			json.Unmarshal(pollBody, &tr)
		}
		if tr.Error == "slow_down" {
			interval += 5
			continue
		}
		if tr.Error == "authorization_pending" {
			fmt.Print(".")
			continue
		}
		if tr.AccessToken != "" {
			fmt.Println(" ✓")
			token = tr.AccessToken
			break
		}
		if tr.Error != "" {
			return "", "", fmt.Errorf("auth error: %s — %s", tr.Error, tr.ErrorDesc)
		}
	}
	if token == "" {
		return "", "", fmt.Errorf("authorisation timed out")
	}

	// Step 3: get username
	var user struct {
		Login string `json:"login"`
	}
	if err := apiGet(token, "/user", &user); err != nil {
		return "", "", fmt.Errorf("fetching user: %w", err)
	}
	return token, user.Login, nil
}

// ── Org membership check ─────────────────────────────────────────────────────

func checkOrgMembership(token, username string) error {
	var membership struct {
		State string `json:"state"`
		Role  string `json:"role"`
	}
	path := fmt.Sprintf("/orgs/%s/memberships/%s", fermradOrg, username)
	if err := apiGet(token, path, &membership); err != nil {
		return fmt.Errorf("not a %s org member (or token missing read:org scope): %w", fermradOrg, err)
	}
	if membership.State != "active" {
		return fmt.Errorf("org membership is %q, not active", membership.State)
	}
	return nil
}

// ── SSH key handling ─────────────────────────────────────────────────────────

func findOrCreateSSHKey(username string) (privPath, pubKey string, err error) {
	home, _ := os.UserHomeDir()
	sshDir := filepath.Join(home, ".ssh")
	os.MkdirAll(sshDir, 0700)

	// Look for an existing key
	for _, name := range []string{"id_ed25519", "id_ecdsa", "id_rsa"} {
		pubPath := filepath.Join(sshDir, name+".pub")
		data, readErr := os.ReadFile(pubPath)
		if readErr == nil && len(data) > 0 {
			return filepath.Join(sshDir, name), strings.TrimSpace(string(data)), nil
		}
	}

	// Generate a new Ed25519 key
	pubKey, privPath, err = generateEd25519Key(sshDir, username)
	return
}

func generateEd25519Key(sshDir, comment string) (pubKeyStr, privPath string, err error) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return "", "", fmt.Errorf("generating key: %w", err)
	}

	// Encode private key in OpenSSH PEM format
	privPEM, err := marshalOpenSSHPrivateKey(priv, comment)
	if err != nil {
		return "", "", fmt.Errorf("encoding private key: %w", err)
	}

	// Encode public key in authorized_keys format
	sshPub, err := ssh.NewPublicKey(pub)
	if err != nil {
		return "", "", fmt.Errorf("encoding public key: %w", err)
	}
	pubKeyStr = strings.TrimSpace(string(ssh.MarshalAuthorizedKey(sshPub))) + " " + comment

	privPath = filepath.Join(sshDir, "id_ed25519")
	if err := os.WriteFile(privPath, privPEM, 0600); err != nil {
		return "", "", err
	}
	if err := os.WriteFile(privPath+".pub", []byte(pubKeyStr+"\n"), 0644); err != nil {
		return "", "", err
	}
	return pubKeyStr, privPath, nil
}

// marshalOpenSSHPrivateKey encodes an Ed25519 private key in OpenSSH PEM format.
// golang.org/x/crypto/ssh does not expose a public API for this, so we build
// the wire format manually (matches openssh-key-v1 spec).
func marshalOpenSSHPrivateKey(key ed25519.PrivateKey, comment string) ([]byte, error) {
	pub := key.Public().(ed25519.PublicKey)

	// check number (random 4 bytes, repeated for integrity)
	var checkInt [4]byte
	if _, err := io.ReadFull(rand.Reader, checkInt[:]); err != nil {
		return nil, err
	}

	// Build the private key blob
	var privBlob bytes.Buffer
	writeStr := func(b []byte) {
		var l [4]byte
		binary.BigEndian.PutUint32(l[:], uint32(len(b)))
		privBlob.Write(l[:])
		privBlob.Write(b)
	}
	privBlob.Write(checkInt[:])
	privBlob.Write(checkInt[:])
	writeStr([]byte("ssh-ed25519"))
	writeStr(pub)
	writeStr(key) // 64-byte seed+pub
	writeStr([]byte(comment))
	// Pad to 8-byte boundary
	for i := 1; privBlob.Len()%8 != 0; i++ {
		privBlob.WriteByte(byte(i))
	}

	// Public key blob
	var pubBlob bytes.Buffer
	pubWriteStr := func(b []byte) {
		var l [4]byte
		binary.BigEndian.PutUint32(l[:], uint32(len(b)))
		pubBlob.Write(l[:])
		pubBlob.Write(b)
	}
	pubWriteStr([]byte("ssh-ed25519"))
	pubWriteStr(pub)

	// Outer structure
	var outer bytes.Buffer
	writeOuter := func(b []byte) {
		var l [4]byte
		binary.BigEndian.PutUint32(l[:], uint32(len(b)))
		outer.Write(l[:])
		outer.Write(b)
	}
	outer.WriteString("openssh-key-v1\x00")
	writeOuter([]byte("none")) // cipher
	writeOuter([]byte("none")) // kdf
	writeOuter([]byte{})       // kdf options
	// number of keys: 1
	var nkeys [4]byte
	binary.BigEndian.PutUint32(nkeys[:], 1)
	outer.Write(nkeys[:])
	writeOuter(pubBlob.Bytes())
	writeOuter(privBlob.Bytes())

	return pem.EncodeToMemory(&pem.Block{
		Type:  "OPENSSH PRIVATE KEY",
		Bytes: outer.Bytes(),
	}), nil
}

// ── SSH config ────────────────────────────────────────────────────────────────

func writeSSHConfig(username, privPath string) (alreadySet bool, err error) {
	home, _ := os.UserHomeDir()
	configPath := filepath.Join(home, ".ssh", "config")

	existing, _ := os.ReadFile(configPath)
	if strings.Contains(string(existing), devServerHost) {
		return true, nil
	}

	entry := fmt.Sprintf("\nHost %s\n  User %s\n  IdentityFile %s\n",
		devServerHost, username, privPath)

	f, err := os.OpenFile(configPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		return false, err
	}
	defer f.Close()
	_, err = f.WriteString(entry)
	return false, err
}

// ── Claude skills installation ────────────────────────────────────────────────

func installSkills(token string) error {
	home, _ := os.UserHomeDir()
	repoDir := filepath.Join(home, "repos", "AI-tools")
	skillsSrc := filepath.Join(repoDir, "claude", "skills")
	commandsDst := filepath.Join(home, ".claude", "commands")

	if err := cloneOrUpdateRepo(token, repoDir); err != nil {
		return fmt.Errorf("updating AI-tools: %w", err)
	}

	if err := os.MkdirAll(commandsDst, 0755); err != nil {
		return err
	}

	entries, err := os.ReadDir(skillsSrc)
	if err != nil {
		return fmt.Errorf("reading skills dir: %w", err)
	}

	installed := 0
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		skillMD := filepath.Join(skillsSrc, e.Name(), "SKILL.md")
		if _, err := os.Stat(skillMD); err != nil {
			continue
		}
		linkPath := filepath.Join(commandsDst, e.Name()+".md")
		os.Remove(linkPath)
		if err := createLink(skillMD, linkPath); err != nil {
			fmt.Printf("  warning: could not link %s: %v\n", e.Name(), err)
			continue
		}
		installed++
	}
	fmt.Printf("  installed %d skills → %s\n", installed, commandsDst)
	return nil
}

func cloneOrUpdateRepo(token, repoDir string) error {
	cloneURL := fmt.Sprintf("https://x-access-token:%s@github.com/%s.git", token, aiToolsRepo)

	if _, err := os.Stat(filepath.Join(repoDir, ".git")); os.IsNotExist(err) {
		fmt.Printf("  cloning AI-tools (claude/ only)...\n")
		if err := gitRun("", "clone", "--filter=blob:none", "--sparse", cloneURL, repoDir); err != nil {
			return err
		}
		if err := gitRun(repoDir, "sparse-checkout", "set", "claude"); err != nil {
			return err
		}
		// Remove token from stored remote URL
		return gitRun(repoDir, "remote", "set-url", "origin",
			fmt.Sprintf("https://github.com/%s.git", aiToolsRepo))
	}

	fmt.Printf("  updating AI-tools...\n")
	return gitRun(repoDir, "pull", "--ff-only")
}

func gitRun(dir string, args ...string) error {
	// Use exec on macOS/Linux; on Windows git must be in PATH
	cmd := []string{"git"}
	if dir != "" {
		cmd = append(cmd, "-C", dir)
	}
	cmd = append(cmd, args...)
	return run(cmd[0], cmd[1:]...)
}

func run(name string, args ...string) error {
	// Minimal exec: inherit stderr for progress output, discard stdout
	pr, pw, _ := os.Pipe()
	defer pr.Close()
	defer pw.Close()

	// We just need exit status
	var buf bytes.Buffer
	done := make(chan struct{})
	go func() {
		io.Copy(&buf, pr)
		close(done)
	}()

	// On Windows, wrap in cmd /c for shell commands
	var execName string
	var execArgs []string
	if runtime.GOOS == "windows" && (name == "git") {
		execName = name + ".exe"
	} else {
		execName = name
	}
	execArgs = args

	// Use os.StartProcess for cross-platform compat
	attr := &os.ProcAttr{
		Files: []*os.File{os.Stdin, pw, pw},
	}
	path, lookErr := lookPath(execName)
	if lookErr != nil {
		return fmt.Errorf("%s not found in PATH", execName)
	}
	fullArgs := append([]string{execName}, execArgs...)
	proc, err := os.StartProcess(path, fullArgs, attr)
	pw.Close()
	if err != nil {
		return err
	}
	state, err := proc.Wait()
	<-done
	if err != nil {
		return err
	}
	if !state.Success() {
		return fmt.Errorf("%s %v failed: %s", name, args, buf.String())
	}
	return nil
}

func lookPath(name string) (string, error) {
	// Simple PATH search
	pathEnv := os.Getenv("PATH")
	var sep string
	if runtime.GOOS == "windows" {
		sep = ";"
	} else {
		sep = ":"
	}
	for _, dir := range strings.Split(pathEnv, sep) {
		full := filepath.Join(dir, name)
		if info, err := os.Stat(full); err == nil && !info.IsDir() {
			return full, nil
		}
	}
	return "", fmt.Errorf("%s: not found", name)
}

// createLink creates a symlink on Unix or copies the file on Windows (where
// symlinks require elevated privileges or developer mode).
func createLink(target, link string) error {
	if runtime.GOOS == "windows" {
		data, err := os.ReadFile(target)
		if err != nil {
			return err
		}
		return os.WriteFile(link, data, 0644)
	}
	return os.Symlink(target, link)
}

// ── Provisioning workflow ─────────────────────────────────────────────────────

func triggerProvisioning(token, username, pubKey string) (runURL string, err error) {
	payload := map[string]interface{}{
		"ref": "main",
		"inputs": map[string]string{
			"github_username": username,
			"public_key":      pubKey,
		},
	}

	path := fmt.Sprintf("/repos/%s/actions/workflows/%s/dispatches", infraRepo, provisionWorkflow)
	status, body, err := apiPost(token, path, payload)
	if err != nil {
		return "", fmt.Errorf("dispatching workflow: %w", err)
	}
	if status != 204 {
		return "", fmt.Errorf("workflow dispatch returned %d: %s", status, body)
	}

	// Wait a moment for the run to register, then fetch its URL
	time.Sleep(3 * time.Second)
	var runs struct {
		WorkflowRuns []struct {
			ID     int64  `json:"id"`
			HTMLURL string `json:"html_url"`
		} `json:"workflow_runs"`
	}
	listPath := fmt.Sprintf("/repos/%s/actions/workflows/%s/runs?per_page=1", infraRepo, provisionWorkflow)
	if err := apiGet(token, listPath, &runs); err == nil && len(runs.WorkflowRuns) > 0 {
		runURL = runs.WorkflowRuns[0].HTMLURL
	}
	return runURL, nil
}

// ── Main ──────────────────────────────────────────────────────────────────────

func check(step string, err error) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "\n✗ %s: %v\n", step, err)
		os.Exit(1)
	}
}

func main() {
	if githubClientID == "PLACEHOLDER_OAUTH_CLIENT_ID" {
		fmt.Fprintln(os.Stderr, "Error: this binary was built without a GitHub OAuth Client ID.\n"+
			"See claude/setup-tool/README.md for build instructions.")
		os.Exit(1)
	}

	fmt.Println("\n╔══════════════════════════════════════╗")
	fmt.Println("║       Fermrad Dev Setup Tool         ║")
	fmt.Println("╚══════════════════════════════════════╝")

	// 1. Authenticate
	fmt.Println("\n→ Authenticating with GitHub...")
	token, username, err := authenticate()
	check("authentication", err)
	fmt.Printf("  ✓ Signed in as %s\n", username)

	// 2. Verify org membership
	fmt.Printf("\n→ Checking %s org membership...\n", fermradOrg)
	check("org membership", checkOrgMembership(token, username))
	fmt.Printf("  ✓ Active %s member\n", fermradOrg)

	// 3. SSH key
	fmt.Println("\n→ Checking SSH key...")
	privPath, pubKey, err := findOrCreateSSHKey(username)
	check("SSH key", err)
	if strings.Contains(privPath, "id_ed25519") {
		action := "found"
		if _, statErr := os.Stat(privPath); statErr == nil {
			if _, pubStatErr := os.Stat(privPath + ".pub"); pubStatErr != nil {
				action = "generated"
			}
		}
		fmt.Printf("  ✓ Key %s: %s\n", action, privPath)
	}

	// 4. SSH config
	fmt.Println("\n→ Configuring SSH...")
	alreadySet, err := writeSSHConfig(username, privPath)
	check("SSH config", err)
	if alreadySet {
		fmt.Printf("  ✓ %s already in ~/.ssh/config\n", devServerHost)
	} else {
		fmt.Printf("  ✓ Added %s → User %s\n", devServerHost, username)
	}

	// 5. Skills
	fmt.Println("\n→ Installing Claude Code skills...")
	check("skills install", installSkills(token))

	// 6. Provision server
	fmt.Printf("\n→ Provisioning server access on %s...\n", devServerHost)
	preview := pubKey
	if len(preview) > 60 {
		preview = preview[:60] + "..."
	}
	fmt.Printf("  Public key: %s\n", preview)

	fmt.Print("\n  Trigger server provisioning? [Y/n] ")
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Scan()
	answer := strings.TrimSpace(strings.ToLower(scanner.Text()))
	if answer != "" && answer != "y" && answer != "yes" {
		fmt.Println("\nSkipped. Run this tool again when ready, or share your public key")
		fmt.Println("with a fermrad admin to provision server access manually.")
		os.Exit(0)
	}

	runURL, err := triggerProvisioning(token, username, pubKey)
	check("triggering provisioning", err)

	fmt.Println("\n╔══════════════════════════════════════╗")
	fmt.Println("║             All done!                ║")
	fmt.Println("╠══════════════════════════════════════╣")
	fmt.Printf("║                                      \n")
	if runURL != "" {
		fmt.Printf("  Provisioning job: %s\n", runURL)
	}
	fmt.Printf("\n  The server is being set up. Once the GitHub Actions\n")
	fmt.Printf("  workflow completes, open the job summary to get your\n")
	fmt.Printf("  Claude session link.\n\n")
	fmt.Printf("  To start a session later:\n")
	fmt.Printf("    /new-remote-session\n\n")
}

