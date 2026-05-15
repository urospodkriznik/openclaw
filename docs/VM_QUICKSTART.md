# GCP VM quick start

One-page path for a **fresh Linux VM** (Gemini + Telegram + optional gog + GitHub deploy).

## Cheat sheet (copy in order)

| Step | Where | Command / action |
|------|--------|------------------|
| 1 | GCP | VM **e2-small+**, service account → Secret Manager accessor |
| 2 | VM | `git clone … ~/openclaw` (or your folder) → `cd` there |
| 3 | VM | `make deploy-instances-init` → edit `deploy/instances.json` (`path` = clone folder name) |
| 4 | GitHub | Variable `DEPLOY_INSTANCES_JSON` = same JSON one line; secrets `GCP_VM_*`; deploy user SSH key in `authorized_keys` |
| 5 | VM | `make init-vm` → edit `.env` → `SKIP_GOG=1 INSTALL_HOST_DEPS=1 make init-vm` |
| 6 | VM | `gog auth …` on host (see below) → **`make setup-gog`** |
| 7 | Telegram | Message bot → `/approve` if needed → `/new` |

**Mac:** stop local stack if it uses the same Telegram bot.

---

## 1. Clone and deploy manifest

```bash
mkdir -p ~/openclaw && cd ~/openclaw
git clone https://github.com/<you>/<repo>.git .
make deploy-instances-init
# edit deploy/instances.json — "path" must match this folder name (e.g. openclaw)
```

Mirror that JSON in GitHub → **Settings → Variables →** `DEPLOY_INSTANCES_JSON`.

SSH deploy: [GITHUB_ACTIONS.md](GITHUB_ACTIONS.md) (deploy user, `GCP_VM_SSH_KEY`, `authorized_keys` after a clean VM).

## 2. Configure `.env`

```bash
make init-vm   # creates .env from example — edit, then continue
```

Typical production values:

```bash
USE_GSM_SECRETS=true
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_LOCATION=europe-southwest1
GSM_TELEGRAM_BOT_TOKEN_SECRET=telegram-bot-token-vm
GSM_GEMINI_API_KEY_SECRET=gemini-api-key
LLM_PROVIDER=google
GEMINI_MODEL=gemini-3-flash-preview

# gog (needed before make setup-gog)
GOG_KEYRING_BACKEND=file
GOG_KEYRING_PASSWORD=your-long-random-password
GOG_ACCOUNT=you@gmail.com
```

Use a **new** Telegram bot token in GSM (not the same as your Mac).

## 3. First install (no gog yet)

```bash
SKIP_GOG=1 INSTALL_HOST_DEPS=1 make init-vm
```

Does: host Docker (if needed) → reown → bootstrap → GSM → compose up → Telegram → `/healthz`.

## 4. gog (one command after host OAuth)

**On the VM** (headless: `--manual` in your laptop browser):

```bash
set -a && source .env && set +a
gog auth credentials /path/to/client_secret.json
gog auth add you@gmail.com --services gmail,calendar,drive,docs,sheets --manual
```

Then:

```bash
make setup-gog
```

That installs Linux `gog`, runs `sync-gog-config`, reowns, recreates the gateway, pushes the gog volume, and runs `gog auth doctor` in the container.

Manual equivalents: `make install-gog-linux` → `make sync-gog-config` → `make restart` — prefer **`make setup-gog`**.

## 5. Telegram

1. Message the VM bot (`ping`).
2. Pairing: `./scripts/docker-compose.sh run -T --rm openclaw-cli pairing list telegram` → `pairing approve …`
3. `/new` and test.

## 6. Updates

| Action | Command |
|--------|---------|
| On VM (git pull + restart) | `make deploy` |
| From GitHub | push to `main` |
| gog token refresh on host | `make setup-gog` (or `make sync-gog-config && make restart`) |

## Wipe and reinstall

```bash
make wipe-vm
# if Permission denied on .openclaw-config (UID 1000):
sudo bash -c 'cd /home/deployuser/openclaw && ./scripts/wipe-vm-state.sh'
```

Then repeat from §2.

## Troubleshooting

| Symptom | Doc |
|---------|-----|
| `EACCES` / Missing config | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — `chmod 755 .openclaw-config`, `reown --container` |
| gog / empty keyring | [GOOGLE_INTEGRATIONS.md](GOOGLE_INTEGRATIONS.md), `make setup-gog` |
| Deploy SSH / wrong path | [GITHUB_ACTIONS.md](GITHUB_ACTIONS.md) |
| `codex not registered` | Use Gemini or latest `bootstrap-config.sh` |

```bash
./scripts/diagnose-openclaw-config.sh
make logs
```
