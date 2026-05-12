# Troubleshooting

## `fetch-secrets-gsm.sh` fails

When `USE_GSM_SECRETS=true`, ensure VM IAM and secret names are correct:

```bash
gcloud auth list
gcloud secrets versions access latest --secret "$GSM_TELEGRAM_BOT_TOKEN_SECRET" --project "$GSM_PROJECT_ID"
# If configured, test optional secrets the same way (replace with your secret names):
# gcloud secrets versions access latest --secret "$GSM_GEMINI_API_KEY_SECRET" --project "$GSM_PROJECT_ID"
./scripts/validate-env.sh
./scripts/fetch-secrets-gsm.sh
```

## `bootstrap-config.sh`: Permission denied on `.openclaw-config/.env`

After the gateway has run, bind-mounted files under **`.openclaw-config`** are often owned by **UID 1000** (the `node` user in the image). Your SSH deploy user then cannot overwrite **`openclaw.json`** or **`.openclaw-config/.env`** during CI.

**Automated path:** [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) and **`./scripts/deploy.sh`** run **`./scripts/reown-openclaw-mounts.sh --host`** before bootstrap and **`--container`** before **`docker compose up`**. That needs **passwordless `sudo`** for the **`chown`** path returned by **`command -v chown`** on the VM (often **`/usr/bin/chown`** — your **`NOPASSWD:`** line must use that exact path). See [GITHUB_ACTIONS.md](GITHUB_ACTIONS.md).

**Manual once:**

```bash
sudo chown -R "$(id -un):$(id -gn)" .openclaw-config workspace
# after bootstrap, before starting containers again:
sudo chown -R 1000:1000 .openclaw-config workspace
```

## Permission errors (`EACCES`) under `/home/node/.openclaw`

The container runs as **UID 1000**. Fix host ownership (same as **`reown-openclaw-mounts.sh --container`**):

```bash
sudo chown -R 1000:1000 .openclaw-config workspace
```

## Healthcheck fails (`curl: (52) Empty reply` or immediate failure)

Right after **`docker compose up -d`**, the host port can be open while the Node process is still booting; **`scripts/healthcheck.sh`** retries **`/healthz`** for up to **`HEALTHCHECK_MAX_WAIT_SECONDS`** (default **180**) every **`HEALTHCHECK_INTERVAL_SECONDS`** (default **3**).

1. `docker compose logs --tail=200 openclaw-gateway`
2. On the VM: `ss -tlnp | grep 18789` (or your **`OPENCLAW_GATEWAY_PORT`**).
3. On very small instances, set in **`.env`**: `HEALTHCHECK_MAX_WAIT_SECONDS=300` (or higher).
4. Increase **`start_period`** in **`docker-compose.yml`** if Docker’s own health state flaps on cold start.

## Vertex errors (`permission denied`, `not found`, `API key`)

- Confirm **Vertex AI API** enabled and SA has `roles/aiplatform.user`.
- Verify **`GOOGLE_CLOUD_LOCATION`** supports the chosen model.
- Run `gcloud auth application-default print-access-token` **on the host** only for debugging (do not paste tokens into chats).

## Telegram repeats the same intro / ignores prior messages

If every DM looks like a **first boot** (“fresh workspace”, who am I, etc.), the gateway may be **re-classifying turns as “new”** and re-applying the **startup prelude** each time.

This template’s **`./scripts/bootstrap-config.sh`** writes:

- **`session.dmScope: "main"`** — one shared DM session for the default agent (good for a single-owner bot).
- **`agents.defaults.startupContext.applyOn: ["reset"]`** — prelude runs on **explicit reset** paths, not on every `new` signal.
- **`commands.text: true`** — Telegram slash commands are parsed from message text when `bot_command` entities are missing ([upstream discussion](https://github.com/openclaw/openclaw/issues/27012)).

Re-run **`./scripts/bootstrap-config.sh`** on the VM (or redeploy), then **`docker compose restart openclaw-gateway`**.

If it persists, check gateway logs for **session key** stability and inspect sessions per [Session management](https://docs.openclaw.ai/concepts/session) (e.g. **`docker compose exec openclaw-cli sh -lc 'node dist/index.js sessions --help'`** on your OpenClaw version).

## Exec approval timed out / agent “won’t re-run” shell or `openclaw` commands

Default **`SAFE_MODE`** sets **`tools.exec.ask: on-miss`** and **`askFallback: deny`**. [Exec approvals](https://docs.openclaw.ai/tools/exec-approvals) need a **Control UI / companion** to approve; on a **headless** gateway, prompts expire with nobody attached.

**Options:**

1. **SSH tunnel** the Control UI: `ssh -L 18789:127.0.0.1:18789 user@vm` then open `http://127.0.0.1:18789/`.
2. **Single trusted VM:** **`TRUSTED_HEADLESS_EXEC=true`** and **`I_ACCEPT_HEADLESS_EXEC_RISK=1`** in **`.env`**, then **`./scripts/bootstrap-config.sh`** + gateway restart ([docs/SECURITY.md](SECURITY.md)).
3. Upstream break-glass chat commands (e.g. **`/elevated full`**) for operators who understand the risk.

## Google Workspace from chat (Gmail, Calendar, Drive)

This template does **not** install Gmail, Calendar, or Drive skills. The agent only gets those abilities after you add skills (or MCP) and auth.

| Goal | What to do |
|------|------------|
| **Send/read email** | Install a **Gmail or SMTP skill** from [ClawHub](https://documentation.openclaw.ai/clawhub) (`openclaw skills search "gmail"`). Optional automation: [Gmail Pub/Sub](https://docs.openclaw.ai/automation/gmail-pubsub) (not the same as “send mail” in chat). |
| **Calendar events** | Install a **Calendar API skill** (`openclaw skills search "calendar"`). Enable **Google Calendar API** in GCP; OAuth or service account per skill. |
| **Drive files** | Install a **Drive / Workspace skill** (`openclaw skills search "drive"`). Enable **Google Drive API** in GCP; OAuth per skill. |

Details, API enablement, and OAuth vs Secret Manager: **[docs/GOOGLE_INTEGRATIONS.md](GOOGLE_INTEGRATIONS.md)**.

## Telegram bot silent

- Re-run channel registration with a fresh token if rotated.
- Check gateway logs for Telegram adapter errors.
- Confirm outbound HTTPS is allowed from the VM (NAT/firewall).
- If using GSM mode, regenerate runtime env: `./scripts/fetch-secrets-gsm.sh`.

## GitHub Actions deploy fails SSH

- Verify `GCP_VM_HOST`, user, key, and port (**22** if secret omitted).
- Ensure the deploy user can run **passwordless** `docker` (group membership).

## `validate-env` complains about Telegram

Production validation defaults to `VALIDATION_LEVEL=full`. For compose-only checks:

```bash
VALIDATION_LEVEL=minimal ./scripts/validate-env.sh
```

## Out of memory (exit code 137)

- Move to a larger machine type or raise swap.
- Reduce concurrent workloads; avoid browser automation plugins on e2-micro.

## Further reading

- [OpenClaw Docker](https://docs.openclaw.ai/install/docker)
- [Docker VM runtime](https://docs.openclaw.ai/install/docker-vm-runtime)
