# GitHub Actions

## Workflows

| File | When | What |
|------|------|------|
| [.github/workflows/ci.yml](../.github/workflows/ci.yml) | PR + push | ShellCheck, compose config, required files, secret-pattern scan |
| [.github/workflows/deploy.yml](../.github/workflows/deploy.yml) | Push to `main` or `master` + manual | SSH deploy to your VM (pulls whichever branch exists on `origin`) |

## One-time VM preparation

1. Clone **this** repository on the VM (same path you will use in deploy):

   ```bash
   mkdir -p ~/openclaw-gcp-agent && cd ~/openclaw-gcp-agent
   git clone https://github.com/<you>/<repo>.git .
   ```

2. Attach a VM service account with IAM:
   - `roles/aiplatform.user`
   - `roles/secretmanager.secretAccessor`

3. Create a starter `.env` on the VM with non-secret defaults (paths, image, autonomy flags), and set:
   - `USE_GSM_SECRETS=true`
   - `GSM_PROJECT_ID=<your-project>` (optional if equal to `GOOGLE_CLOUD_PROJECT`)
   - `GSM_TELEGRAM_BOT_TOKEN_SECRET=<secret-name>`
   - `GSM_OPENAI_API_KEY_SECRET=<optional-secret-name>`

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
DEPLOY_PATH="${DEPLOY_PATH:-$HOME/openclaw-gcp-agent}"
```

To use `/opt/...`, log in once and `export DEPLOY_PATH=/opt/openclaw-gcp-agent` in the server user’s `~/.profile`, **or** edit the workflow script to match your layout.

## What deploy does

1. `git fetch` + fast-forward `main`.
2. Ensures `USE_GSM_SECRETS=true` in `.env` (production default).
3. `./scripts/bootstrap-config.sh` + `./scripts/validate-env.sh`.
4. `./scripts/fetch-secrets-gsm.sh` to generate `.env.generated` from Secret Manager.
5. `docker compose pull && up -d`.
6. `./scripts/healthcheck.sh`; on failure prints recent logs.

## Branch protection

Enable required status checks for `ci` on PRs before merging to `main`.
