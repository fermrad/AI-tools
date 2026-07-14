# ferm-setup

One-command developer setup tool for the Fermrad org. Downloads as a single binary — no prerequisites required.

## What it does

1. **Authenticates with GitHub** via OAuth (browser-based, no token to paste)
2. **Verifies fermrad org membership**
3. **Sets up an SSH key** — finds your existing key or generates a new Ed25519 one
4. **Configures `~/.ssh/config`** with the dev server host
5. **Installs Claude Code skills and commands** into `~/.claude/skills/` and `~/.claude/commands/`
6. **Provisions your account on the dev server** — triggers the GitHub Actions workflow that creates your user, clones AI-tools, authenticates Claude, and starts a remote session

## Usage

### Download

Go to the [latest release](https://github.com/fermrad/AI-tools/releases/latest) and download the file for your platform:

| Platform | File |
|---|---|
| macOS (Apple Silicon) | `ferm-setup-darwin-arm64.zip` |
| macOS (Intel) | `ferm-setup-darwin-amd64.zip` |
| Linux | `ferm-setup-linux-amd64.zip` |
| Windows | `ferm-setup-windows-amd64.exe` |

### Run

**macOS / Linux:** Unzip, then right-click the binary → Open (to bypass Gatekeeper on macOS).

**Windows:** Double-click the `.exe`.

A browser window opens showing live progress. The only action required is clicking "Connect with GitHub" to authorise, and confirming your SSH key before it is added to the server.

### Re-running

The tool is idempotent — safe to run again if you get a new machine, regenerate your SSH key, or want to update the installed skills to the latest version.

## Development

### Local build

```bash
cd claude/setup-tool
./build.sh
```

`build.sh` copies the current skills from `claude/skills/` into `bundled/` (required by `//go:embed`) then runs `go build`.

### Releasing

Bump `claude/setup-tool/VERSION`, open a PR, merge. The build workflow:

- Fails the PR check if the version regresses below the latest published release
- On merge: overwrites the existing release if the version is unchanged, or creates a new one if the version is higher

### OAuth App

The binary requires a GitHub OAuth App Client ID injected at build time via `-ldflags`. The Client ID is stored as the `FERM_SETUP_OAUTH_CLIENT_ID` org secret in fermrad. Authentication uses the [Authorization Code + PKCE flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps) — no client secret is embedded in the binary.
