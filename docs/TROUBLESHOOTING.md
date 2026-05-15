# Troubleshooting

## Gateway restart loop / “unhealthy” right after editing `openclaw.json`

If the gateway **exits repeatedly** after **`./scripts/bootstrap-config.sh`** or a manual merge, the image may **reject unknown keys** in **`openclaw.json`**.

1. **Logs:** `./scripts/docker-compose.sh -f docker-compose.dev.yml logs --tail=80 openclaw-gateway` — look for config / Zod validation errors.
2. **Recover:** from repo root run **`./scripts/bootstrap-config.sh`** again (template emits only keys this repo supports), then **`make restart-dev`**.

## `docker compose restart` — only CLI runs, or gateway stuck / unhealthy

**`openclaw-cli`** uses **`network_mode: service:openclaw-gateway`**: it joins the **gateway** container’s network namespace. If you **`docker compose restart openclaw-gateway`** (or Compose restarts services in an order that recreates the gateway while the CLI container is unchanged), the CLI can stay attached to an **old** netns while the gateway is a **new** container — the stack looks broken (e.g. only CLI “up”, gateway exited, or no `/healthz`).

**Do this instead** (recreate **both** services):

```bash
./scripts/docker-compose.sh -f docker-compose.dev.yml up -d --force-recreate
# or: make restart-dev
# or: down then up -d
```

Avoid **`docker compose restart`** for this stack unless you restart **both** services in a way that recreates the pair; **`up -d --force-recreate`** is the reliable pattern.

## `docker-compose.sh: skipping gog overlay` but `.openclaw-host-bin/gog` exists

The compose wrapper checks that the host **`gog`** binary is **Linux ELF**. It uses the **`file`** command when installed; on minimal Ubuntu images **`file` is often missing**, so detection failed even though **`gog` is valid**.

**Fix (either):**

```bash
sudo apt-get install -y file
# or pull latest repo (docker-compose.sh falls back to ELF magic bytes without `file`)
./scripts/docker-compose.sh up -d --force-recreate
```

Confirm the overlay loads: compose should **not** print `skipping gog overlay`. Then continue OAuth in [GOOGLE_INTEGRATIONS.md](GOOGLE_INTEGRATIONS.md).

## `gog` in container: “Mach-O” / “wrong executable format” / macOS binary on Linux

The OpenClaw image is **Linux**. Bind-mounting **`gog` from Homebrew on a Mac** mounts a **Mach-O** binary; the kernel inside the container expects **ELF**.

**Fix:** `make install-gog-linux` (downloads [gogcli](https://github.com/openclaw/gogcli) `linux_amd64` or set **`GOG_LINUX_ARCH=arm64`**), then `make restart-dev`. Keep using **macOS `gog auth`** for OAuth; **`make sync-gog-config`** copies tokens into **`.openclaw-gog-config`**.

### Agent still says “macOS binary” after `make install-gog-linux`

The gateway may already be correct. Run **`make verify-gog`** (or **`./scripts/verify-gog-in-container.sh -f docker-compose.dev.yml`**) and check the printed **magic** bytes: **ELF** is **`7f 45 4c 46`**. If that matches but the assistant in Telegram disagrees, it is usually **stale session context** from before the fix — use **`/new`** or a **reset** flow for that chat (per [session](https://docs.openclaw.ai/concepts/session) docs), or ask it to run **`sh -lc 'head -c 4 /usr/local/bin/gog | od -An -tx1; gog version'`** and trust the tool output over its prior narrative.

## `apt-get update` fails on `dl.google.com` / Chrome (`File has unexpected size`)

Google’s **Chrome** APT repo sometimes returns a **Packages** index that does not match the **Release** file while mirrors sync (`1213 != 1212`, “Mirror sync in progress”). That is **upstream/transient**, not an OpenClaw bug.

**Quick fixes**

1. **Retry** after a few minutes: `sudo apt-get update`
2. **CI / self-hosted runners:** retry the update step (this repo’s **`.github/workflows/ci.yml`** retries **`apt-get update`** up to **3** times).
3. **You do not need Chrome on that machine:** remove the list file and update again:

   ```bash
   sudo rm -f /etc/apt/sources.list.d/google-chrome.list /etc/apt/sources.list.d/google-chrome*.list
   sudo apt-get update
   ```

## `fetch-secrets-gsm.sh` fails

When `USE_GSM_SECRETS=true`, ensure VM IAM and secret names are correct:

```bash
gcloud auth list
gcloud secrets versions access latest --secret "$GSM_TELEGRAM_BOT_TOKEN_SECRET" --project "$GSM_PROJECT_ID"
# If configured, test optional secrets the same way (replace with your secret names):
# gcloud secrets versions access latest --secret "$GSM_GEMINI_API_KEY_SECRET" --project "$GSM_PROJECT_ID"
# gcloud secrets versions access latest --secret "$GSM_GOOGLE_PLACES_API_KEY_SECRET" --project "$GSM_PROJECT_ID"
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

**`reown --host` run as root (`sudo bash -c '…'`)** used to no-op because root can write everything. The script now chowns to the **repo owner** (or **`OPENCLAW_DEPLOY_USER`**). Prefer:

```bash
sudo ./scripts/reown-openclaw-mounts.sh --host   # from the clone, as an admin with sudo
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

Re-run **`./scripts/bootstrap-config.sh`** on the VM (or redeploy), then **`./scripts/docker-compose.sh up -d --force-recreate`** (recreate gateway + CLI).

If it persists, check gateway logs for **session key** stability and inspect sessions per [Session management](https://docs.openclaw.ai/concepts/session) (e.g. **`docker compose exec openclaw-cli sh -lc 'node dist/index.js sessions --help'`** on your OpenClaw version).

## Exec approval timed out / agent “won’t re-run” shell or `openclaw` commands

Default **`SAFE_MODE`** sets **`tools.exec.ask: on-miss`** and **`askFallback: deny`**. [Exec approvals](https://docs.openclaw.ai/tools/exec-approvals) need a **Control UI / companion** to approve; on a **headless** gateway, prompts expire with nobody attached.

**Options:**

1. **SSH tunnel** the Control UI: `ssh -L 18789:127.0.0.1:18789 user@vm` then open `http://127.0.0.1:18789/`.
2. **Single trusted VM:** **`TRUSTED_HEADLESS_EXEC=true`** and **`I_ACCEPT_HEADLESS_EXEC_RISK=1`** in **`.env`**, then **`./scripts/bootstrap-config.sh`** + gateway restart ([docs/SECURITY.md](SECURITY.md)).
3. Upstream break-glass chat commands (e.g. **`/elevated full`**) for operators who understand the risk.

### “Command approval unavailable” / approval timeout (Telegram only)

If shell / **`gog`** commands never run and the UI shows **`Command approval unavailable`** or **approval timed out**, the gateway is in **`SAFE_MODE`** but **nothing is connected** that can answer [exec approvals](https://docs.openclaw.ai/tools/exec-approvals) (no Control UI on **18789**). Telegram DMs alone often **cannot** complete that approval path.

On a **trusted personal** Mac (Docker only, no public exposure), set in **`.env`**:

```bash
TRUSTED_HEADLESS_EXEC=true
I_ACCEPT_HEADLESS_EXEC_RISK=1
```

Then **`./scripts/bootstrap-config.sh`**, **`make restart-dev`**, and **`/new`** in Telegram. This matches the **headless exec** preset in [docs/SECURITY.md](SECURITY.md) (widens **gateway `tools.exec`** only — read the risk section first). Alternatively keep **`SAFE_MODE`** and open an **SSH tunnel** to **`127.0.0.1:18789`** so the Control UI can approve.

## Google Workspace from chat (Gmail, Calendar, Drive)

This template does **not** install Gmail, Calendar, or Drive skills. The agent only gets those abilities after you add skills (or MCP) and auth.

| Goal | What to do |
|------|------------|
| **Send/read email** | Install a **Gmail or SMTP skill** from [ClawHub](https://documentation.openclaw.ai/clawhub) (`openclaw skills search "gmail"`). Optional automation: [Gmail Pub/Sub](https://docs.openclaw.ai/automation/gmail-pubsub) (not the same as “send mail” in chat). |
| **Calendar events** | Install a **Calendar API skill** (`openclaw skills search "calendar"`). Enable **Google Calendar API** in GCP; OAuth or service account per skill. |
| **Drive files** | Install a **Drive / Workspace skill** (`openclaw skills search "drive"`). Enable **Google Drive API** in GCP; OAuth per skill. |

Details, API enablement, and OAuth vs Secret Manager: **[docs/GOOGLE_INTEGRATIONS.md](GOOGLE_INTEGRATIONS.md)**.

## `gog` in Docker: `credentials.json` shows `?????????` / permission denied (inside container)

**Cause (historical):** bind-mounting **`.openclaw-gog-config`** from **macOS** into the Linux VM could leave **`stat(2)`** / **`open(2)`** broken (**`?????????`**) even after **`xattr -cr`** and inode rewrites (**VirtioFS** quirks).

**Current layout:** **`docker-compose.gog.yml`** mounts a **named Docker volume** at **`/home/node/.config/gogcli`** (Linux ext4 inside the VM). The host directory **`OPENCLAW_GOGCLI_CONFIG_DIR`** (default **`.openclaw-gog-config`**) is only a **staging** copy: **`make sync-gog-config`** refreshes it from **`~/Library/Application Support/gogcli`** (or **`~/.config/gogcli`**), then **`make push-gog-gateway`** (or **`./scripts/push-gogcli-to-gateway.sh`**) streams a **tar** archive into the running gateway via **`docker exec`** so OAuth files land on the volume without crossing the broken bind path.

```bash
make sync-gog-config
make restart-dev
# or with the stack already up:
make push-gog-gateway
```

**`make restart-dev`** / **`local`** / **`dev`** / **`restart`** wait briefly, then run **`push-gogcli-to-gateway.sh`** (errors ignored if gog is not configured). If staging files are **`600`** and owned by **UID 1000**, the push script may prompt for **sudo** so **`tar`** can read them on the host.

**`tar: Write error`:** usually a **broken pipe** — **`docker exec`** exited while the gateway was still booting (or crashed). **`push-gogcli-to-gateway.sh`** now waits for **`http://127.0.0.1:18789/healthz`** inside the container (up to **90s**) **before** clearing the gog volume and streaming. If a failed push left the volume empty, run **`make sync-gog-config`** then **`make push-gog-gateway`** again. If **`/healthz`** never succeeds, inspect gateway logs and **`openclaw-config/openclaw.json`** (a bad config merge can prevent startup).

**`docker compose down -v`** / **`make clean`** removes named volumes including **`openclaw_gogcli_config`** — re-run **`make sync-gog-config`** and **`make push-gog-gateway`** (or **`make restart-dev`**) to repopulate.

Verify:

```bash
./scripts/docker-compose.sh exec -T openclaw-gateway ls -la /home/node/.config/gogcli/credentials.json
```

## `gog` in Docker: `permission denied` on `/home/node/.config/gogcli`

The **`openclaw-gateway`** process runs as **UID 1000**. Use host staging **`OPENCLAW_GOGCLI_CONFIG_DIR=./.openclaw-gog-config`**, run **`./scripts/sync-gog-cli-config.sh`** after host **`gog auth`**, then **`./scripts/push-gogcli-to-gateway.sh`** (or **`make push-gog-gateway`**) so files exist on the **named volume** with **`node`**-readable ownership. See **[docs/GOOGLE_INTEGRATIONS.md](GOOGLE_INTEGRATIONS.md)** (gog skill).

## Docker Desktop (Mac): `restart` fails — `mkdir ... .openclaw-gog-config: file exists`

After **`chown -R 1000:1000`** on **`.openclaw-gog-config`**, directories copied from **`~/Library/Application Support/gogcli`** are often mode **`700`**. Your Mac user can no longer traverse that path; **Docker Desktop** can then fail when (re)creating the bind mount, sometimes with a misleading **`mkdir ... file exists`** error.

**Fix:** re-run **`./scripts/sync-gog-cli-config.sh`** (current script sets **dirs `755`**, **files `600`** after `chown`), or manually:

```bash
sudo sh -c 'chown -R 1000:1000 .openclaw-gog-config && find .openclaw-gog-config -type d -exec chmod 755 {} + && find .openclaw-gog-config -type f -exec chmod 600 {} +'
```

Then **`./scripts/docker-compose.sh … down`** and **`up -d`** (cleaner than **`restart`** if Docker was wedged).

## Telegram bot silent

- **New clone or moved repo:** use **`make init`** (local) or **`make init-vm`** / **`make restart`** (GCP VM) — not plain **`docker compose up`** alone. Those targets run **`--force-recreate`** and **`push-gogcli-to-gateway.sh`** (gog is optional for Telegram, but recreate fixes CLI/gateway networking).
- Re-run channel registration with a fresh token if rotated.
- Check gateway logs for Telegram adapter errors.
- Confirm outbound HTTPS is allowed from the VM (NAT/firewall).
- If using GSM mode, regenerate runtime env: `./scripts/fetch-secrets-gsm.sh`.

## No Telegram replies after `restart` / `--force-recreate`

1. **Containers actually up:**  
   `cd ~/openclaw && ./scripts/docker-compose.sh ps`  
   Both should be **running** (not **Restarting**).

2. **Gateway HTTP:**  
   `curl --noproxy '*' --http1.1 -H 'Expect:' -fsS http://127.0.0.1:18789/healthz`  
   (Use **`OPENCLAW_GATEWAY_PORT`** from **`.env`** if not **18789**.) Expect HTTP **200**. If this fails, the bot cannot run.

3. **Logs (first errors):**  
   `./scripts/docker-compose.sh logs --tail=200 openclaw-gateway`  
   Look for crash on startup, **invalid `openclaw.json`**, OOM (**137**), or Telegram token errors.

4. **`docker restart` / namespace errors:** If **`restart`** failed with **runc** / **`ns/net`** errors, prefer **`./scripts/docker-compose.sh up -d --force-recreate`** or stop **CLI** first, then **gateway**, then start **gateway** then **CLI** (CLI uses **`network_mode: service:openclaw-gateway`**).

5. **Stale config:** If **`./healthz`** works but Telegram is dead, confirm **`TELEGRAM_BOT_TOKEN`** is still present (host **`.env`** + **`.env.generated`** when **`USE_GSM_SECRETS=true`**) and run **`./scripts/fetch-secrets-gsm.sh`** then **`up -d`** again.

6. **Config schema:** Very old gateway images might reject unknown keys. If logs show a parse error on **`agents.defaults.llm`**, remove that block from **`openclaw.json`** or upgrade **`OPENCLAW_IMAGE`**, then **`./scripts/docker-compose.sh up -d --force-recreate`** (gateway + CLI).

## Gateway logs `Missing config` but `jq '.gateway.mode'` is `"local"` on the host

The gateway runs as **UID 1000** inside the image. If you restored config with:

```bash
cp .openclaw-config/openclaw.json.bak .openclaw-config/openclaw.json
```

the backup is often mode **`600`** (`-rw-------`). Your SSH user can read it with **`jq`**, but the container **cannot** → crash loop with **`Missing config. Run openclaw setup or set gateway.mode=local`**.

**Check:**

```bash
ls -la .openclaw-config/openclaw.json
./scripts/diagnose-openclaw-config.sh
```

**Fix (pick one):**

```bash
chmod 644 .openclaw-config/openclaw.json
# or (preferred before compose up on a VM):
sudo ./scripts/reown-openclaw-mounts.sh --container
./scripts/docker-compose.sh up -d --force-recreate
./scripts/healthcheck.sh
```

After **`/healthz` OK**, re-apply Codex/PI changes with **`jq`** (not **`nano`**) if needed; see **OpenAI `openai/gpt-*` → “codex harness not registered”** below.

**`chmod 755 .openclaw-config` alone is not enough for a running gateway.** The container must also **write** under **`logs/`**, **`credentials/`**, etc. If logs show **`EACCES`** on **`/home/node/.openclaw/logs/...`** or **`credentials/oauth.json`**, re-own the whole tree to UID **1000** (deploy user cannot `sudo` — use an admin account):

```bash
# as any user with sudo, full path to the clone:
sudo bash -c 'cd /home/deployuser/openclaw-primary && ./scripts/reown-openclaw-mounts.sh --container'
```

Then as the deploy user: **`./scripts/docker-compose.sh up -d --force-recreate`** and **`./scripts/healthcheck.sh`**.

## OpenAI `openai/gpt-*` → “Requested agent harness codex is not registered”

On recent OpenClaw images, **`openai/gpt-*`** model refs may route agent turns through the **Codex** harness. If the **`codex` plugin** is not loaded, Telegram replies fail with a generic error; logs show **`codex is not registered`**.

**Option A — force PI (direct OpenAI API)** — add only after the gateway is healthy; a bare **`models.providers.openai`** object can wipe the bundled provider on some versions:

```bash
jq '
  .models //= {}
  | .models.providers //= {}
  | .models.providers.openai //= {}
  | .models.providers.openai.agentRuntime = { "id": "pi" }
' .openclaw-config/openclaw.json > /tmp/oc.json && mv /tmp/oc.json .openclaw-config/openclaw.json
chmod 644 .openclaw-config/openclaw.json
sudo ./scripts/reown-openclaw-mounts.sh --container
./scripts/docker-compose.sh up -d --force-recreate
```

If the gateway crash-loops again, remove the block: **`jq 'del(.models)' …`** and use **Option B**.

**Option B — change model** in **`.env`** / **`.env.generated`** (e.g. **`OPENAI_MODEL=gpt-4.1-mini`**), run **`./scripts/bootstrap-config.sh`**, recreate, then **`/new`** in Telegram.

**Option C — enable Codex** per [OpenClaw Codex harness](https://docs.openclaw.ai/plugins/codex-harness) (heavier on small VMs).

## Gateway stuck `Restarting (1)` (crash loop)

Often **`openclaw.json`** is invalid for this image or **replaces** built-in provider config incorrectly.

1. **Logs:** `./scripts/docker-compose.sh logs --tail=120 openclaw-gateway` — look for Zod/config validation errors at startup.

2. **Partial `models.providers.google`:** A minimal object like `{ "timeoutSeconds": 180 }` can **wipe** the bundled Google provider definition on some versions → immediate exit. **Remove** the entire **`models`** key from **`openclaw.json`** unless you merged a **full** provider per upstream docs, then re-run **`./scripts/reown-openclaw-mounts.sh --container`** and **`./scripts/docker-compose.sh up -d`**.

3. **`agents.defaults.llm` / `timeoutSeconds`:** If **`/healthz`** never succeeds right after merging idle/turn limits, remove them: **`jq 'del(.agents.defaults.timeoutSeconds, .agents.defaults.llm)' .openclaw-config/openclaw.json`** (write to a temp file, **`mv`**, then **`make restart-dev`**). See **“Model idle timeout”** below.

4. **Recover minimal config:** From repo root: **`./scripts/reown-openclaw-mounts.sh --host`**, **`./scripts/bootstrap-config.sh`**, **`./scripts/reown-openclaw-mounts.sh --container`**, **`./scripts/docker-compose.sh up -d`** (note: **`bootstrap-config.sh`** overwrites **`openclaw.json`** with the template minimal shape — back up first if you added channels/plugins by hand).

## “Model idle timeout” / slow replies on Telegram

OpenClaw uses separate limits (see [model providers](https://docs.openclaw.ai/concepts/model-providers)):

- **`agents.defaults.llm.idleTimeoutSeconds`** — max gap **without streamed tokens** (often triggers the **“model idle timeout”** Telegram message).
- **`agents.defaults.timeoutSeconds`** — max time for a **whole agent turn**.
- **`models.providers.<id>.timeoutSeconds`** — provider **HTTP** guard (not the same as idle streaming).

**This repo’s `bootstrap-config.sh` does not write these keys** (doing so with a bare **`google`** provider object has crashed gateways). Merge optional fragments from **`config/openclaw-timeouts.example.json5`** only after you confirm your **`OPENCLAW_IMAGE`** supports them, then **`./scripts/docker-compose.sh up -d --force-recreate`** (gateway + CLI).

**Safer first step:** some **`OPENCLAW_IMAGE`** builds **crash or restart-loop** when **`agents.defaults.llm`** (or even **`agents.defaults.timeoutSeconds`**) is present — **`/healthz` never goes OK**. If that happens, **remove** those keys and recreate:

```bash
cd /path/to/openclaw
jq 'del(.agents.defaults.timeoutSeconds, .agents.defaults.llm)' \
  .openclaw-config/openclaw.json > .openclaw-config/openclaw.json.tmp &&
mv .openclaw-config/openclaw.json.tmp .openclaw-config/openclaw.json
make restart-dev
```

Before editing again, confirm the schema for your image in [model providers](https://docs.openclaw.ai/concepts/model-providers) / gateway docs. Until then, expect occasional **“model idle timeout”** on long **`gog`** tool chains.

**Do not** paste a bare **`models.providers.google`** fragment unless you merge a **full** provider object (see **Gateway stuck `Restarting`** above).

Also confirm **`GEMINI_API_KEY`** / GSM Gemini secret is valid (`gateway` logs for API errors).

## GitHub Actions deploy fails SSH

### `ssh: unable to authenticate ... attempted methods [none publickey]`

The runner’s private key (`GCP_VM_SSH_KEY`) must match a **public** key line in **`~/.ssh/authorized_keys`** for **`GCP_VM_USER`** on the VM (same user the workflow connects as).

1. **Align user and key:** On the VM, pick the account you use for deploy (e.g. `ubuntu` or `your_username`). Append the **deploy public** key to that user’s `authorized_keys`:

   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   cat >> ~/.ssh/authorized_keys <<'EOF'
   # paste single line from deploy key .pub
   EOF
   chmod 600 ~/.ssh/authorized_keys
   ```

2. **GitHub secret contents:** `GCP_VM_SSH_KEY` must be the **full private** key (including `-----BEGIN … PRIVATE KEY-----` / `END` lines), with **newlines preserved**. If the key has a **passphrase**, add **`passphrase:`** to the workflow’s `appleboy/ssh-action` inputs (this repo does not set it by default — use a **passphraseless** deploy key).

3. **Match host:** `GCP_VM_HOST` must be the VM’s **external IP** or a DNS name that resolves to it (not an internal-only name GitHub’s runners cannot resolve).

4. **Sanity check from your laptop** (substitute your deploy key):

   ```bash
   ssh -i ~/.ssh/your_deploy_private_key -o IdentitiesOnly=yes YOUR_USER@YOUR_VM_IP true
   ```

If that fails, CI will fail for the same reason.

Also verify **`GCP_VM_PORT`** if SSH is not on **22**.

### Other checks

- Ensure the deploy user can run **passwordless** `docker` (group membership) and **`sudo`** for **`chown`** per [docs/GITHUB_ACTIONS.md](GITHUB_ACTIONS.md).

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
