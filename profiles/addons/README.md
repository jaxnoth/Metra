# Metra Persona Add-ons

Optional Cursor rules that **raise or specialize chat tone** without changing the public base persona (`metra-persona.mdc`) or the operator overlay (name / roots / redistribution).

Public name: **Persona Add-ons**. Install still uses `import-profile` (same plumbing as `profiles/sample`); that does not make them full operator profiles.

## Layer split

| Layer | Holds |
|-------|--------|
| Base | Shared operational policy (routing-first, evidence, incidents, professional sink) |
| Operator overlay | Operator identity (display name, greeting, team redistribution) |
| Persona Add-ons | Optional behavioral preferences (humor, teaching warmth, etc.) |

## Hard guardrails

Persona Add-ons may alter **tone** only.

They may **not** alter:

- routing or project selection
- root isolation
- evidence hierarchy (brief / notes / CLI before opinion)
- professional artifact rules (tickets, commits, coworker drafts)
- incident / outage handling defaults

If a dial needs to change those behaviors, discuss it as a **base** rule change - not an add-on.

Also:

- Opt-in only. A clone without the local rule keeps quiet public Metra.
- Import does not rewrite `metra.config.json` or the operator overlay unless the pack intentionally lists those files.
- Personality never chooses the project.

## Install

```powershell
.\metra.ps1 import-profile -Path .\profiles\addons\humor-desk -Preview
.\metra.ps1 import-profile -Path .\profiles\addons\humor-desk -Force
.\metra.ps1 import-profile -Path .\profiles\addons\teaching-gentle -Force
```

That writes the matching `.cursor/rules/metra-*.local.mdc` (gitignored). Delete the file to disable. (`list-addons` / `disable-addon` are deferred - not v1.)

Single-file path (no pack): copy the matching `.cursor/rules/metra-*.local.example.mdc` to the `.local.mdc` name.

### Family / shared Cursor

Prefer a **separate overlay per person** (name / redistribution). Swap Persona Add-ons per session or checkout - e.g. import `teaching-gentle` for school help and remove `metra-humor.local.mdc` if sarcasm is unwanted. Do not put ages into always-on rules; `teaching-gentle` activates only on an explicit ask in chat.

## Shipped add-ons

| Pack | Id | Role |
|------|----|------|
| [humor-desk](humor-desk/) | `humor-desk` | Desk-partner humor palette (dry asides, ticket intro beat, light sarcasm with evidence) |
| [teaching-gentle](teaching-gentle/) | `teaching-gentle` | Gentler pacing and plain words; explicit kid/family/beginner/educational ask only - never infer audience |

## Suggested later add-ons (not shipped yet)

| Idea | What it would dial | Keep out of base? |
|------|--------------------|-------------------|
| `teaching-warm` | Slightly warmer Teaching Mode pacing; more one-line why | Yes - base stays anti-lecture |
| `ticket-focus` | Stronger "brief first / similar / one technical route" chat reminders | Yes - procedural preference |
| `redistribution-strict` | Extra reminders that coworker drafts stay flat | Optional; base already requires sink |
| `personal-casual` | More conversational on personal-root asks only | Yes - operator taste |
| `quiet-ops` | Fewer asides than base default (extra flat for pager-heavy weeks) | Yes - temporary dial |
| `brand-voice-local` | Operator-only Motif / Ops board phrasing in chat (not tickets) | Yes - never in iSupport |

Ship a new add-on only when someone would actually import it. Prefer one alwaysApply local rule per pack under `.cursor/rules/`. Document here and in [docs/Customizing-Metra.md](../../docs/Customizing-Metra.md). Keep README marketing ops-first; Persona Add-ons stay under customization, not the product hero.

See also: [SECURITY.md](../../SECURITY.md) (local rules are machine-private).
