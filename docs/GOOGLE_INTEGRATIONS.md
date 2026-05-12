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

**Sending mail or reading inbox in chat** usually requires an **OpenClaw skill** (Gmail, SMTP, etc.) from **ClawHub** / upstream docs—not this template alone.

OpenClaw can also connect Gmail **push** via **Pub/Sub** when explicitly configured. This template keeps hooks **off** by default:

- `.env`: `ENABLE_GMAIL_HOOKS=false`, `OPENCLAW_SKIP_GMAIL_WATCHER=1` (default in Compose).

To explore enabling it, read the official guide: [Gmail Pub/Sub](https://docs.openclaw.ai/automation/gmail-pubsub). Expect additional GCP resources (topics, IAM bindings) and OAuth/consent considerations.

## Google Calendar (from chat — not built-in)

There is **no** Telegram-style “Calendar channel” in this template. To let the agent **list/create/update events** from chat, add an **OpenClaw skill** (or MCP) that wraps the **Google Calendar API**.

**Typical path**

1. **Discover / install a skill** — [ClawHub](https://clawhub.ai/) and native OpenClaw flows: `openclaw skills search "calendar"` then `openclaw skills install <slug>` (see [ClawHub](https://documentation.openclaw.ai/clawhub)). Example public listing: [Google Calendar on ClawHub](https://clawhub.ai/skills/google-calendar) (verify the slug and version match your gateway).
2. **GCP** — Enable **Google Calendar API** on the same (or linked) Google Cloud project as your OAuth client or service account.
3. **Auth** — Most skills expect **OAuth** (user consent) or a **workspace admin** setup with **domain-wide delegation** for a service account. Store refresh tokens / secrets only in OpenClaw’s auth store or Secret Manager—**never** in git.
4. **Automation without chat** — You can also use OpenClaw **cron** / scheduled tasks ([automation index](https://docs.openclaw.ai/automation/gmail-pubsub)) to poll Calendar; that is separate from “agent replies in Telegram.”

This repo does **not** configure Calendar API credentials for you.

## Google Drive (from chat — not built-in)

Same model as Calendar: **no** first-class Drive channel here. For **upload, download, search, or edit** files from chat, install a **Drive- or Workspace-capable skill** (or MCP) and complete its auth.

**Typical path**

1. **ClawHub / skills** — `openclaw skills search "drive"` or `"google workspace"` and install the skill your operator trusts; follow that skill’s `SKILL.md` for scopes and setup.
2. **GCP** — Enable **Google Drive API** on your project when the skill uses Google Cloud OAuth or a service account in that project.
3. **Auth** — Usually **OAuth** for “my Drive”; shared drives / org-wide access may need admin configuration and narrower scopes per skill docs.

This repo does **not** mount Drive-specific secrets or enable Drive API by default.

## Secret Manager + IAM vs OAuth

- **GCP production (this template):** use VM IAM + **Google Secret Manager** for bot tokens and optional API keys (OpenAI, Gemini developer API via `GSM_*` env vars and `fetch-secrets-gsm.sh`).
- **OAuth:** still common for user-owned Gmail/Calendar/Drive when you add **skills**; more moving parts (consent screen, refresh tokens). Prefer OpenClaw’s auth store or GSM for those secrets—**never** commit tokens.
