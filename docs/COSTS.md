# Costs (indicative)

Cloud pricing changes by region and commitment; treat numbers as **order-of-magnitude** planning aids only (2026 public list prices, verify in console).

## Compute (e2-micro)

- **Always Free** e2-micro is available in **some** regions for eligible accounts—verify eligibility.
- Paid on-demand e2-micro is typically **a few dollars / month** plus disk.

**Caveat:** 1 GB RAM is **below** OpenClaw’s comfortable guidance for builds; this template avoids building images on the VM. Expect swapping and occasional OOM if you enable heavy plugins or browsers.

## Disk

- 20 GB `pd-standard` is usually **~$1–3 / month** depending on region.

## Vertex AI

- Billed per **model**, **tokens**, and **region**. Flash-class models are cheaper than Pro-class.
- Enable **budget alerts** on the GCP project.

## Egress

- Telegram + Vertex traffic egress from GCP may accrue **network egress** charges depending on paths and volumes—monitor **Networking** in billing reports.

## Recommendations

| Goal | Suggestion |
|------|------------|
| Reliable hobby prod | **e2-small** or **e2-medium**, 4 GB+ RAM |
| Cost floor / demo | **e2-micro** + **4G swap**, accept fragility |
| Predictable spend | Budget + alerts + autoscaling off |
