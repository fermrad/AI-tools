// ferm-setup provisions a new Fermrad developer's machine and server access.
// It is self-contained — no prerequisites beyond the binary itself.
// Authentication uses GitHub Device Flow (no client secret required).
package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"embed"
	"encoding/binary"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"io/fs"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"
)

//go:embed bundled/skills
var bundledSkills embed.FS

// githubClientID is injected at build time via -ldflags.
// Device Flow requires no client secret — the client_id alone is enough,
// and GitHub explicitly designed this flow for native apps and CLIs.
var githubClientID = "PLACEHOLDER_OAUTH_CLIENT_ID"

const (
	fermradOrg        = "fermrad"
	devServerHost     = "claude-dev.ferm.dk"
	infraRepo         = "fermrad/infrastructure"
	provisionWorkflow = "provision-claude-user.yml"
	aiToolsRepo       = "fermrad/AI-tools"
)

// ── Browser UI ────────────────────────────────────────────────────────────────

const uiHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Fermrad Dev Setup</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
         background:#f8fafc;color:#0f172a;min-height:100vh;
         display:flex;align-items:flex-start;justify-content:center;padding:48px 16px}
    .card{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:32px;
          width:100%;max-width:560px;box-shadow:0 1px 3px rgba(0,0,0,.06)}
    h1{font-size:1.2rem;font-weight:600;margin-bottom:24px}
    .steps{display:flex;flex-direction:column;gap:10px}
    .step{display:flex;align-items:flex-start;gap:10px;font-size:.9rem;line-height:1.5}
    .icon{width:18px;flex-shrink:0;text-align:center;margin-top:1px;font-size:.85rem}
    .ok .icon{color:#16a34a}
    .err .icon,.err .text{color:#dc2626}
    .dim .icon,.dim .text{color:#6b7280}
    .auth-box{margin-top:10px;padding:20px;background:#f0f9ff;
              border:1px solid #bae6fd;border-radius:8px}
    .auth-box p{font-size:.875rem;color:#0369a1;margin-bottom:14px}
    .user-code{font-family:'SF Mono',Monaco,monospace;font-size:2rem;
               font-weight:700;letter-spacing:.2em;color:#0f172a;
               text-align:center;padding:16px 0}
    .gh-link{display:inline-block;color:#2563eb;font-size:.875rem;
             text-decoration:none;margin-top:4px}
    .gh-link:hover{text-decoration:underline}
    .waiting{margin-top:12px;font-size:.8rem;color:#6b7280}
    .confirm{margin-top:20px;padding:16px;background:#f8fafc;
             border:1px solid #e2e8f0;border-radius:8px}
    .confirm p{font-size:.85rem;color:#64748b;margin-bottom:10px}
    code{display:block;font-family:'SF Mono',Monaco,monospace;font-size:.75rem;
         background:#f1f5f9;padding:8px;border-radius:4px;color:#475569;
         word-break:break-all;margin-bottom:14px}
    button{background:#0f172a;color:#fff;border:none;border-radius:6px;
           padding:8px 18px;font-size:.875rem;font-weight:500;cursor:pointer}
    button:hover{background:#1e293b}
    button:disabled{background:#94a3b8;cursor:default}
    .link-row{margin-top:4px}
    .link-row a{color:#2563eb;text-decoration:none;font-size:.875rem}
    .link-row a:hover{text-decoration:underline}
    .done{margin-top:20px;padding:16px;background:#f0fdf4;border:1px solid #bbf7d0;
          border-radius:8px;color:#166534;font-size:.875rem;font-weight:500}
    @keyframes spin{to{transform:rotate(360deg)}}
    .spin{display:inline-block;animation:spin 1s linear infinite}
  </style>
</head>
<body>
<div class="card">
  <h1>⚙ Fermrad Dev Setup</h1>
  <div class="steps" id="steps"></div>
</div>
<script>
const root = document.getElementById('steps');
const es = new EventSource('/events');
es.onmessage = e => {
  const ev = JSON.parse(e.data);
  const d = document.createElement('div');
  if (ev.type === 'running') {
    d.className = 'step dim';
    d.innerHTML = '<span class="icon"><span class="spin">⟳</span></span><span class="text">'+ev.text+'</span>';
    root.appendChild(d);
  } else if (ev.type === 'ok') {
    d.className = 'step ok';
    d.innerHTML = '<span class="icon">✓</span><span class="text">'+ev.text+'</span>';
    root.appendChild(d);
  } else if (ev.type === 'error') {
    d.className = 'step err';
    d.innerHTML = '<span class="icon">✗</span><span class="text">'+ev.text+'</span>';
    root.appendChild(d);
  } else if (ev.type === 'auth') {
    d.className = 'auth-box';
    d.innerHTML =
      '<p>A GitHub tab has opened. Enter this code to authorise:</p>' +
      '<div class="user-code">'+ev.text+'</div>' +
      '<a class="gh-link" href="'+ev.url+'" target="_blank">'+ev.url+' ↗</a>' +
      '<p class="waiting"><span class="spin">⟳</span> Waiting for authorisation…</p>';
    root.appendChild(d);
    window.open(ev.url, '_blank');
  } else if (ev.type === 'link') {
    d.className = 'link-row';
    d.innerHTML = '<a href="'+ev.url+'" target="_blank">↗ '+ev.text+'</a>';
    root.appendChild(d);
  } else if (ev.type === 'confirm') {
    d.className = 'confirm';
    const btn = document.createElement('button');
    btn.textContent = 'Set up server access';
    btn.onclick = () => {
      btn.disabled = true;
      btn.textContent = 'Setting up…';
      fetch('/confirm', {method:'POST'});
    };
    d.innerHTML = '<p>Your SSH public key will be added to the dev server:</p><code>'+ev.text+'</code>';
    d.appendChild(btn);
    root.appendChild(d);
  } else if (ev.type === 'done') {
    d.className = 'done';
    d.textContent = '✓ Setup complete — open the job link above to watch provisioning and get your Claude session URL.';
    root.appendChild(d);
    es.close();
  }
};
</script>
</body>
</html>`


// ── Event bus ─────────────────────────────────────────────────────────────────

type Event struct {
	Type string `json:"type"`
	Text string `json:"text,omitempty"`
	URL  string `json:"url,omitempty"`
}

type eventBus struct {
	mu      sync.Mutex
	history []Event
	subs    map[int]chan Event
	nextID  int
}

func newEventBus() *eventBus {
	return &eventBus{subs: make(map[int]chan Event)}
}

func (b *eventBus) publish(e Event) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.history = append(b.history, e)
	for _, ch := range b.subs {
		select {
		case ch <- e:
		default:
		}
	}
}

func (b *eventBus) subscribe() ([]Event, int, <-chan Event) {
	b.mu.Lock()
	defer b.mu.Unlock()
	id := b.nextID
	b.nextID++
	ch := make(chan Event, 64)
	b.subs[id] = ch
	hist := make([]Event, len(b.history))
	copy(hist, b.history)
	return hist, id, ch
}

func (b *eventBus) unsubscribe(id int) {
	b.mu.Lock()
	defer b.mu.Unlock()
	delete(b.subs, id)
}

// ── Progress helpers ──────────────────────────────────────────────────────────

type prog struct{ b *eventBus }

func (p *prog) running(text string)   { p.b.publish(Event{Type: "running", Text: text}) }
func (p *prog) ok(text string)        { p.b.publish(Event{Type: "ok", Text: text}) }
func (p *prog) fail(text string)      { p.b.publish(Event{Type: "error", Text: text}) }
func (p *prog) link(text, u string)   { p.b.publish(Event{Type: "link", Text: text, URL: u}) }
func (p *prog) auth(userCode, url string) {
	p.b.publish(Event{Type: "auth", Text: userCode, URL: url})
}
func (p *prog) confirm(pubKey string) { p.b.publish(Event{Type: "confirm", Text: pubKey}) }
func (p *prog) done()                 { p.b.publish(Event{Type: "done"}) }

// ── HTTP server ───────────────────────────────────────────────────────────────

func newHandler(b *eventBus, confirmCh chan<- struct{}) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write([]byte(uiHTML))
	})

	mux.HandleFunc("/events", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")

		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "streaming unsupported", http.StatusInternalServerError)
			return
		}

		hist, id, ch := b.subscribe()
		defer b.unsubscribe(id)

		send := func(e Event) {
			data, _ := json.Marshal(e)
			fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()
		}
		for _, e := range hist {
			send(e)
		}

		ctx := r.Context()
		for {
			select {
			case <-ctx.Done():
				return
			case e, ok := <-ch:
				if !ok {
					return
				}
				send(e)
			}
		}
	})

	mux.HandleFunc("/confirm", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		select {
		case confirmCh <- struct{}{}:
		default:
		}
		w.WriteHeader(http.StatusOK)
	})

	return mux
}

// ── Browser launcher ──────────────────────────────────────────────────────────

func openBrowser(u string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", u)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", u)
	default:
		cmd = exec.Command("xdg-open", u)
	}
	cmd.Start()
}

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

func authenticate(p *prog) (token, username string, err error) {
	// Step 1: request a device code
	resp, err := http.PostForm("https://github.com/login/device/code", url.Values{
		"client_id": {githubClientID},
		"scope":     {"read:org repo"},
	})
	if err != nil {
		return "", "", fmt.Errorf("requesting device code: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	vals, _ := url.ParseQuery(string(body))
	deviceCode := vals.Get("device_code")
	userCode   := vals.Get("user_code")
	verifyURI  := vals.Get("verification_uri")
	interval   := 5
	if v, err := strconv.Atoi(vals.Get("interval")); err == nil && v > 0 {
		interval = v
	}
	if deviceCode == "" {
		return "", "", fmt.Errorf("no device_code in response: %s", body)
	}

	// Show code in browser UI and auto-open GitHub
	p.auth(userCode, verifyURI)

	// Step 2: poll until the user authorises
	for {
		time.Sleep(time.Duration(interval) * time.Second)

		r, err := http.PostForm("https://github.com/login/oauth/access_token", url.Values{
			"client_id":   {githubClientID},
			"device_code": {deviceCode},
			"grant_type":  {"urn:ietf:params:oauth:grant-type:device_code"},
		})
		if err != nil {
			continue
		}
		b, _ := io.ReadAll(r.Body)
		r.Body.Close()

		v, _ := url.ParseQuery(string(b))
		if t := v.Get("access_token"); t != "" {
			token = t
			break
		}
		switch v.Get("error") {
		case "authorization_pending":
			// keep polling
		case "slow_down":
			interval += 5
		case "expired_token":
			return "", "", fmt.Errorf("code expired — please restart")
		case "access_denied":
			return "", "", fmt.Errorf("authorisation denied")
		default:
			if e := v.Get("error"); e != "" {
				return "", "", fmt.Errorf("auth error: %s — %s", e, v.Get("error_description"))
			}
		}
	}

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
	}
	path := fmt.Sprintf("/orgs/%s/memberships/%s", fermradOrg, username)
	if err := apiGet(token, path, &membership); err != nil {
		return fmt.Errorf("not a %s org member: %w", fermradOrg, err)
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

	for _, name := range []string{"id_ed25519", "id_ecdsa", "id_rsa"} {
		pubPath := filepath.Join(sshDir, name+".pub")
		data, readErr := os.ReadFile(pubPath)
		if readErr == nil && len(data) > 0 {
			return filepath.Join(sshDir, name), strings.TrimSpace(string(data)), nil
		}
	}

	pubKey, privPath, err = generateEd25519Key(sshDir, username)
	return
}

func generateEd25519Key(sshDir, comment string) (pubKeyStr, privPath string, err error) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return "", "", fmt.Errorf("generating key: %w", err)
	}

	privPEM, err := marshalOpenSSHPrivateKey(priv, comment)
	if err != nil {
		return "", "", fmt.Errorf("encoding private key: %w", err)
	}

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

	var checkInt [4]byte
	if _, err := io.ReadFull(rand.Reader, checkInt[:]); err != nil {
		return nil, err
	}

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
	writeStr(key)
	writeStr([]byte(comment))
	for i := 1; privBlob.Len()%8 != 0; i++ {
		privBlob.WriteByte(byte(i))
	}

	var pubBlob bytes.Buffer
	pubWriteStr := func(b []byte) {
		var l [4]byte
		binary.BigEndian.PutUint32(l[:], uint32(len(b)))
		pubBlob.Write(l[:])
		pubBlob.Write(b)
	}
	pubWriteStr([]byte("ssh-ed25519"))
	pubWriteStr(pub)

	var outer bytes.Buffer
	writeOuter := func(b []byte) {
		var l [4]byte
		binary.BigEndian.PutUint32(l[:], uint32(len(b)))
		outer.Write(l[:])
		outer.Write(b)
	}
	outer.WriteString("openssh-key-v1\x00")
	writeOuter([]byte("none"))
	writeOuter([]byte("none"))
	writeOuter([]byte{})
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

// installSkills writes the skills bundled into the binary to both locations
// Claude Code reads from:
//
//	~/.claude/skills/<name>/SKILL.md  — skills API (directory format)
//	~/.claude/commands/<name>.md      — commands API (flat-file format)
//
// Skills are embedded at build time from bundled/skills/, so each release
// ships a versioned snapshot. Existing files are overwritten.
func installSkills() (int, error) {
	home, _ := os.UserHomeDir()
	skillsDst := filepath.Join(home, ".claude", "skills")
	commandsDst := filepath.Join(home, ".claude", "commands")
	for _, dir := range []string{skillsDst, commandsDst} {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return 0, err
		}
	}

	entries, err := fs.ReadDir(bundledSkills, "bundled/skills")
	if err != nil {
		return 0, fmt.Errorf("reading bundled skills: %w", err)
	}

	installed := 0
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		content, err := bundledSkills.ReadFile("bundled/skills/" + e.Name() + "/SKILL.md")
		if err != nil {
			continue
		}
		skillDir := filepath.Join(skillsDst, e.Name())
		if err := os.MkdirAll(skillDir, 0755); err != nil {
			return installed, err
		}
		if err := os.WriteFile(filepath.Join(skillDir, "SKILL.md"), content, 0644); err != nil {
			return installed, fmt.Errorf("writing skills/%s: %w", e.Name(), err)
		}
		if err := os.WriteFile(filepath.Join(commandsDst, e.Name()+".md"), content, 0644); err != nil {
			return installed, fmt.Errorf("writing commands/%s: %w", e.Name(), err)
		}
		installed++
	}
	if installed == 0 {
		return 0, fmt.Errorf("no skills bundled in binary")
	}
	return installed, nil
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

	time.Sleep(3 * time.Second)
	var runs struct {
		WorkflowRuns []struct {
			HTMLURL string `json:"html_url"`
		} `json:"workflow_runs"`
	}
	listPath := fmt.Sprintf("/repos/%s/actions/workflows/%s/runs?per_page=1", infraRepo, provisionWorkflow)
	if err := apiGet(token, listPath, &runs); err == nil && len(runs.WorkflowRuns) > 0 {
		runURL = runs.WorkflowRuns[0].HTMLURL
	}
	return runURL, nil
}

// ── Setup flow ────────────────────────────────────────────────────────────────

func runSetup(p *prog, confirmCh <-chan struct{}) {
	p.running("Waiting for GitHub authorisation…")
	token, username, err := authenticate(p)
	if err != nil {
		p.fail(err.Error())
		return
	}
	p.ok("Signed in as " + username)

	// 2. Org membership
	p.running("Checking fermrad org membership…")
	if err := checkOrgMembership(token, username); err != nil {
		p.fail(err.Error())
		return
	}
	p.ok("Active fermrad member")

	// 3. SSH key
	p.running("Checking SSH key…")
	privPath, pubKey, err := findOrCreateSSHKey(username)
	if err != nil {
		p.fail("SSH key: " + err.Error())
		return
	}
	action := "found"
	if _, statErr := os.Stat(privPath + ".pub"); statErr != nil {
		action = "generated"
	}
	p.ok("SSH key " + action + ": " + privPath)

	// 4. SSH config
	p.running("Configuring SSH…")
	alreadySet, err := writeSSHConfig(username, privPath)
	if err != nil {
		p.fail("SSH config: " + err.Error())
		return
	}
	if alreadySet {
		p.ok(devServerHost + " already in ~/.ssh/config")
	} else {
		p.ok("Added " + devServerHost + " to ~/.ssh/config")
	}

	// 5. Skills
	p.running("Installing Claude Code skills…")
	n, err := installSkills()
	if err != nil {
		p.fail("Skills: " + err.Error())
		return
	}
	p.ok(fmt.Sprintf("Installed %d Claude Code skills → ~/.claude/skills/ and ~/.claude/commands/", n))

	// 6. Confirm — waits for user to click button in browser
	p.confirm(pubKey)
	<-confirmCh

	// 7. Provision
	p.running("Triggering server provisioning…")
	runURL, err := triggerProvisioning(token, username, pubKey)
	if err != nil {
		p.fail("Provisioning: " + err.Error())
		return
	}
	if runURL != "" {
		p.link("View provisioning job on GitHub Actions", runURL)
	}
	p.done()
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	if githubClientID == "PLACEHOLDER_OAUTH_CLIENT_ID" {
		fmt.Fprintln(os.Stderr, "Error: binary built without OAuth Client ID (developer build only).")
		os.Exit(1)
	}

	b := newEventBus()
	confirmCh := make(chan struct{}, 1)

	l, err := net.Listen("tcp", ":0")
	if err != nil {
		fmt.Fprintf(os.Stderr, "could not start server: %v\n", err)
		os.Exit(1)
	}
	addr := fmt.Sprintf("http://localhost:%d", l.Addr().(*net.TCPAddr).Port)

	srv := &http.Server{Handler: newHandler(b, confirmCh)}
	go srv.Serve(l)

	time.Sleep(50 * time.Millisecond)
	fmt.Printf("Opening setup UI at %s\n", addr)
	openBrowser(addr)

	p := &prog{b: b}
	go runSetup(p, confirmCh)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt)
	<-quit
}
