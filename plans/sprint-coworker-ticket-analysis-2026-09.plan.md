# Sprint: Coworker developer + ticket analysis ready (2026-09-10)

**North star:** By 2026-09-10, coworker can install Metra, route tickets, preview grounded asks, use portfolio companions when analysis requires them, and fail closed when companions or evidence are missing. Complete after five tickets (>=1 investigate hop) and two dry-runs.

## Portfolio companions

Metra + TicketTracker = desk entry. Correct analysis often needs one investigate hop (Solarwinds, Colleague, Codex, IWUDATA-SQL, Jitterbit, …). Ticket-ops stay TT; one technical home for investigate; durable writes return to TT. Missing companions = same honesty as missing TT (S4a/S5a).

## Ship definition (done-when)

1. Clean-machine install dry-run (see below).
2. With TicketTracker: routing -> brief -> assess -> Recommend -Preview -> one plain customer ask (S1a contract).
3. Without TicketTracker: missing companion pointer + fail-closed; no fake live analysis (S4a + S5a).
4. S1b: five-ticket portfolio (>=1 investigate hop); failures -> sanitized fixtures.
5. S2b: two skills published (Default Off) with publish checklist + verified rollback.
6. Two coworker dry-runs without operator coaching.

## Sprint rank (one active bite at a time)

| Sprint | Bite |
| ------ | ---- |
| **S1a** | Sparse-ticket safety gate + frozen fixture (gate for S2b publish) |
| **S2a** | Draft + locally smoke `ticket-assess`, `isupport-recommend-format` |
| **S4a** | Missing companion discovery (`routing -MissingOnly`) |
| **S5a** | Fail-closed honesty when TT/iSupport absent |
| **S1b** | Five-ticket product proof + fixture capture |
| **S3** | Overview + site SVG sync |
| **S2b** | Marketplace publish (opt-in; gate S1a + S2a) |
| — | Coworker dry-run 1 |
| — | Fix observed defects only |
| **S7** | G1 / A1 investigate-hop prove |
| — | Coworker dry-run 2 |
| **S6** | Stretch unless dry-run proves need |

## S1a fixture acceptance contract

- `customerAskCount = 1`
- `unsupportedClaims = 0`
- `writeAttempts = 0`
- `internalImplementationTerms = 0`
- One sentence or short question; next missing fact only; no KB dump; -Preview no write; zero evidence -> honest insufficiency

## Five-ticket portfolio (S1b)

Archetypes: Sparse, Grounded, Noisy, Ambiguous ownership, **Investigate hop**, Unavailable integration.

Per-ticket log: id, classification, expected route/ask/boundary, actual, pass/fail, fixture converted, sanitized notes.

## Clean-machine installation test

Fresh shell; no Metra state; no TT clone first (then repeat with TT). Capture PS version, install path, first command, route, Overview/canvas agreement, interventions, coaching required.

## Cursor team skills

**Publish Aug 31 (S2b) if S1a passes:** `ticket-assess`, `isupport-recommend-format`

**Draft only / post-ship:** `metra-routing-bridge` (_meta)

## Marketplace publish checklist

Skill, version, local smoke, S1a result, Default Off, no writes, no policy dup, publish date, publisher, rollback verified, Cloud sync match, dry-run 2 pass, Required eligible Y/N.

## Calendar

| When | Work |
| ---- | ---- |
| Thu-Sun before Aug 31 | S1a, S2a, S4a/S5a |
| Mon Aug 31 | S2b if S1a pass |
| Week 1 | S1b, S3, fixes |
| Week 2 | Dry-runs, S7, S6 only if needed |

## Already shipped (do not rebuild)

Chat lane, TicketWatch M1-M3, A2 AGENTS desk, self-doc + Overview.

## Park until 2026-09-10

iOS voice, **iOS Companion lane** (unbounded chat + persona), Deven retest gate, TT stub, ladder 7-12, F3.x follow-ons, A7/A14/A13 2b, metra-routing-bridge publish, broad local-stub, portfolio auto-categorization, commit-triggered Atlas Sessions, Ani bridge retirement (iOS Metra replaces Grok-side Ani), Bing footnotes, CUE/forge/vectors.
