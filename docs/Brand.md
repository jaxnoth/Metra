# Metra brand kit

Compact identity for **operator-facing** Metra surfaces. Durable artifacts (tickets, commits, coworker redistribution, professional docs meant for iSupport) stay unbranded.

## Customization boundary

How far Metra goes into Cursor:

| Layer | Stance |
|-------|--------|
| HTML Ops desk (`ops/`) | Primary product face - Brand hex OK (Signal Teal / Mist / Graphite) |
| Metra Ops canvas | Advanced IDE face - customize deeply; map brand via `useHostTheme()` |
| CLI help colors | Light touch (Cyan / Yellow / Red) |
| Naming (`Metra`, workspace label) | Yes |
| Optional local accent override | Allowed - Signal Teal into host accent only |
| Full Cursor color theme extension | Out of scope (optional personal experiment only) |
| Activity bar / title bar takeover | No |

**Primary vs advanced:** For non-technical users, installer + HTML Ops is the front door. Cursor (including the Ops canvas) is an advanced interface. See [Decisions.md](Decisions.md) (HTML Ops primary desk).

Host-following stays the rule for canvases: map brand **intent** through `useHostTheme()` - no hardcoded hex in `.canvas.tsx`. HTML Ops may use the reference hex below directly. Reference hex is also for docs, approval screenshots, and optional local Cursor accent overrides.

## Palette (reference)

| Token | Hex | Use |
|-------|-----|-----|
| Signal Teal | `#0F766E` | Primary brand / action accent |
| Graphite | `#1F2937` | Structure and strong text (light themes) |
| Mist | `#E6F4F1` | Restrained tint / soft fill (light) |
| Amber | `#D97706` | Attention only - never general decoration |

Host success/error greens and reds stay operational. Do not invent a rainbow of brand colors.

## Dual-mode intent map

Same jobs in **Cursor Light** and **Cursor Dark**. Host tokens vary; the mapping should feel like one product.

| Brand job | Light feel | Dark feel | Canvas mapping |
|-----------|------------|-----------|----------------|
| Signal Teal (brand) | Clear teal/blue accent on route mark, faceplate bar, primary buttons | Same accent, slightly brighter on charcoal | `theme.accent.primary` |
| Mist (soft brand fill) | Soft cool gray/teal-tinted strip behind title | Soft elevated fill, not flat black slab | `theme.fill.tertiary` (faceplate) |
| Graphite (structure) | Strong title / body | Strong title / body | `theme.text.primary` / host typography |
| Amber (attention) | Dirty, missing, drift > 0, behind remote | Same | Stat / row `tone="warning"` |
| Healthy / zero issues | Calm success (often teal-green) | Same | Stat `tone="success"` |
| Informational git counts | Quiet blue/info | Same | Stat `tone="info"` |
| Route motif | Teal line + terminal nodes; open labeled interchange | Same, with brighter teal on charcoal | [`assets/metra-mark.svg`](assets/metra-mark.svg) |

**Daily default:** Cursor Dark is fine for long sessions.  
**Demo / approval faceplate:** Cursor Light shows Mist + Signal Teal intent more clearly. Both must pass the checklist below.

### Optional local accent (not a full skin)

To push Signal Teal into host accent (and thus the Ops board route mark) without a Metra theme pack, a **local** `settings.json` accent override is enough. Example only - do not commit machine-specific settings into the Metra checkout:

```json
"workbench.colorCustomizations": {
  "[Cursor Light]": {
    "focusBorder": "#0F766E",
    "button.background": "#0F766E",
    "button.hoverBackground": "#0D9488",
    "textLink.foreground": "#0F766E"
  },
  "[Cursor Dark]": {
    "focusBorder": "#14B8A6",
    "button.background": "#0F766E",
    "button.hoverBackground": "#14B8A6",
    "textLink.foreground": "#2DD4BF"
  }
}
```

Dark uses a slightly brighter teal for focus/links so the motif stays visible on charcoal. If host accent stays Cursor blue, the board is still valid - brand intent is "accent = primary wayfinding," not "must be exactly #0F766E."

## Motif

A short **route line with nodes** - wayfinding, not a train logo and not Chicago transit Metra blue/orange. No mascot, no emoji chrome, no gradients, no box shadows.

### Public mark (GitHub / docs)

GitHub README stays operator/coder-facing. Plain-language landing for non-coders: [`site/`](../site/) published as GitHub Pages at [jaxnoth.github.io/Metra](https://jaxnoth.github.io/Metra/). May move to a fuller host later; keep the README pointer current. See [Decisions.md](Decisions.md) (public audience / plain-language site).

Canonical file: [`assets/metra-mark.svg`](assets/metra-mark.svg). Tray / Start Menu bitmap: [`assets/metra.ico`](assets/metra.ico) (square crop of the route mark for NotifyIcon and installer shortcuts).

HTML Ops home-screen / PWA icons live under `ops/public/`: `apple-touch-icon.png` (180), `icon-192.png`, `icon-512.png`, plus square `favicon.svg` and `site.webmanifest`. iOS ignores SVG for Add to Home Screen - without the PNG it falls back to a letter tile from the page title. Fixed Mist + Signal Teal (no dark-mode swap) so the saved icon stays readable.

Composition (locked):

1. Horizontal teal route line
2. Two filled terminal nodes (same Signal Teal family as the line)
3. Open center node (interchange / classification point)
4. Short stem from the open node up into a Mist pill labeled **Metra**

Do **not** recolor the terminal nodes blue, amber, or other hues for “direction.” Geometry already carries origin → interchange → destination. Extra endpoint colors invent categories the product does not have and dilute brand coherence.

Dark mode uses a brighter teal on charcoal; light mode uses Signal Teal + Mist. Prefer `prefers-color-scheme` in the SVG for GitHub README.

### Brand story (short)

The Metra mark represents a routed path between endpoints. Metra does not replace humans or coding agents; it connects them through routing, context, decisions, audiences (`serves`), and communication. The open center node is where work is classified before moving forward.

The mark should read as **connection and flow** before anyone reads that sentence. Do not invent a longer mythology.

### Desk presence mark

The HTML Ops desk uses a larger wordmark-first treatment than the compact public mark: **Metra** text is the primary signal; the route line, stem, terminals, and open interchange sit beneath as motif. Do not trap the desk wordmark in a small pill.

The desk implementation keeps the mark in a dedicated presence component with `idle`, `listening`, and `speaking` visual states. Voice remains optional. While Ask (or Classify) is in flight, the HTML desk sets `listening` so the interchange node pulses, and the subtitle under the mark reads Working... `speaking` is reserved for spoken reply (TTS) when the parked iOS voice + listen path (or a later desk mic path) is active - see Future-Development Metra iOS and Decisions 2026-08-06 Voice Ask scar. Motion belongs to the route and interchange geometry, never a face, mascot, or separate avatar. The idle state does not move, and all active motion must honor `prefers-reduced-motion`.

The presence mark is an **awareness companion**, not a health dashboard or sensor legend. Presence-first Ops puts one truthful first-person Metra observation directly below the mark, then the shared Ask / Put somewhere composer. Updated time stays quiet; waiting / held counts live on the compact expandable Attention surface below the composer. Workload truth supports the relationship - it does not replace Metra with a scoreboard. See Decisions 2026-08-06 Ops presence-first correction and Ops desk three-layer model. Do not invent node meanings for terminals/interchange in the SVG until a Future-Development volume-v2 bite defines them.

### Visual vocabulary

Prefer:

- paths, nodes, routes, connections, hubs, interchanges

Avoid as brand chrome:

- brains, robots, assistants, chat bubbles, lightning bolts, mascots, emoji

Those cliches say “AI product.” Metra’s distinctive claim is portfolio operations and wayfinding.

## Typography

Use the host font. Monospace only for commands and paths (`.\metra.ps1`, folder names).

## Ops board layout target

Faceplate (top strip):

1. Left accent bar (`accent.primary`, ~3px)
2. Integrated route mark (teal path, open center, **Metra** label on stem - same composition as [`assets/metra-mark.svg`](assets/metra-mark.svg); host tokens, no hardcoded hex)
3. **Metra Ops** title
4. One-line subtitle + snapshot timestamp
5. Soft fill behind the strip (`fill.tertiary`) - Mist intent on light, elevated soft fill on dark

Do not add a second standalone **Metra** pill beside the title - the label lives on the mark.

Below that:

- Route / Portfolio / Stewardship pills (Route is default)
- Route: a capped Needs attention queue beside Resolve this; request preview and handoff by Where/What/Why/For whom/Next appear below
- Needs attention retrieves actionable portfolio and stewardship work, prioritizes verify/drift before git hygiene, and gives each row one next command
- Resolve this shows issue-specific summary / detail / done-when for a selected item; Ask Metra is the preferred path, Copy for terminal is optional self-serve
- Standing routes appear only when the queue is empty and no query is typed: default entry plus pinned present projects, as a jump list into the normal handoff
- An empty queue states why it is empty (quick snapshot skips git and verify) and offers a full re-scan
- Pinned workspace folders are not a hub card on the Route home; workspace membership is not routing priority
- A short collapsed Start here primer explains the board without turning the home into documentation
- Portfolio: needs-attention summary, root-filtered exceptions, project detail
- Stewardship: Portfolio Operating Model card, Decision Registry / OCC / coverage (read-only)
- Faceplate and tab navigation stay visible while long tab content scrolls

## Surface adapters

| Surface | Rule |
|---------|------|
| Cursor Canvas | Map brand intent to `useHostTheme()` tokens (`accent`, `fill`, `text`, `stroke`). No hardcoded hex in `.canvas.tsx`. |
| PowerShell CLI | Restrained Cyan headings; Yellow/Red for warning/error. Product name **Metra** in help text. Prefer Brand vocabulary in new operator-facing strings; terminal Ask/setup wording may lag until the Operator Vocabulary Pass. |
| Markdown docs / `ctx` packs | Neutral prose; product name **Metra** in titles. No teal wallpaper. |
| Installer (Inno) | Temporary first glimpse; Brand vocabulary + light first-person Welcome; Signal Teal / Mist / route mark; at most one dry beat on Welcome. Role = intent (including Files only). |
| Metra Ops Settings | Same role / Main Metra address vocabulary as the glossary below; factual, not humorous. |

## Naming boundary

| Operator-facing | Technical |
|-----------------|-----------|
| Product **Metra** | Checkout folder `_metra` (also accepted: `_meta`, `Metra`, `metra`) |
| Workspace file `Metra.code-workspace` | CLI `metra.ps1`, module `Metra.psm1`, config `metra.config.json` |
| Orchestration folder label **Metra** | Internal PowerShell `*-Metra*` function names |
| Canvas **Metra Ops** / `metra-ops-board` | Cursor path-derived state slug (e.g. `c-Projects-meta` for a `_meta` checkout) |
| Primary UI **Metra Ops** (HTML desk) | `ops/`, binding prefs, profile `opsBaseUrl` |

Legacy silent shims (one release; not taught): `meta.ps1` forwards to `metra.ps1`; loaders accept `meta.config.json` / `meta-profile.json` / `metaFolder*` keys; old `*-Meta*` function aliases remain exported.

## Operator vocabulary

Canonical **operator-facing** words. Brand owns this glossary; installer, Metra Ops Settings, and future onboarding consume it. Implementation names are not UI copy.

| Say (operator UI) | Avoid in UI | Technical / internal |
|-------------------|-------------|----------------------|
| **Metra** (product) | Setup Wizard chrome-as-brand | checkout `_metra` / `_meta` |
| **Metra Ops** (desk UI; name after first handoff) | Ops desk, Ops host, jumpbox | HTML `ops/`, `opsBaseUrl` key |
| **desk** / **work in Metra** | Ops desk (until Metra Ops is named) | - |
| **How should I show up on this PC?** | Run Metra setup now? | `Invoke-MetraSetup` |
| **HQ (Main Metra machine)** - Home base. Other devices come here to work in Metra | HQ hosts Ops / jumpbox | `machineRole: Hq` |
| **Satellite** - connects to your main Metra machine | use HQ Ops URL | `machineRole: Satellite` |
| **Standalone** - everything stays on this PC | local only; no remote Ops | `machineRole: Standalone` |
| **Files only** - Install Metra now. Choose a role later. (installer only) | Skip setup / uncheck Run setup | no postinstall setup |
| **Main Metra address** | OpsBaseUrl, HQ Ops URL | profile `opsBaseUrl` |
| **Ask assistant** | Ask engine (operator labels) | engine APIs / Ollama under the hood |
| **Here's where we're landing** | Setup Summary | - |

**Product vs primary UI:** Product = **Metra**. Primary UI = **Metra Ops**. Introduce Metra Ops on installer Finished (and Start Menu); earlier installer pages stay Metra / desk / work in Metra.

**Review standard:** Is this operator text? Check this glossary. New operator surfaces must use it.

### Operator voice / dry humor

Calm, direct, competent, slightly personal. Role = intent. Wayfinding motif - no mascot.

Dry desk humor may appear on chat and light temporary operator UIs (installer Welcome at most one beat). Never a joke quota. Coworker-at-the-next-desk, not salesy or cute.

**Off:** tickets, commits, ADRs, redistribution (professional sink); refuse dialogs; incident / outage tone. Settings stay factual.

Humor **dials and palette** live in [`.cursor/rules/metra-persona.mdc`](../.cursor/rules/metra-persona.mdc) and optional humor-desk add-on - do not duplicate that table here. Brand owns the **boundary**; persona owns the **dial**.

## Professional sink

Chat and operator UIs may show Metra branding. Tickets, commits, ADRs, and redistribution drafts do **not** get Metra voice, catchphrases, or decorative brand chrome.

## Screenshot approval checklist

Capture **Metra Ops** (Ops tab) under **Cursor Light** and **Cursor Dark**. Re-run `.\metra.ps1 snapshot` if the board looks stale. Submit both shots for approval against this list:

| Check | Light | Dark |
|-------|-------|------|
| Reads as Metra Ops, not a generic status widget | | |
| Route mark visible; nodes + line use accent | | |
| Faceplate soft fill distinct from page background | | |
| Zero-drift / healthy stats calm (success), not loud | | |
| Dirty / missing / drift use amber-like attention (warning) | | |
| No gradients, glow, emoji, or heavy shadows | | |
| Amber not used as general decoration | | |
| Same information hierarchy in both modes | | |

Pass = both columns feel like one product at different times of day. Fail = dark looks like a different app, or light loses the wayfinding accent.

## Related

- [Overview.md](Overview.md) - audience overview / leave-behind (prose twin of self-doc canvas)
- [Customizing-Metra.md](Customizing-Metra.md) - persona, Origin, and overlays
- [Decisions.md](Decisions.md) - append-only portfolio decisions (incl. brand bounds)
- [Integrations.md](Integrations.md) - core vs Cursor
- [Context-Routing.md](Context-Routing.md) - Ops board refresh
