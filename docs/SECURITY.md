# Security

## Threat model (short)

This template targets a **single-operator** VM with **one primary Telegram bot** and a **Gemini API key** (or optional Vertex ADC). It is **not** safe as a multi-tenant public agent platform without substantial additional controls.

## Network exposure

- **SSH (22):** restrict source IPs; prefer **IAP** or VPN where possible.
- **Gateway (18789):** bind defaults are suitable for **local / LAN / tunneled** access. If you must expose WAN, place a **TLS-terminating reverse proxy** with strong authentication in front, and read upstream [Gateway security](https://docs.openclaw.ai/gateway/security).

## Secrets handling

- For production, keep secrets in **Google Secret Manager** and fetch runtime values into `.env.generated` via `scripts/fetch-secrets-gsm.sh` (Telegram required; OpenAI, Gemini, and Google Places API keys optional when `GSM_*` secret names are set).
- Keep `.env` (non-secret config) and `.env.generated` (runtime secrets) **out of git** and mode `600`.
- Prefer VM-attached service accounts / workload identity over downloadable JSON keys.
- CI includes a **lightweight pattern scan**—it is not a substitute for secret scanning services or pre-commit hooks.

## Autonomy modes

### SAFE (default convention)

- `SAFE_MODE=true` in `.env` (semantic flag for this template).
- `scripts/bootstrap-config.sh` writes conservative `tools.exec` defaults and `exec-approvals.json`.
- Gmail hooks remain **disabled** unless you deliberately enable them.

### DEMO (`DEMO_MODE=true`)

- For screenshots / portfolio demos.
- **Mutually exclusive** with `FULL_AUTONOMY` and with **`TRUSTED_HEADLESS_EXEC`**.
- Keeps Gmail hooks off; uses stricter **ask** behavior for exec approvals.

### FULL AUTONOMY (`FULL_AUTONOMY=true`)

- **Dangerous:** aligns with OpenClaw “YOLO” style policies (broad host exec, approvals off).
- Requires **`I_ACCEPT_FULL_AUTONOMY_RISK=1`** or `validate-env.sh` fails.
- Use only in an **isolated** GCP project and with full understanding of [Exec approvals](https://docs.openclaw.ai/tools/exec-approvals).

### TRUSTED HEADLESS EXEC (`TRUSTED_HEADLESS_EXEC=true`)

- For **SSH / Telegram-only** VMs where the [Control UI](https://docs.openclaw.ai/gateway/control-ui) is not running: default **`ask: on-miss`** prompts **cannot be answered**, so shell/exec requests **time out** ([Exec approvals](https://docs.openclaw.ai/tools/exec-approvals)).
- With **`I_ACCEPT_HEADLESS_EXEC_RISK=1`**, **`./scripts/bootstrap-config.sh`** writes the same **gateway** `tools.exec` + **`exec-approvals.json`** defaults as **FULL AUTONOMY** for **host exec only**. Do **not** combine with **`FULL_AUTONOMY`** or **`DEMO_MODE`** (`validate-env.sh` enforces this).
- Prefer an **SSH tunnel** to port **18789** and approvals in the Control UI if you want to keep **`SAFE_MODE`**-style exec without auto-allow.

## Filesystem

The agent workspace is bind-mounted from the host. Any tool or shell access can read/write within mounted paths subject to container UID (**1000** / `node`) and host permissions. Fix ownership:

```bash
sudo chown -R 1000:1000 "$OPENCLAW_CONFIG_DIR" "$OPENCLAW_WORKSPACE_DIR"
```

## Reporting

If you find a security issue in **OpenClaw itself**, follow the upstream project’s disclosure process. Issues in **this template** belong in your fork’s tracker.
