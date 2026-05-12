# GitHub Actions

## Workflows

| File | When | What |
|------|------|------|
| [.github/workflows/ci.yml](../.github/workflows/ci.yml) | PR + push | ShellCheck, compose config, required files, secret-pattern scan |
| [.github/workflows/deploy.yml](../.github/workflows/deploy.yml) | Push to `main` or `master` + manual | SSH deploy to your VM (pulls whichever branch exists on `origin`) |

## One-time VM preparation

1. Clone **this** repository on the VM (same path you will use in deploy):

   ```bash
   mkdir -p ~/openclaw && cd ~/openclaw
   git clone https://github.com/<you>/<repo>.git .
   ```

2. Attach a VM service account with IAM:
   - `roles/secretmanager.secretAccessor` (GSM)
   - `roles/aiplatform.user` (optional — only if you use Vertex / `google-vertex`)

3. **Deploy user + `sudo`:** the deploy workflow runs **`./scripts/reown-openclaw-mounts.sh`** so the SSH user can refresh **`.openclaw-config`** after Docker has created files as **UID 1000**, then hands ownership back to **1000:1000** before **`docker compose up`**. Configure **passwordless** `sudo` for the **`chown`** binary that exists on the VM (path must match what `command -v chown` prints — often **`/usr/bin/chown`** on Ubuntu):

   ```text
   yourdeployuser ALL=(ALL) NOPASSWD: /usr/bin/chown
   ```

   On some images `chown` is **`/bin/chown`**; if `sudo -n "$(command -v chown)" --help` still fails after editing sudoers, add that path too (comma-separated in `NOPASSWD`).

   See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if bootstrap fails with **Permission denied** on **`.openclaw-config/.env`**.

4. Create a starter `.env` on the VM with non-secret defaults (paths, image, autonomy flags), and set:
   - `USE_GSM_SECRETS=true`
   - `GSM_PROJECT_ID=<your-project>` (optional if equal to `GOOGLE_CLOUD_PROJECT`)
   - `GSM_TELEGRAM_BOT_TOKEN_SECRET=<secret-name>`
   - `GSM_OPENAI_API_KEY_SECRET=<optional-secret-name>`
   - `GSM_GEMINI_API_KEY_SECRET=<optional-secret-name>` (Gemini developer API key for provider `google`)
   - `GEMINI_MODEL` (defaults in `.env.example`; override if needed)
   - For local keys instead of GSM: `GEMINI_API_KEY` in `.env` (never commit)

## Secrets

Create the following in **GitHub → Settings → Secrets and variables → Actions**:

| Secret | Notes |
|--------|------|
| `GCP_VM_HOST` | External IP or hostname |
| `GCP_VM_USER` | e.g. `ubuntu` |
| `GCP_VM_SSH_KEY` | **Private** half of an SSH key pair |
| `GCP_VM_PORT` | Optional; if unset, workflow uses **22** |

## Deploy path

The remote script defaults to:

```bash
DEPLOY_PATH="${DEPLOY_PATH:-$HOME/openclaw}"
```

To use another directory (e.g. `/opt/openclaw`), log in once and `export DEPLOY_PATH=/opt/openclaw` in the server user’s `~/.profile`, **or** edit the default in [.github/workflows/deploy.yml](../.github/workflows/deploy.yml).

## What deploy does

1. `git fetch` + fast-forward `main`.
2. Ensures `USE_GSM_SECRETS=true` in `.env` (production default).
3. **`./scripts/reown-openclaw-mounts.sh --host`** (so bootstrap can write bind-mounted config).
4. `./scripts/bootstrap-config.sh` + `./scripts/validate-env.sh`.
5. `./scripts/fetch-secrets-gsm.sh` to generate `.env.generated` from Secret Manager.
6. **`./scripts/reown-openclaw-mounts.sh --container`** (restore **UID 1000** ownership for the gateway image).
7. `docker compose pull && up -d`.
8. `./scripts/healthcheck.sh`; on failure prints recent logs.

## Branch protection

Enable required status checks for `ci` on PRs before merging to `main`.
