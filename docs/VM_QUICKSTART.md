# GCP VM quick start (clean install)

Use this for a **fresh VM** or after wiping a broken install. Goal: **one deploy user**, **one new Telegram bot**, **Gemini**, **no gog** on first pass.

## Before you start

| Item | Recommendation |
|------|----------------|
| VM size | **e2-small** (2 GB) or larger; e2-micro is fragile |
| Deploy user | One Linux user for clone + `make init-vm` (passwordless `sudo` for `chown` helps — see [GITHUB_ACTIONS.md](GITHUB_ACTIONS.md)) |
| Telegram | **New bot** from [@BotFather](https://t.me/BotFather) — do not reuse the Mac/local bot token |
| LLM | `LLM_PROVIDER=google` (default) + Gemini API key in GSM or `.env` |
| Mac | Stop local OpenClaw (`docker compose down`) so it does not poll the same bot |

## 1. Wipe old state (on the VM)

From the repo root (e.g. `~/openclaw-primary` or `~/openclaw`):

```bash
make wipe-vm
# optional: reclaim disk
./scripts/wipe-vm-state.sh --prune-docker
```

Keeps `.env` so you can edit GSM names and provider. To delete `.env` too: `./scripts/wipe-vm-state.sh --full`.

If you see **`Permission denied`** removing `.openclaw-config` (files owned by Docker UID **1000**), run wipe as an admin:

```bash
sudo bash -c 'cd /home/deployuser/openclaw-primary && ./scripts/wipe-vm-state.sh'
```

(If the deploy user cannot `sudo`, use an admin account with sudo.)

## 2. Update secrets in GCP (new bot)

1. Create a **new** bot token in BotFather.
2. Store it in Secret Manager (new secret version or new secret id).
3. Point `GSM_TELEGRAM_BOT_TOKEN_SECRET` in `.env` at that secret.
4. Ensure the VM service account has **Secret Manager Secret Accessor**.

## 3. Configure `.env`

Minimum for GSM + Gemini:

```bash
USE_GSM_SECRETS=true
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_LOCATION=europe-southwest1
GSM_TELEGRAM_BOT_TOKEN_SECRET=telegram-bot-token-vm   # example name
GSM_GEMINI_API_KEY_SECRET=gemini-api-key
LLM_PROVIDER=google
GEMINI_MODEL=gemini-3-flash-preview
OPENCLAW_CONFIG_DIR=./.openclaw-config
OPENCLAW_WORKSPACE_DIR=./workspace
```

Do **not** set `OPENAI_*` for this path. Leave `LLM_PROVIDER` unset or `google`.

Scaffold if needed:

```bash
make init-vm    # creates .env from example — edit, then run again
```

## 4. Install (skip gog on first success)

```bash
SKIP_GOG=1 make init-vm
```

Or first boot without Docker yet:

```bash
INSTALL_HOST_DEPS=1 SKIP_GOG=1 make init-vm
```

This runs: reown → bootstrap → GSM fetch → compose up → Telegram `channels add` → `/healthz`.

## 5. Telegram

1. Message the **new** bot: `ping`
2. If pairing is required:

```bash
./scripts/docker-compose.sh run -T --rm openclaw-cli pairing list telegram
./scripts/docker-compose.sh run -T --rm openclaw-cli pairing approve telegram <CODE>
```

Or approve in the Telegram chat with **`/approve`** when the bot prompts you.

3. `/new` then ask a short question.

## 6. If something fails

| Symptom | See |
|---------|-----|
| `Missing config` / `EACCES` | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — config dir `755`, `reown --container` |
| `codex is not registered` | You used OpenAI `openai/gpt-*` without PI — use Gemini or pull latest `bootstrap-config.sh` |
| No Telegram logs | Wrong bot token, or Mac still polling — `deleteWebhook` + stop Mac stack |
| Healthcheck timeout | Wait longer: `HEALTHCHECK_MAX_WAIT_SECONDS=180 ./scripts/healthcheck.sh` |

Diagnostics:

```bash
./scripts/diagnose-openclaw-config.sh
./scripts/docker-compose.sh logs --tail=80 openclaw-gateway
```

## 7. After it works

- Add gog: install Linux gog, `gog auth`, `make sync-gog-config`, `make restart`
- Wire GitHub Actions deploy to the **same clone path** on the VM
- Optional: OpenAI later with `LLM_PROVIDER=openai` and `OPENAI_MODEL=gpt-4.1-mini` (bootstrap sets PI runtime)
