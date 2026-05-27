# Operator tool conventions (managed by template — do not store personal data here)

This file is overwritten on `make init`, `make deploy`, and `make sync-operator-workspace`.
Put end-user persona in `SOUL.md` and memory in `memory/` — not here.

## Google Places (goplaces skill)

- For **nearby restaurants, cafes, shops**, you **must** run the **`goplaces`** CLI (Places API). Do not guess from memory or the web.
- When the user shares a **Telegram location**, use their coordinates (`LocationLat`, `LocationLon` from the message context). If they say "near me" without a pin, ask them to attach **Location** (📎 → Location).
- Default search unless they specify otherwise: **radius 2000 m**, **`--open-now`** when they want open places now.
- Example (no extra quotes around numbers; negative lng is fine):

  ```bash
  goplaces search "vegan restaurant" --lat 46.051 --lng -16.708665 --radius-m 2000 --open-now --limit 10
  ```

- Prefer results whose types include `vegan_restaurant` or `vegetarian_restaurant`. For others, run `goplaces details <place_id> --reviews` before claiming vegan options.
- In replies, include **name**, **rating**, **open now** (from tool output), **distance if shown**, and **Place ID** (`ChIJ…`).

### Google Maps links (required format)

- **Never** use: `query=place_id:ChIJ…` — Maps often fails to open the place.
- **Always** use official search URLs with a real **query** plus **query_place_id**:

  ```text
  https://www.google.com/maps/search/?api=1&query=<URL-encoded name or lat,lng>&query_place_id=<ChIJ...>
  ```

- Examples:
  - Name: `query=Ondori+Street+Food&query_place_id=ChIJ…`
  - Coordinates fallback: `query=28.051851,-16.708665&query_place_id=ChIJ…`
  - Minimal fallback: `query=%20&query_place_id=ChIJ…`

- If `goplaces` fails (403, empty, error), say so — **do not invent** venues or links.

## Google Workspace (gog skill)

- Use **`gog`** for Gmail, Calendar, Drive, Sheets when the user asks — not generic web search.
- **Bot account** sends mail and creates calendar events on **its** calendar; invite the user's address when they say "me" or "my calendar" (see `AGENTS.md`).
- If `gog` or exec fails, report the error; do not pretend an email was sent or an event was created.
