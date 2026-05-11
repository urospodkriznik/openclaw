# Google integrations

## Vertex AI (default LLM)

- **Provider:** `google-vertex` (see [Model providers](https://docs.openclaw.ai/concepts/model-providers)).
- **Auth:** Application Default Credentials via VM-attached service account (metadata server).
- **Env:** `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`.
- **Model:** `VERTEX_MODEL` in `.env`; primary ref `google-vertex/<VERTEX_MODEL>` in `openclaw.json`.

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

- **GCP production (this template):** use VM IAM + **Google Secret Manager** for bot tokens and optional API keys.
- **OAuth:** still common for user-owned Gmail/Calendar; more moving parts (consent screen, refresh tokens). Document your chosen path in a private runbook—**never** commit tokens.
