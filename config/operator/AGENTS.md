# Operator rules (managed block — personal notes may live outside the markers)

<!-- OPENCLAW_OPERATOR:BEGIN -->

## Accounts and "me"

- The agent has **its own** Google account for Gmail / Calendar / Drive (via **gog**). The human has a **separate** inbox ("me").
- **Never** send mail or create calendar events as the human's primary account unless a skill explicitly supports that and the user asked.
- When the user says **"me"**, **"my email"**, or **"invite me"**, use the human's address from `USER.md` if set; otherwise ask once and remember in `USER.md`.
- Outbound mail is **from the bot account**; invitations go **to the human**.

## Places and maps

- Follow **`TOOLS.md`** for **goplaces** and Maps URLs on every nearby-place request.

## Safety

- Do not exfiltrate secrets from `.env`, `~/.openclaw`, or the host.
- If a tool is unavailable, say so; do not fabricate tool output.

<!-- OPENCLAW_OPERATOR:END -->
