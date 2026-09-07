---
name: codex
description: >-
  Metra Codex knowledge-base procedures: search, page get/contents, cite format
  for tickets. Use for KB articles, Nice Knowledge, documentation lookups.
  Default Off; never invents articles; surfaces Provider and Mode; no ticket
  writes (TicketTracker owns post/recommend/resolve).
disable-model-invocation: true
---

# Codex

Procedure wrapper for Metra Codex. **Skill is not authority.** Search, providers,
and write gates live in the Codex checkout (`.\Codex.ps1`). TicketTracker owns
durable ticket writes.

## Authority

| Owns | Does not own |
|------|--------------|
| Pointing at `.\Codex.ps1 search` / `page` / cite shape | Inventing KB content |
| Reminding Provider / Mode honesty | iSupport `post` / `recommend` / `resolve` |
| Stub vs live surfacing | Metra routing / TicketTracker assess policy |

## Portfolio rules (encode)

1. Codex never routes to TicketTracker, M365, or other projects for ticket-ops.
2. TicketTracker owns tickets - paste cites into TT; do not write tickets from here.
3. Never invent KB articles. Prefer newest active-space article when sources conflict.
4. Always surface **Provider** and **Mode** (`live` / `stub`). If fallback occurred, say so.

## Workflow

Run from `<Codex checkout>` (clone required; else fail-closed):

```powershell
.\Codex.ps1 health
.\Codex.ps1 search "<terms>" -Top 10
.\Codex.ps1 page get <page-id>
.\Codex.ps1 page contents <page-id> -Format Text
```

Ticket cite shape (operator pastes into TicketTracker `note` / `post`):

```text
[KB: page title](https://...)
```

Stub example honesty: `Provider: stub` / `Mode: stub` / `Source: local corpus` -
do not present stub as production institutional KB.

## Missing station

If Codex is not on disk, say so (Metra `routing -MissingOnly` / `whenMissing`).
Prefer Metra Ops **Station Updates** to install the Codex Station when available.
Ask the operator to paste KB text/URL. Do not invent articles or claim KB writes.

## Hard offs

- Ticket writes from this skill
- Silent stub-as-live
- Merging TicketTracker assess policy into Codex
- Replacing `metra.ps1 routing`

## Smoke

1. `.\Codex.ps1 health` (or honest missing-checkout message).
2. `search` returns citations with Provider/Mode when live/stub configured.
3. No `TicketTracker.ps1 post|recommend|resolve` during smoke.
