# Google integrations

## Gemini developer API (default)

- **Provider:** `google` ([Model providers](https://docs.openclaw.ai/concepts/model-providers)).
- **Auth:** **`GEMINI_API_KEY`** from `.env`, or **Secret Manager** via **`GSM_GEMINI_API_KEY_SECRET`** + **`./scripts/fetch-secrets-gsm.sh`** → **`.env.generated`**.
- **Model:** **`GEMINI_MODEL`** in `.env` (no `google/` prefix); **`./scripts/bootstrap-config.sh`** sets **`primary`** to **`google/<GEMINI_MODEL>`** in `openclaw.json`.
- **Verify ids:** `docker compose run -T --rm openclaw-cli models list --provider google`.

## Vertex AI (optional enterprise path)

- **Provider:** `google-vertex` when your OpenClaw image loads that plugin.
- **Auth:** Application Default Credentials via VM-attached service account (metadata server).
- **Env:** `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`.
- **Model:** set **`agents.defaults.model.primary`** to **`google-vertex/<model-id>`** manually (see Vertex model list for your region).

Enable **Vertex AI API** and grant the SA `roles/aiplatform.user`.

## Gmail (optional, advanced)

OpenClaw can connect Gmail push via **Pub/Sub** when explicitly configured. This template keeps hooks **off** by default:

- `.env`: `ENABLE_GMAIL_HOOKS=false`, `OPENCLAW_SKIP_GMAIL_WATCHER=1` (default in Compose).

To explore enabling it, read the official guide: [Gmail Pub/Sub](https://docs.openclaw.ai/automation/gmail-pubsub). Expect additional GCP resources (topics, IAM bindings) and OAuth/consent considerations.

## Google Calendar

There is **no** turnkey “Calendar channel” documented like Telegram. Practical options:

- Periodic checks via OpenClaw **cron** / automation (see [Scheduled tasks](https://docs.openclaw.ai/automation/gmail-pubsub) index for cron).
- Custom tooling via **Google Calendar API** (OAuth or service account with domain-wide delegation)—**TODO:** wire as a skill/MCP in your fork; not enabled in this template.

## Google Drive

Same story as Calendar: treat as **optional API integration** you add explicitly. **Do not** imply this repo grants Drive access out of the box.

## Secret Manager + IAM vs OAuth

- **GCP production (this template):** use VM IAM + **Google Secret Manager** for bot tokens and optional API keys (OpenAI, Gemini developer API via `GSM_*` env vars and `fetch-secrets-gsm.sh`).
- **OAuth:** still common for user-owned Gmail/Calendar; more moving parts (consent screen, refresh tokens). Document your chosen path in a private runbook—**never** commit tokens.
