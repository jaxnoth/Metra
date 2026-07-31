# Metra brand kit

Compact identity for **operator-facing** Metra surfaces. Durable artifacts (tickets, commits, coworker redistribution, professional docs meant for iSupport) stay unbranded.

## Customization boundary

How far Metra goes into Cursor:

| Layer | Stance |
|-------|--------|
| Metra Ops canvas | Customize deeply (layout, motif, dual-mode intent) |
| CLI help colors | Light touch (Cyan / Yellow / Red) |
| Naming (`Metra`, workspace label) | Yes |
| Optional local accent override | Allowed - Signal Teal into host accent only |
| Full Cursor color theme extension | Out of scope (optional personal experiment only) |
| Activity bar / title bar takeover | No |

Host-following stays the rule for canvases: map brand **intent** through `useHostTheme()` - no hardcoded hex in `.canvas.tsx`. Reference hex below is for docs, approval screenshots, and optional local Cursor accent overrides.

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

Canonical file: [`assets/metra-mark.svg`](assets/metra-mark.svg).

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
| PowerShell CLI | Restrained Cyan headings; Yellow/Red for warning/error. Product name **Metra** in help text. |
| Markdown docs / `ctx` packs | Neutral prose; product name **Metra** in titles. No teal wallpaper. |

## Naming boundary

| Operator-facing | Technical |
|-----------------|-----------|
| Product **Metra** | Checkout folder `_metra` (also accepted: `_meta`, `Metra`, `metra`) |
| Workspace file `Metra.code-workspace` | CLI `metra.ps1`, module `Metra.psm1`, config `metra.config.json` |
| Orchestration folder label **Metra** | Internal PowerShell `*-Metra*` function names |
| Canvas **Metra Ops** / `metra-ops-board` | Cursor path-derived state slug (e.g. `c-Projects-meta` for a `_meta` checkout) |

Legacy silent shims (one release; not taught): `meta.ps1` forwards to `metra.ps1`; loaders accept `meta.config.json` / `meta-profile.json` / `metaFolder*` keys; old `*-Meta*` function aliases remain exported.

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

- [Demo-5min.md](Demo-5min.md) - coworker walkthrough (concepts for low AI experience + live demo)
- [Customizing-Metra.md](Customizing-Metra.md) - persona, Origin, and overlays
- [Decisions.md](Decisions.md) - append-only portfolio decisions (incl. brand bounds)
- [Integrations.md](Integrations.md) - core vs Cursor
- [Context-Routing.md](Context-Routing.md) - Ops board refresh
