# GCP setup

## 1. Create a project

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project (e.g. `openclaw-demo`).
2. **Enable billing** (required for Compute Engine and optional GCP APIs).

## 2. Enable APIs

At minimum:

- **Compute Engine API**
- **Secret Manager API** (when using `USE_GSM_SECRETS=true`)

Optional:

- **Vertex AI API** — only if you use provider **`google-vertex`** (the default template uses **`google`** + **`GEMINI_API_KEY`** from AI Studio).

Optional (only if you follow [Gmail Pub/Sub](https://docs.openclaw.ai/automation/gmail-pubsub)):

- **Gmail API**
- **Cloud Pub/Sub API**

CLI example:

```bash
gcloud services enable compute.googleapis.com secretmanager.googleapis.com --project "$PROJECT_ID"
# Optional, for Vertex-backed models only:
# gcloud services enable aiplatform.googleapis.com --project "$PROJECT_ID"
```

Suggested first VM (PoC):

- **Machine type:** `e2-micro` (1 vCPU, 1 GB RAM) — see [COSTS.md](COSTS.md) warnings.
- **OS:** Ubuntu 24.04 LTS.
- **Disk:** 20 GB `pd-standard`.
- **Network tags / firewall:** allow **TCP 22** from your IP only.

Do **not** open `18789` publicly unless you fully understand [SECURITY.md](SECURITY.md).

## 4. SSH access

```bash
gcloud compute ssh --zone YOUR_ZONE INSTANCE_NAME --project "$PROJECT_ID"
```

Copy your deploy key or use OS Login—document your team standard.

## 5. Service account (Secret Manager + optional Vertex ADC)

1. **IAM & Admin → Service Accounts → Create**.
2. Grant **`roles/secretmanager.secretAccessor`** so deploy/runtime scripts can read Telegram, OpenAI, and optional Gemini API keys from GSM.
3. **Optional (Vertex only):** grant **Vertex AI User** `roles/aiplatform.user` and enable **Vertex AI API** if you use **`google-vertex`**.
4. Attach this service account to the VM instance (recommended) so ADC resolves through the metadata server when you use Vertex or `gcloud` on the VM.

### Workload Identity / keyless ADC

This template is keyless by default for production: VM-attached IAM identity, no downloaded JSON credentials on disk.

## 6. Host preparation

On the VM (sudo):

```bash
./scripts/setup-server.sh
./scripts/setup-swap.sh
./scripts/install-docker.sh
sudo usermod -aG docker "$USER"
```

Re-login, clone this repo, configure `.env`, then deploy.

## 7. Firewall summary

| Port | Purpose | Exposure |
|------|---------|----------|
| 22 | SSH | Trusted IPs / IAP only |
| 18789 | OpenClaw Control UI / gateway HTTP | **Default closed** — use SSH tunnel |

SSH tunnel example:

```bash
ssh -L 18789:127.0.0.1:18789 USER@VM_IP
```

Then open `http://127.0.0.1:18789/` locally.
