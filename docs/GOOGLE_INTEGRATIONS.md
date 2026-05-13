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

## Same Google account as the GCP project owner?

Often **yes**: the person who created the GCP project can use the **same** Google identity for Gmail and Calendar in skills. That does **not** make auth automatic.

- **What already “just works” on the VM:** **Gemini** (`GEMINI_API_KEY` / GSM) and **GCP APIs** the **VM service account** is allowed to call (Secret Manager, optional Vertex). Those are **not** your personal Gmail or Calendar.
- **Gmail / Calendar / Drive as you:** Google still requires either **OAuth** (sign in once; skills store refresh tokens under the bind-mounted **`.openclaw-config`**) or, for SMTP-only paths, an **App Password**. The project owner account does not get a shortcut that skips that.
- **Usually easier than IMAP:** install **OAuth-based** Gmail and Calendar skills from [ClawHub](https://documentation.openclaw.ai/clawhub), create an **OAuth client** in **Google Cloud Console** in this **same** project (Desktop / Web app per skill docs), enable **Gmail** / **Calendar** APIs, run the skill’s login flow once with **that same account**. After that it feels like one Google account for everything.
- **Google Workspace (company domain):** admins can grant **domain-wide delegation** to a **service account** so automation does not use your personal password—more setup, not simpler for a solo `@gmail.com` consumer mailbox.

## Step-by-step: OAuth for Gmail, Calendar, and Drive (same GCP project)

Use this when you want the **same personal Google account** that owns the GCP project to power **mail + calendar + Drive** in chat via **skills** (recommended over IMAP/App Passwords when the skill supports OAuth).

**Assumptions:** OpenClaw is running with this repo’s **Docker Compose** on a host where you can SSH; config persists under **`OPENCLAW_CONFIG_DIR`** (default **`./.openclaw-config`**). All shell examples run from the directory that contains **`docker-compose.yml`** (on the VM, often **`~/openclaw`**).

### 1) Pick the skills (and read their docs)

1. Open [ClawHub](https://clawhub.ai/) or use search inside OpenClaw (see [ClawHub docs](https://documentation.openclaw.ai/clawhub)).
2. Choose **one Gmail-oriented skill** and **one Calendar skill** (and optionally **Drive**) that explicitly support **Google OAuth** (not only IMAP).
3. Open each skill’s **`SKILL.md`** / upstream page and note: **required GCP APIs**, **OAuth client type** (Desktop vs Web), **redirect URIs** (if Web), **env vars or config keys**, and the exact **CLI commands** for install + login.

Exact slugs change over time—always follow the skill you picked, not a fixed slug in this file.

### 2) Enable Google APIs on your GCP project

1. In [Google Cloud Console](https://console.cloud.google.com/), select the **same project** as **`GOOGLE_CLOUD_PROJECT`** on the VM.
2. Go to **APIs & Services → Library** and enable at least:
   - **Gmail API** (if the mail skill uses Gmail API),
   - **Google Calendar API** (for calendar skills),
   - **Google Drive API** (for Drive skills).F
3. Optional CLI (same project):

   ```bash
   gcloud services enable gmail.googleapis.com calendar.googleapis.com drive.googleapis.com --project "$GOOGLE_CLOUD_PROJECT"
   ```

### 3) Configure the OAuth consent screen

1. **APIs & Services → OAuth consent screen**.
2. **User type:** **External** for a personal `@gmail.com` account (or **Internal** only if this is a Google Workspace org project).
3. Fill **App name**, **User support email**, **Developer contact**.
4. **Scopes:** add only what your **skill documentation** lists (principle of least privilege). Many skills document exact scope strings.
5. If the app stays in **Testing** (typical for a personal project), add your Google account under **Test users** so you can sign in during development.

Publishing the app to **Production** is optional and involves Google verification if you use sensitive/restricted scopes; for a private VM and your own account, **Testing + test users** is often enough.

### 4) Create an OAuth client ID

1. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
2. **Application type:** start with **Desktop app** unless the skill’s `SKILL.md` requires **Web application** (Web apps need authorized redirect URIs exactly as documented).
3. Save the **Client ID** and **Client Secret** somewhere safe (password manager). You will paste them where the skill says (env file, `openclaw.json` fragment, or a prompt)—**never** commit them to git.

### 5) Install the skills in the container

From the machine that has `docker-compose.yml`:

```bash
./scripts/docker-compose.sh run -T --rm openclaw-cli --help
./scripts/docker-compose.sh run -T --rm openclaw-cli skills search "gmail"
./scripts/docker-compose.sh run -T --rm openclaw-cli skills search "calendar"
# Then install using the slug from the listing, e.g.:
# ./scripts/docker-compose.sh run -T --rm openclaw-cli skills install <slug>
```

If your image uses different subcommands, check **`docker compose run -T --rm openclaw-cli --help`** and the [OpenClaw CLI](https://docs.openclaw.ai/) / skill page.

### 6) Complete OAuth sign-in once (headless VM)

1. Follow the **skill’s login / auth** instructions (often `auth`, `login`, or a wizard subcommand).
2. On a **headless** server, the CLI usually prints a **URL** and sometimes a **code**. Open the URL in a **browser on your laptop**, sign in with the **same Google account**, approve scopes, then paste any code or redirect result back into the SSH session as instructed.
3. OpenClaw stores tokens under the bind-mounted config tree (see [OpenClaw Docker — Storage and persistence](https://docs.openclaw.ai/install/docker)); with this template that is the host’s **`.openclaw-config`** directory.

If the flow expects a local browser on the VM, use an SSH tunnel to the gateway or run the auth step from a machine with a browser, then copy the resulting token files into **`.openclaw-config`** only if the skill documents that path—prefer the official CLI flow.

### 7) Restart the gateway and smoke-test

```bash
./scripts/docker-compose.sh restart openclaw-gateway
```

In Telegram (or your channel), ask the agent to do something narrow (e.g. list calendars, list labels, or send a test message to yourself) using the tool names from the skill. If you get **403 / access denied**, re-check **scopes**, **test users**, and **APIs enabled** for the same project as the OAuth client.

### 8) Production hardening (optional)

- Keep **OAuth client secrets** out of git; optionally store them in **Secret Manager** and inject via a small hook or env if the skill supports env-based configuration.
- Restrict **Test users** to accounts you trust; treat **refresh tokens** like passwords (backed-up disk snapshot of **`.openclaw-config`** is sensitive).

## gog skill (Google Workspace CLI)

The ClawHub **gog** skill gates on **`bins: gog`**: the **`gog`** executable from **[openclaw/gogcli](https://github.com/openclaw/gogcli)** must exist **inside** both the gateway and CLI containers (not only on the host).

**If the agent still talks about “upload credentials” or OAuth in Telegram:** that usually means the **skill is not installed** or **`gog` / keyring is not visible in the container**—not that you lack a client JSON on disk. The model cannot see your host `~/.config/gogcli` unless it is bind-mounted and **`GOG_*`** is set in **`.env`**, and it has no **`gog`** tools until **`skills install`** for **gog** succeeds.

**Quick verify (on the VM, from `~/openclaw`):** the CLI image entrypoint is **`node dist/index.js`** — raw **`sh`** is parsed as an OpenClaw command and fails. Override the entrypoint to run **`gog`**:

```bash
# After sync (see numbered steps below), container gog should pass doctor:
./scripts/sync-gog-cli-config.sh
./scripts/docker-compose.sh run -T --rm --entrypoint /bin/sh openclaw-cli -c 'command -v gog && gog auth doctor --check'
./scripts/docker-compose.sh run -T --rm openclaw-cli skills search gog
# Skill already present? update instead of plain install:
# ./scripts/docker-compose.sh run -T --rm openclaw-cli skills install gog --help
# ./scripts/docker-compose.sh run -T --rm openclaw-cli skills install gog --force   # if supported
./scripts/docker-compose.sh restart openclaw-gateway
```

1. Install **`gog`** on the VM host (e.g. unpack **`gogcli_*_linux_amd64.tar.gz`** from [Releases](https://github.com/openclaw/gogcli/releases) to **`/usr/local/bin/gog`**).
2. **gogcli data for Docker (important):** the gateway runs as **UID 1000** (`node`). If **`OPENCLAW_GOGCLI_CONFIG_DIR`** points at **`~/.config/gogcli`** owned only by your SSH user, **`gog`** inside the container gets **`permission denied`**. Recommended:
   - Set **`OPENCLAW_GOGCLI_CONFIG_DIR=./.openclaw-gog-config`** in **`.env`** (default in **`docker-compose.gog.yml`**).
   - After every host **`gog auth`** (or token refresh), run **`./scripts/sync-gog-cli-config.sh`** (or **`make sync-gog-config`**) from repo root: it **`rsync`**s from **`$HOME/.config/gogcli`** (override with **`GOGCLI_SOURCE_DIR`**) into that directory and **`chown`s to `1000:1000`**.
   - Then **`./scripts/reown-openclaw-mounts.sh --container`** (if needed) and **`./scripts/docker-compose.sh restart openclaw-gateway`**.
3. Set **`GOG_KEYRING_BACKEND=file`**, **`GOG_KEYRING_PASSWORD`**, and optionally **`GOG_ACCOUNT`** in **`.env`** so gateway and CLI containers can open the same keyring as on the host.
4. Use **`./scripts/docker-compose.sh`** for stack operations (**`make up`**, **`./scripts/deploy.sh`**, **`make logs`**, **`./scripts/rollback.sh`**) so the gog overlay is applied automatically. Raw **`docker compose -f docker-compose.yml …`** skips the mount unless you add **`-f docker-compose.gog.yml`** yourself.
5. Store the **Desktop** OAuth client JSON, then authorize your Google account (see [gogcli Quickstart](https://github.com/openclaw/gogcli/blob/main/docs/quickstart.md)):
   - **`gog auth credentials /path/to/client_secret_….json`**
   - **`gog auth add you@gmail.com --services gmail,calendar,drive,docs,sheets`** (add other services you need).
6. **Headless VM (no browser on the server):** do **not** rely on **`gog auth login`** opening `http://127.0.0.1:…` — that URL is only reachable on the VM. Use **`gog auth add … --manual`** for a paste-the-URL flow in your **laptop** browser, or **`gog auth add … --remote --step 1` / `--step 2`** for a split SSH flow ([Quickstart § Authorize](https://github.com/openclaw/gogcli/blob/main/docs/quickstart.md)). Optional: from your laptop, **`ssh -L <port>:127.0.0.1:<port> user@vm`** matches the printed port if you insist on the loopback flow (the port changes each run, so `--manual` is usually easier).
7. Verify with **`gog auth doctor --check`** on the host, then **`./scripts/sync-gog-cli-config.sh`** and the **`--entrypoint /bin/sh`** **`gog auth doctor`** check inside the container (see **Quick verify** above).

## Gmail (optional, advanced)

**Sending mail or reading inbox in chat** usually requires an **OpenClaw skill** (Gmail, SMTP, etc.) from **ClawHub** / upstream docs—not this template alone.

**IMAP/SMTP skills (e.g. `imap-smtp-email`)** often read **`~/.config/imap-smtp-email/.env`** inside the container (`HOME=/home/node`). This repo bind-mounts **`OPENCLAW_IMAP_SMTP_CONFIG_DIR`** (default **`./.openclaw-imap-smtp`** on the host) to that path so credentials survive **`docker compose up`** / image updates. Create **`./.openclaw-imap-smtp/.env`** on the VM with **`chmod 600`**; follow the skill’s `SKILL.md` for exact variable names.

**Gmail with app passwords:** Google rejects normal account passwords for SMTP (`535-5.7.8`). Turn on **2-Step Verification**, create a **Google App Password** (16 characters), and use that as the SMTP/IMAP password in the skill `.env`—not your daily login password. Prefer **OAuth-based Gmail skills** if you want to avoid app passwords.

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
