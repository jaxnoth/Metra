# Plan: iOS presence behavior and face transitions

**Status:** Approved with amendments (Bing 2026-08-29; structural cleanup same day); Brand.md iOS subsection landed 2026-08-29  
**Review date:** 2026-08-29  
**Owner surface:** Metra iOS companion  
**Excluded surface:** HTML Ops desk presence mark (route geometry only; no face)  
**Default pose:** `warm/attend`  
**Locked catalog:** Nine variants  
**Speech appendix status:** Operator-approved design contract; optional reviewer pass. Amendments must keep one-node, on-path articulation unless the operator explicitly reopens it.  
**Voice identity:** [ios-voice-identity.plan.md](ios-voice-identity.plan.md) - provisional default **Siri Voice 4** (operator 2026-08-29)  
**Conversation policy:** [ios-conversation-policy.plan.md](ios-conversation-policy.plan.md) (Desk / Company / Deliver; **Approved** Bing second review 2026-08-29) - orthogonal to face geometry  
**Next bite:** park until companion app / further planning - no implementation wiring yet  
**Assets:** [`assets/metra-presence-face.svg`](assets/metra-presence-face.svg), gallery [`assets/metra-presence-face.html`](assets/metra-presence-face.html), base mark [`assets/metra-mark.svg`](assets/metra-mark.svg)  
**Supersedes:** `ios-presence-face-transitions.plan.md` (stub redirect)

---

## 1. Intent

Give the iOS companion a readable presence that:

1. Starts from the **base Metra mark** (route + nameplate, no face).
2. Settles into **Warm / attend** as home, recovery, incident settle, and cross-mood hub.
3. Moves among faces from **product cues**, not free-running personality noise.
4. Renders cross-mood movement through a **perceptually stable** `warm/attend` pose.
5. Keeps behavior **explainable, reason-coded, interruptible, and fail-closed**.

The face is still the **nodes mark**: nameplate, stem, route line, terminal nodes as eyes, open center as mouth. Awareness companion - not scoreboard, chat bubble, or emoji avatar.

**Architecture principles**

- Public mark remains faceless and canonical.
- Facial reading is limited to the iOS companion.
- Same-mood movement is direct; cross-mood normalizes through `warm/attend`.
- Playful requires contextual justification and enters through `wave`.
- Semantic intent is separate from rendered pose.
- Incident, accessibility, backgrounding, and stale-cue behavior are explicit.
- Live voice articulation is a **reserved overlay** (Appendix A), not a presence-v1 ship requirement.

---

## 2. Locked visual catalog

| Mood | Variant | Role |
|------|---------|------|
| **Warm** | `attend` | **Hub / default / recovery / incident settle.** Soft solid ovals, faint smile, open node on the route. Startup target. |
| Warm | `empath` | Wider soft ovals; slightly broader mouth. Care-oriented; keep close to attend. |
| Warm | `welcome` | Rounder, more open. Arrival / greeting - not permanent idle. |
| **Curious** | `glance` | Reversed eyes (teal field + light gaze dot); nameplate leans right. |
| Curious | `ask` | Uneven reversed eyes; stronger mouth-o; light letter peek. |
| Curious | `lean` | Gaze + nameplate lean left. Dig deepens. |
| **Playful** | `wave` | **Only cross-mood Playful entry.** Round eyes, letter wave, wink, medium bounce. |
| Playful | `spark` | Diamond eyes, letter hops, plate spin. Same-mood escalation from `wave` only. |
| Playful | `cheeky` | Squint bars, tumble letters, bigger bounce. Same-mood; humor-aligned cue only. |

**Visual rules**

- Warm: soft oval shape, **no iris**.
- Curious: **reversed** eye colors (required) + nameplate lean on glance/lean.
- Playful: distinct eye geometry (do not flatten to Warm ovals).
- Warm open node sits **on** the soft smile path.

Pill / twin-pill layouts stay in `assets/presence-stash/` only.

---

## 3. System model

```
PresenceModel
├── semanticState      // durable presence intent
├── renderState        // what animation is drawing
├── policyState        // accessibility, incident, budget, clocks
└── voiceOverlayState  // transient listen/speech modulation (Appendix A; off in presence v1)
```

Mood and variant are durable semantic presence intent. Speech and listening are transient modulation. Mic energy is an input measurement, not face meaning. Face mood controller and voice controller remain separate owners.

---

## 4. Semantic state

| Field | Role |
|-------|------|
| `mood` | warm / curious / playful (or none while on MARK) |
| `variant` | attend / empath / welcome / glance / ask / lean / wave / spark / cheeky |
| `cueId` | Originating product cue |
| `reasonCode` | Why this pose (required for every semantic transition, including micro-progressions) |
| `priority` | See §14 priority classes |
| `cueActive` | Whether the originating cue is still valid |
| `enteredAt` | Monotonic time of semantic entry |

Speech and listen fields do **not** live here (see Appendix A / `voiceOverlayState`).

---

## 5. Render state

| Field | Role |
|-------|------|
| `sourcePose` | Pose leaving |
| `displayedPose` | What is on screen now |
| `targetPose` | Pose converging toward |
| `phase` | idle / morph-in-hub / hub-hold / morph-out / settle |
| `phaseStartedAt` | Monotonic |
| `transitionId` | Correlates legs of one semantic transaction |
| `moodMouthPath` | Catalog route/mouth geometry for current mood+variant |
| `nodePose` | Optional open-center node modulation from voice overlay (`rest` when overlay inactive) |

**Example:** while rendering `curious/ask → warm/attend → playful/wave`, semantic target may already be `playful/wave` while `displayedPose` is still `warm/attend`. Cancellation and telemetry use semantic + render (+ voice overlay), not a mashed `currentState`.

---

## 6. Policy state

| Field | Role |
|-------|------|
| `reducedMotion` | Accessibility |
| `incidentActive` | Suppresses Playful, decorative motion, and **visual** speech chatter |
| `foreground` | Backgrounding rules |
| `transitionBudget` | Rolling semantic caps |
| `voiceOverlayEnabled` | When false (presence v1 default), ignore voice overlay inputs |

**Clocks:** monotonic process clock for animation, dwell, and rolling caps. Wall-clock for telemetry only. Clock adjustments must not reset or extend transition budgets.

---

## 7. Face state machine

### 7.1 Poses

```
MARK          = base logo (no facial eyes)
WARM/attend   = hub / default / recovery / incident
WARM/*        = empath | welcome
CURIOUS/*     = glance | ask | lean
PLAYFUL/*     = wave | spark | cheeky
```

### 7.2 Edges (hard rules)

| From | To | Allowed? | Path |
|------|-----|----------|------|
| `MARK` | `warm/attend` | Yes | Cold start / new session / explicit branding reset |
| `warm/attend` | `warm/empath`, `warm/welcome` | Yes | Direct; cue + reasonCode |
| `warm/attend` | `curious/*` | Yes | Direct morph out of hub |
| `warm/attend` | `playful/wave` | Yes | **Only** Playful cross-mood entry |
| `warm/attend` | `playful/spark` or `cheeky` | **No** | Escalate only from `playful/wave` |
| Same mood, other variant | Same mood, other variant | Yes if cue permits | Direct; **reasonCode required**; no catalog walking |
| Mood A (not attend) | Mood B | **No direct** | `current → warm/attend → target` (one **semantic** transition; two render legs) |
| Any face | `MARK` | Rare | Branding, signed-out / inactive, shutdown, or renderer fallback - **not** incident |

**Cross-mood contract**

> Every cross-mood transition renders through `warm/attend`. Under normal motion, Attend must be perceptually stable for **600–900 ms** before departure. The hold may be interrupted by incident priority, application lifecycle changes, cue cancellation, or a newer valid target. If Attend was already stably displayed, **no additional hub hold** is required.

### 7.3 Startup

1. Show **MARK**.
2. Morph **MARK → warm/attend** (900–1200 ms).
3. Hold Attend **≥ 2 s** before any other face.
4. Do not auto-walk the catalog. Do **not** restore a persisted expressive pose from a prior session.

### 7.4 Same-mood flow

**Guard A - cue compatibility.** Sibling variants only when the active cue permits them.

**Guard B - no decorative catalog walking.** Disallow automatic variety tours whose only reason is showing the set.

> Same-mood transitions may occur directly when the cue meaning changes or an allowed animation sequence explicitly progresses. **Variant diversity alone is not a valid transition reason.**

### 7.5 Playful escalation

```
warm/attend → playful/wave → playful/spark | playful/cheeky
```

Playful stays **cue-gated in v1**. No idle surprises. Future `ambientPersonality` (off by default; suppressed during focus / incident / screen share / inactivity; rate-limited; **wave only**; decorative reason code) is parked - not v1.

### 7.6 Incident contract

**Freeze at `warm/attend`, not MARK.**

```
any state
  → cancel queued expressive transitions
  → warm/attend
  → suppress Playful
  → suppress decorative motion
  → suppress visual speech/listen node chatter (Appendix A)
  → retain only minimal operational presence
```

Incident Attend uses the same locked artwork with quieter animation. Severity lives in the surrounding UI.

**Audio vs visual:** Incident mode does **not** independently cancel operationally necessary audio. It suppresses decorative or syllabic **node** animation. If speech continues, the node stays at `rest` or performs one minimal state-entry fade. Audio authority belongs to voice/incident policy, not the face renderer.

**MARK reserved for:** cold-start source, explicit branding, signed-out / intentionally inactive, shutdown, true renderer fallback.

---

## 8. Cue policy

| Cue class | Target | Notes |
|-----------|--------|--------|
| Cold start / new session | `warm/attend` | From MARK |
| Idle / ticket flat / ops steady | Stay or return `warm/attend` | Via hub if leaving another mood |
| Soft acknowledgment / care | `warm/empath` | Cue must justify care reading |
| Greeting / welcome back | `warm/welcome` | Not persistent idle |
| Initial inspection | `curious/glance` | |
| Clarification requested | `curious/ask` | May outlive short dwell while awaiting answer |
| Dig deepens | `curious/lean` | Same-mood OK |
| Light humor / celebration entry | `playful/wave` | Via attend if cross-mood |
| Energetic success (already Playful) | `playful/spark` | Same-mood escalation only |
| Explicit humor-aligned beat | `playful/cheeky` | Same-mood; highest bar |
| Incident / outage / urgent | Static `warm/attend` | §7.6 |
| Offline | Capability, **not** a mood | Stay attend unless a local cue is valid; show offline elsewhere |
| `prefers-reduced-motion` | Cuts / short fades; hub order preserved | §13 |

Do **not** drive face from Attention count badges or health dashboards.

---

## 9. Cadence

Policy constants. Monotonic clock.

| Event | Value |
|-------|--------|
| Cold-start `MARK → warm/attend` | **900–1200 ms** |
| Startup Attend hold | **≥ 2 s** |
| Same-mood geometry transition | **350–550 ms** |
| Incompatible eye-layer crossfade | **180–280 ms** (nested) |
| Minimum ordinary target dwell | **3 s** (anti-flicker only) |
| Typical cue-controlled dwell | **While cue remains active** |
| Conversational non-hub span (guidance) | **6–15 s** when cues are short-lived |
| Autonomous decorative **micro-sequence** | **At most once per 45–90 s**; never while originating cue still active |
| Cross-mood leg into Attend | **350–550 ms** |
| Normal Attend hub hold | **600–900 ms** |
| Playful recovery Attend hold | **800–1200 ms** |
| Incident / urgency to Attend | **Immediate** |
| Already-stable Attend + new target | **No new hub hold** |
| Reduced-motion hub hold | **300–500 ms** |
| Cross-mood leg out | **350–550 ms** |
| Return after cue clears | Begin within **500–1000 ms** |
| Ordinary mood change while `speechActive` | May defer render until phrase boundary (Appendix A); semantic target may update immediately |
| Normal **semantic**-transition budget | **3 per rolling minute** |
| Hard semantic-transition ceiling | **5 per rolling minute** |
| Emotion-change ceiling | **2 per rolling minute** |
| Reduced-motion fades | **0–150 ms** |

**Budget accounting:** `ask → attend → wave` counts as **one semantic transition**. Hub pass-through legs do not each consume a full semantic swap credit.

**Cue lifetime vs dwell**

> Dwell timers do **not** terminate semantic cues. Minimum dwell prevents flicker. Cue lifetime owns meaning. Decorative-loop duration limits repetitive motion.

An `ask` pose may remain while Metra awaits an operator answer. Leaving solely because a timer elapsed would falsely imply the inquiry expired.

Separate:

1. **Minimum visual dwell** - prevents flicker.
2. **Cue lifetime** - owns semantic state.
3. **Maximum decorative micro-sequence duration** - prevents repetitive idle animation.

**Autonomous decoration** means a **micro-sequence within the active pose** - not a catalog `(mood, variant)` change. Examples: one allowed blink, small settle, restrained nameplate movement. Requires a decorative reason code. Does **not** consume a semantic-transition credit. Uncued catalog variant changes are not allowed.

---

## 10. Transition rendering

| Technique | Use for |
|-----------|---------|
| **Geometric interpolation** | Compatible topology: nameplate pose/rotation, stem, route-mouth curvature, open node position, Warm oval width/height, whole-composition lean, small scale/translation |
| **Crossfade / layered replace** | Incompatible geometry: Warm oval ↔ Curious reversed circle; round ↔ diamond; diamond ↔ squint; open ↔ wink; tumbling letter paths; malformed control-point blends |

**Architecture**

- Shared structural layer interpolates continuously.
- Incompatible eye layers crossfade **~180–280 ms** inside the larger transition.
- Nameplate and route keep moving through the eye crossfade.
- Outgoing and incoming eye layers share the same visual center.
- Reduced motion: cut or short opacity fade; no continuous loops.

```
PresenceFace
├── NameplateLayer
├── StemLayer
├── LeftEyeLayer
├── RightEyeLayer
├── RouteMouthLayer
└── OpenNodeLayer
```

Controller requests a **pose**. Renderer decides what interpolates vs replaces. Do not morph the entire SVG as one object.

---

## 11. Brand and surface boundaries

| Surface | Rule |
|---------|------|
| **Public / README mark** | `metra-mark.svg` - route story, no face. |
| **HTML Ops desk** | Wordmark + route motif; voice/attention as data attributes; **no facial presence**. |
| **iOS companion** | Nodes composition **may** use facial reading via `metra-presence-face.svg`. |

**Next docs bite:** Brand.md **iOS presence** subsection pointing at this plan: Warm/attend default; cross-mood via Attend; Playful entry via `wave`; incident → Attend; Ops desk “no face” unchanged; voice overlay reserved (Appendix A).

---

## 12. Telemetry

Optional, privacy-light: mood, variant, reasonCode, priority, transitionId, whether hub was visited, incidentActive, reducedMotion. No facial “emotion AI.” Voice overlay events (when enabled) carry `utteranceId` / sequence for diagnostics - not content transcripts in the face channel.

---

## 13. Accessibility and reduced motion

| Setting | Behavior |
|---------|----------|
| Reduced motion | No continuous letter bounce / wink loops. Cross-mood still visits Attend. Morphs → cuts or **0–150 ms** fades. Hub hold **300–500 ms** unless interrupted. Voice node loops off (Appendix A). |
| Screen reader | Expose mood+variant on **stable** variant changes only. Do not narrate every animation frame or micro-motion. |
| Contrast | Signal Teal / Mist tokens; dark mode brighter teal on charcoal per Brand.md. |

---

## 14. Priority, interruptions, and failures

### 14.1 Queue rule

> Presence transitions use a **bounded, coalescing target model**, not an animation FIFO. The newest valid cue at the highest active priority replaces stale pending targets. Incident clears all non-incident pending targets.

### 14.2 Priority classes

1. incident / safety  
2. operator-explicit  
3. active interaction / clarification  
4. greeting  
5. completion / acknowledgment  
6. playful  
7. idle / ambient  
8. decorative  

Never delay incident Attend behind queued Playful. Decorative cues cannot supersede active interaction.

### 14.3 Failure and interruption matrix

| Case | Rule |
|------|------|
| **A. Background mid-transition** | Stop animation clocks; do not continue expressive work invisibly. Preserve latest semantic cue separately from render progress. On foreground: re-evaluate cue; converge to correct **stable** pose; do not replay missed choreography; do not run cold-start MARK unless product defines a new session; if continuity uncertain → `warm/attend`. Suspend voice-overlay timing without losing semantic mood. |
| **B. Rapid cue spam** | Latest-valid-intent wins under priority. Cancel uncommitted targets; coalesce/drop with diagnostics; no unbounded queue. |
| **C. Cue changes during hub hold** | If Playful clears while holding Attend: cancel `playful/wave`, remain Attend. If a new Curious cue arrives during hold: proceed to newest Curious target; do not finish obsolete Playful first. |
| **D. Cue expires before min dwell** | Incident and lifecycle may interrupt immediately. Operator-explicit may interrupt. Ordinary cue clear may finish a short exit-safe dwell. Decorative drops freely. |
| **E. Offline** | Capability condition, not mood. No invented Curious / sad / concerned. Maintain attend unless a local cue is valid. |
| **F. Renderer / asset failure** | Atomic fallback to stable attend snapshot if available; else MARK. Never assemble a partial face. Fallback is not an emotional state. |
| **G. Relaunch / persisted mood** | Do not persist prior expressive pose across cold start. Always `MARK → warm/attend`. |
| **H. Clock changes** | Monotonic clock for cadence. Wall-clock for telemetry only. |
| **I. Simultaneous cues** | Highest priority wins; document conflicts in tests. |
| **J. Generation / voice latency** | Do not hold `curious/ask` solely because a request is processing. Distinguish internally: user being asked; Metra investigating; waiting on a service; idle. |
| **K. Mood change while speaking** | See Appendix A phrase-boundary deferral. Incident/lifecycle interrupt immediately. |
| **L. Stale voice events** | Reject by `utteranceId` / sequence (Appendix A). |

---

## 15. Implementation bites

Independently reviewable slices:

| Bite | Scope |
|------|--------|
| **1. Brand contract** | Brand.md iOS presence subsection; Ops no-face rule; Warm/attend defaults; Playful via wave; point at locked catalog + this plan. |
| **2. Pure controller** | `semanticState` / `renderState` / `policyState`; legal-edge validation; cue priority + coalescing; transition budget; monotonic clock. No polished animation required. |
| **3. Stable pose renderer** | All nine poses as layers; immediate pose selection; atomic fallback to Attend snapshot or MARK; dark mode / contrast. |
| **4. Transition renderer** | Compatible geometry interpolation; incompatible-layer crossfades; hub phases + cancellation; reduced motion. |
| **5. Lifecycle and incident hardening** | Background/foreground; incident override; offline; renderer failure; clock-change and cue-spam tests. |
| **6. Voice seam only** | `voiceOverlayState`; node-pose API + ownership; aperture envelopes and caps; **no live TTS yet**. |
| **7. Voice integration** | Word/syllable markers; utterance IDs + stale rejection; listen energy smoothing; incident / a11y / background interactions. |

Presence v1 ships through bite 5 (plus Brand). Bites 6–7 are explicit follow-ons.

---

## 16. Tests

### 16.1 Face / transition

- Cross-mood request passes through a legible Attend state.
- No redundant hub delay when already on Attend.
- Cue clears while holding at Attend.
- Target changes twice while morphing into Attend.
- Incident arrives during `playful/spark`.
- Incident clears with no previous Playful resurrection.
- Foreground after background mid-morph.
- Cold start ignores persisted expressive pose.
- Reduced motion: no continuous loops; semantic hub ordering preserved.
- Clock adjustment does not reset or extend transition budget.
- Asset failure falls back atomically to Attend snapshot or MARK.
- `spark` and `cheeky` cannot be cross-mood entry targets.
- Same-mood variation requires a valid reasonCode.
- Repeated identical cues do not restart the same animation.
- Offline does not invent an emotional pose.
- Decorative cue cannot supersede active interaction.
- Autonomous decoration does not change `(mood, variant)`.
- Accessibility name changes only on stable variant changes.
- Illegal edge: cross-mood without Attend.
- Semantic budget: `ask → attend → wave` counts as one semantic transition.
- Caps: normal 3 / hard 5 semantic transitions per rolling minute; emotion ceiling 2.

### 16.2 Cross-controller races (required when voice seam exists)

- Mood transition requested while `speechActive`: ordinary transition waits for phrase boundary; semantic target may update immediately.
- Incident interrupts speech articulation immediately (visual); does not assume face muted TTS.
- Stale speech event arrives after `clearSpeech()`.
- Stale utterance event arrives after a new utterance begins.
- Backgrounding clears or suspends voice-overlay timing without losing semantic mood.
- `speechActive` becomes false while a hub transition is pending.
- Reduced-motion mode changes while speech is active.
- Incident clears while audio remains active - node stays rest/minimal; no Playful resurrection.
- Listen energy falls below threshold without rapid `hold` ↔ `receive` flicker (hysteresis).
- Device’s own TTS must not generate listen pulses if input/output paths overlap.
- Node pose restoration after speech uses the **current** face pose, not the pose from utterance start.

Appendix A lists voice-shape tests for bites 6–7.

---

## 17. Non-goals

- No Canva-dependent animation pipeline.
- No separate mascot / emoji avatar beside the mark.
- No auto-tour of all nine faces on launch.
- No face driven by ticket volume badges.
- No resurrecting pill/twin-pill presence layouts in product.
- No Ops desk facial presence.
- No live TTS / phoneme lip-sync in presence v1 (Appendix A is reserved contract only).
- No Disney-style jaw, teeth, lips, or second mouth.
- No v1 idle Playful surprises / ambientPersonality (parked).
- No incident → MARK (except true renderer fallback).
- No uncued autonomous catalog variant changes.
- No forcing all eye types through one universal path morph.
- No face renderer authority over muting necessary audio.
- No TTS voice selection or mood→voice binding in this plan (voice module / Brand; see Appendix A.0).

---

## 18. Decision record

**2026-08-29 (Bing + operator):** Approve face transition architecture with cadence/hub amendments. Nine faces locked; `warm/attend` hub; Playful via `wave`; incident → static Attend; hybrid morph; coalescing cues; monotonic clocks.

**2026-08-29 (operator):** Mouth/speech overlay design locked: per-mood envelopes; listen inward pulse vs soft hold; mood mouth yields while speaking; vowel/consonant classes into six node poses; aperture capped to mood mouth.

**2026-08-29 (Bing structural pass + Metra fold):** Scope renamed to **presence behavior**. Split `voiceOverlayState` from semantic state. `SpeechPose` excludes listen `hold`. Incident suppresses visual articulation, not necessarily audio. Autonomous decoration = micro-sequence within pose. Phrase-boundary deferral for ordinary mood changes during speech. Utterance IDs + stale rejection. Voice contract moved to Appendix A for presence-v1 clarity. Implementation sliced into bites 1–7.

---

## 19. Revision log

| Date | Change |
|------|--------|
| 2026-08-29 | Initial transition draft for Bing. |
| 2026-08-29 | Bing approve-with-amendments folded (hub, cadence, Playful, incident, hybrid morph, failures). |
| 2026-08-29 | Operator mouth/speech addendum + vowel/consonant shapes. |
| 2026-08-29 | **Behavior-contract cleanup:** rename/retitle; metadata block; `voiceOverlayState`; SpeechPose vs ListenPose; incident audio/visual split; micro-sequence cadence; speech×mood deferral; stale voice events; race tests; Appendix A; implementation bites 1–7. |
| 2026-08-29 | **A.0 voice identity seam:** voice selection owned by voice module / Brand; presence consumes utterance events only. |
| 2026-08-29 | Brand.md iOS companion presence subsection landed; conversation policy plan linked. |

---

## Appendix A: Reserved voice-overlay contract

**Authority:** Operator-approved design contract. Optional external review may refine values and edges; it must not silently reopen one-node, on-path articulation.

**Presence v1:** Overlay disabled (`voiceOverlayEnabled = false`). Bites 6–7 implement this appendix.

### A.0 Voice identity ownership

**Voice identity is owned by the voice module** (and Brand.md when a default Metra voice is published). Presence consumes utterance and listen **events** only.

Out of scope for this plan and for the face controller:

- TTS voice catalog, picker UI, provider voice IDs
- Locale, rate, pitch, SSML, and timbre presets
- Mapping moods to different selected voices (e.g. “Warm uses Voice A”)

In scope for presence:

- Reacting to `speechActive` / listen / pose / marker events from whichever voice is selected
- Per-**face-mood** node envelopes and aperture caps (not per-timbre)
- Not inventing a tenth face or a new mouth alphabet when the selected voice changes

Swapping one TTS voice for another must not change the locked nine-face catalog or the node pose alphabet.

### A.1 `voiceOverlayState`

| Field | Role |
|-------|------|
| `listenActive` | Mic / listen path armed |
| `micEnergy` | Normalized input level 0..1 (measurement, not mood) |
| `speechActive` | TTS / spoken output in flight |
| `speechPose` | `rest` \| `closed` \| `mid` \| `wide` \| `round` |
| `listenPose` | `rest` \| `hold` \| `receive` |
| `nodePose` | Resolved open-node pose after policy (see A.2) |
| `utteranceId` | Active utterance identity |
| `speechEventSequence` | Monotonic per-utterance event order |
| `markerQuality` | none / word / syllable |
| `envelope` | warm / curious / playful multiplier in force |
| `lastUpdatedAt` | Monotonic |

### A.2 Node pose vocabulary

Renderer-facing union:

```
NodePose = rest | closed | mid | wide | round | hold
```

Ownership:

| Source | Allowed poses |
|--------|----------------|
| **SpeechPose** | `rest` \| `closed` \| `mid` \| `wide` \| `round` |
| **ListenPose** | `rest` \| `hold` \| `receive` (receive = inward scale; maps toward `hold`/`closed` visually) |

`hold` is **not** a speech phoneme. The voice module must not emit `hold` on the speech channel during articulation.

While speech and listen conflict, **speech wins** until `speechActive` clears.

### A.3 Layer model

| Layer | Owns | Does not own |
|-------|------|--------------|
| **Mood mouth** | Catalog route path | Syllable timing |
| **Speech / listen overlay** | Open-center **node** scale, aspect, short vertical travel **on** the mood path | Eye mood, nameplate lean, Playful letter motion |

Rules:

1. Open node stays **on** the mood route.
2. Speaking does not replace the mood path mid-utterance.
3. One mouth only - no jaw, teeth, lips, or second stroke.
4. Voice writes short-lived overlay fields; presence clears them when audio ends.

### A.4 Articulation alphabet and shape classes

Syllable / word beats, not phoneme visemes. **No seventh “spread/ee” pose** - fold into `mid` / capped `wide`.

| SpeechPose | Reads as |
|------------|----------|
| `rest` | Between phrases; speech inactive |
| `closed` | Stop / consonant hit |
| `mid` | Neutral syllable; schwa; soft fricative bed; light “ee/ih” |
| `wide` | Open vowel / emphasis; stronger “ee” only under Curious/Playful envelope |
| `round` | Rounded vowel color |

**Vowels:** open→`wide`; neutral→`mid`; round→`round`; spread→`mid` or slight `wide` (Curious/Playful only).

**Consonants:** stops→short `closed`; nasal→`closed`→soft `mid`; fricative→near `mid` flicker (no pinprick); liquid/glide→bias to next vowel.

**Timing:** onset→nucleus when syllable marks exist; else one nucleus per word; else synthetic beat grid.

**Aperture cap:** clamp to current mood mouth aperture after yield. Curious `ask` must not shout past ask-mouth budget.

### A.5 Per-mood envelopes

| Mood | Envelope |
|------|----------|
| Warm | Low; spread stays `mid`; almost no vertical travel |
| Curious | Medium; aperture ≤ ask/mood cap |
| Playful | Higher; short vertical bob allowed; still on-path |

Apply envelope after shape-class choice, then aperture cap. Incident / reduced motion force Warm-or-lower or overlay off.

### A.6 Listen behavior

| Mic | ListenPose |
|-----|------------|
| Input above threshold | `receive` (inward pulse, energy-tied, hysteretic) |
| Armed but quiet | `hold` |

### A.7 Yielding

While `speechActive`, speech overlay owns the open node. Curious `ask` mouth-o yields. On clear, restore catalog mouth for current mood/variant.

### A.8 Speech across mood change

> While `speechActive`, ordinary mood transitions may be **deferred until the next word or phrase boundary**. Semantic target may update immediately; rendering waits for the boundary. Incident and lifecycle transitions interrupt **immediately**. A newly requested transition must not replay stale speech poses after the face transition.

Voice supplies the phrase boundary when available. If no marker exists, treat `speechActive == false` as the boundary.

### A.9 Stale voice-event rejection

Ignore speech-pose events whose `utteranceId` is no longer active or whose `speechEventSequence` is older than the most recently accepted event for that utterance. Consistent with coalescing face transitions.

### A.10 Incident and reduced motion (visual only)

| Condition | Overlay |
|-----------|---------|
| Incident | Suppress syllabic node animation; node `rest` or one minimal fade. **Do not** treat face controller as TTS mute authority. |
| Reduced motion | No loops; optional single fade to `mid`/`rest` |
| Background | Suspend overlay timing; keep semantic mood |

### A.11 API sketch

```
setListen(active, micEnergy?)
setSpeech(active, utteranceId)
setSpeechPose(pose, utteranceId, sequence)  // rest|closed|mid|wide|round
clearSpeech(utteranceId?)
```

Voice owns timing and phoneme→class→SpeechPose mapping. Presence owns envelopes, aperture cap, yielding, stale rejection, and policy clamps.

### A.12 Appendix tests (bites 6–7)

- Node stays on mood path.
- Warm envelope < Curious/Playful for same pose.
- Listen quiet → hold; energy → receive; not speech alphabet.
- `curious/ask` yields mouth-o; restores after clear.
- Aperture never exceeds mood mouth budget.
- No seventh spread pose.
- Onset→nucleus vs word-nucleus timing.
- Stops short `closed`; fricatives not pinprick.
- Incident suppresses visual syllable motion without requiring face to stop audio.
- Stale utterance/sequence rejected.
- Phrase-boundary deferral for ordinary mood change; incident immediate.
- Own-TTS does not drive listen pulses.
- Restore uses current face pose after speech ends.

### A.13 Appendix non-goals

- No phoneme-accurate lip sync in the face controller.
- No waveform mouth.
- No separate talking-face catalog variant.
- No hold on the speech pose channel.
- No voice selection, timbre catalog, or mood→voice binding in the presence controller (see A.0).
