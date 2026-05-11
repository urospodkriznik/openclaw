# Monitoring

## Logs

- **Container logs:** `make logs` or `docker compose logs -f openclaw-gateway`.
- **Host:** `journalctl -u docker` (if using systemd-managed Docker).

## Health checks

- OpenClaw exposes **unauthenticated** probes (see [Docker docs](https://docs.openclaw.ai/install/docker)):
  - `GET /healthz` — liveness
  - `GET /readyz` — readiness
- This repo’s `scripts/healthcheck.sh` hits `/healthz` on `OPENCLAW_GATEWAY_PORT`.

You can point **GCP Uptime checks** at an endpoint only reachable over a **secure tunnel** or internal load balancer—**do not** expose raw gateway ports to the world without auth.

## Prometheus metrics

OpenClaw can expose metrics behind **gateway authentication** on the existing HTTP port (see [Prometheus metrics](https://docs.openclaw.ai/gateway/prometheus)). Do **not** publish an unauthenticated `/metrics` reverse-proxy path.

## OpenTelemetry

Optional OTLP env vars are wired through `docker-compose.yml` (see `.env.example`). Point them at your collector when you add one.

## GCP-native options

- **Cloud Monitoring / Ops Agent** on the VM for CPU, disk, and Docker metrics.
- **Alerting** on instance uptime and disk free space (OpenClaw can grow logs and session files).
