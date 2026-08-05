# Metra decisions

Append-only record of **portfolio-wide** Metra behavior choices. Newest first. Professional prose only - no chat persona voice.

**When to append:** a routing, persona, brand, hook, or registry policy choice that should stick across chats and machines.

**When not to append:** routine tickets, one-off code fixes, temporary experiments.

Entry shape:

```markdown
## YYYY-MM-DD - Short title

- Decision: ...
- Why: ...
- See: path or command
```

---

## 2026-08-05 - Route something (portfolio landing zone)

- Decision: Route Something is Metra's landing zone. It accepts work in whatever form it arrives (text, clipboard paste, path refs, file upload to local quarantine) and recommends a durable home without creating one automatically. Classify / Handoff is retired from the Ops UI; `Get-MetraDeskHandoff` remains for Ask internals. Ask shows a quiet Where chip only when the route is weak or ambiguous, with optional "This belongs in…" corrections that create Decision Registry candidates and place memory. Recommendation cards teach with Recommended home, Why, What happens there, and Your move (Copy / Keep in view / affirm for learning). Keep in view maps to Attention Hold. Place learning stores confirmations/corrections in `docs/ops-place.local.json` and enriches Why on later routes. When `bindTailscale` is on, Ops orchestrates Tailscale Serve so the share URL is HTTPS (secure context for phone clipboard); Serve is not required to run Metra; Funnel stays out of scope. Quarantine uploads are Ask-class reach; durable homes stay Host-gated.
- Why: Operators shove ticket text, screenshots, and notes at Metra from phone-over-Tailscale - Classify was builder language, text-only intake felt fake, and plain HTTP blocked clipboard APIs.
- See: `scripts/private/Place.ps1`, `scripts/private/OpsServe.ps1`, `scripts/private/OpsBinding.ps1`, Ops Route panel, [ops/README.md](../ops/README.md), [SECURITY.md](../SECURITY.md)

## 2026-08-05 - Attention card copy is plain by default

- Decision: Next attention headlines, whyNext, resolveCopy, and doneWhen use plain language for every desk mode. Advanced desk reveals technical detail (original content, command, path, type/confidence meta). General mode stays action-first: what is wrong, why now, what to do.
- Why: Default Ops copy assumed CLI/git fluency and buried the next step under enums and meta tags - the desk is for operators who may not be technical.
- See: `Get-MetraAttentionPlainSummary`, `Get-MetraAttentionWhyNext`, Ops AttentionCard, [ops/README.md](../ops/README.md)

## 2026-08-05 - Open in editor is a desk-process launch, not a browser trick

- Decision: `POST /api/open` launches the operator's editor from the desk process. Preference `editorCommand` accepts `auto` (Cursor, then VS Code, then Windows default), `cursor`, `code`, `system`, or a full executable path; default is `auto`. Path must be an existing folder inside a configured root or the Metra home. Caller must be the operator machine (loopback or one of its own addresses) or present `X-Metra-Local-Session`. UI order stays bridge, then `/api/open`, then clipboard (with an `execCommand` fallback for plain-http origins).
- Why: Clipboard-only degrade was the whole feature in a browser, and the async clipboard does not exist on non-secure share URLs, so Open in editor silently did nothing. Same-machine addresses count as local because MagicDNS is the normal desk URL here; a genuinely remote peer still cannot spawn processes.
- See: `scripts/private/OpsOpen.ps1`, `scripts/private/OpsServer.ps1` (`/api/open`), [ops/README.md](../ops/README.md), [SECURITY.md](../SECURITY.md)

## 2026-08-05 - Attention memory (continuity, not work management)

- Decision: Attention memory exists to preserve continuity of observations and operator intentions. It is not a work management system and does not make claims about completion status. Observations (`active` / sticky `dismissed` / `autoClosed`) are separate from operator Holds (temporary parking). Quick scans never close attention; items auto-close only when a full scan covers that kind and confirms absence. Sticky dismiss stays until `evidenceSignature` changes. Confidence (`fresh` / `likelyStale` / `needsRevalidation`) affects ranking so stale ghosts do not own the top slot. `whyNext` is first-class. Hold quietly nudges durable homes (TicketTracker, Decision Registry, OCC, Future Development). Store: `docs/ops-attention.local.json` (gitignored).
- Why: Quick refresh was wiping Next attention because the desk derived a single ephemeral item and skipped git/verify on quick snapshots - Metra forgot what it meant to say. Treating dismiss as "done" would claim knowledge Metra does not have.
- See: `scripts/private/AttentionMemory.ps1`, `ConvertTo-MetraDeskPayload`, Ops Next attention panel, [ops/README.md](../ops/README.md)

## 2026-08-05 - Tailscale MagicDNS share URL

- Decision: When `bindTailscale` is on, Ops listens on loopback, Tailscale IPv4, and MagicDNS (from `tailscale status --json` Self.DNSName) when available. ShareUrl / BrowserUrl prefer MagicDNS; the IP remains a listener. Local `http://metra/` stays attached when hosts + URL ACL are already present.
- Why: IP-only share URLs are hard to remember; a reserved MagicDNS URL ACL without a matching HttpListener prefix returns 503.
- See: `scripts/private/OpsBinding.ps1` (`Get-MetraOpsTailscaleDnsName`, `Get-MetraOpsTailscaleBinding`), [SECURITY.md](../SECURITY.md)

## 2026-08-04 - Secure Ops Slice 7/8: webview bridge + Tailscale reach

- Decision: Ship the VS Code-family Metra Ops webview bridge under `integrations/vscode-metra-ops` with page contract `requestProposalApply` / `askInChat` / `openWorkspacePath` / `copyText` and host replies `surfaceReady` / `applyStatus`. Tab titles use `{Project}: subject`. Browser without bridge keeps HTTP + clipboard degrade. Opt-in `bindTailscale` prefs add dual loopback+Tailscale HttpListener prefixes for reach (view/ask). Host issues `%LOCALAPPDATA%\Metra\ops-local-session.token`; non-loopback propose/`request-apply` require `X-Metra-Local-Session`. Loopback-only `GET /api/local-session` may mint/read the token for the operator machine. Tray Apply once still gates every disk write. Tailscale Serve is the supported HTTPS front when bindTailscale is on (orchestrated at Ops start); Metra still runs without Serve on loopback. Funnel stays out of product scope.
- Why: Slice 6 Resolve UI needed an IDE surface and a real non-loopback gate before operators test phone/coworker share; stubbed session accept without Host issue was incomplete. Later Route something made HTTPS part of phone clipboard reach.
- See: `ops/src/bridge.ts`, `integrations/vscode-metra-ops/`, `scripts/private/OpsSession.ps1`, `scripts/private/OpsBinding.ps1`, `scripts/private/OpsServe.ps1`, [SECURITY.md](../SECURITY.md), [Integrations.md](Integrations.md)

## 2026-08-04 - Routing precedence; no product-name trigger laundry list

- Decision: New-stop routing precedence is: existing TicketTracker thread (lane continuity) > 6-8 digit ticket id > ticket/helpdesk vocabulary > TicketTracker solutions-index keywords > technical project score > Metra home (ask once). Do not accumulate product, app, or vendor names as TicketTracker `projects.json` triggers - registry triggers stay workflow vocabulary (`ticket`, `isupport`, `helpdesk`, `incident`, …). Recurring product keywords live in TicketTracker `solutions/README.md` and reinforce CLI routing when present. Remove Datamart from TicketTracker `related` (reference source, not an operational next hop). Always-on `project-routing.mdc` owns keep-established-primary immediately after primary selection. Portfolio policy; refuse OCC promote.
- Why: Agents still loaded handoff-eager always-on routing while symptom-only and bare ticket-id queries fell to Metra score 0; stuffing every helpdesk product into registry triggers does not scale and fights technical-project scoring; Datamart on Related invited the wrong investigate hop.
- See: `.cursor/rules/project-routing.mdc`, `scripts/private/Routing.ps1` (`Get-MetraRoutingAmbiguity`), TicketTracker `solutions/README.md`, `docs/Routing-Scenarios.md`, `projects.json` (TicketTracker related)

## 2026-08-04 - In-thread sticky primary; ticket-ops vs investigate

- Decision: Once a chat establishes a primary stop (especially TicketTracker via ticket id or helpdesk triggers), keep that primary for subsequent turns unless the operator names another project, asks for a technical deep dive, or the current ask clearly requires a different stop. Do not re-route from symptom words alone on every turn. For ticket threads, classify each follow-up: **ticket-ops** (status, email draft, `post` / `recommend` / `resolve`, Waiting on Customer, correspondence) stay in TicketTracker; **technical investigate** (explicit dig into a system, or evidence that ticket-ops cannot finish) may open one technical project, then return outcomes to TicketTracker for durable writes. Warehouse / Datamart-style surfaces are read/reference for agents - not update destinations for ticket "fix/change" work. This is portfolio routing policy (Decisions + base persona + TicketTracker AGENTS); refuse OCC promote for it.
- Why: Ticket chats that opened correctly on TicketTracker were re-interpreted mid-thread as product/domain work (RoutingTerms like thrive matching nothing, brief forcing early technical handoff, Datamart treated as a write stop). Operators treat a ticket-opened chat as a ticket thread; per-utterance handoff-eager routing burned time and skipped `post`/`resolve`.
- See: `.cursor/rules/metra-persona.mdc`, `AGENTS.md` (Route first), `docs/Context-Routing.md`, TicketTracker `AGENTS.md`, Datamart `AGENTS.md`

## 2026-08-04 - Secure Ops Propose-Confirm-Apply (Host owns disk writes)

- Decision: Metra Ops may become the desk; the tray Host remains the hands. The browser never writes the workspace. Metra Ops proposes and previews. The tray Host is the only process that applies. Web-originated change requests are untrusted proposal objects until the user-session Host validates, confirms, applies, and audits them. Slice 3 owns what is legal; Slice 4 owns preview; Slice 5 owns truth. Proposals are a security boundary: after `contentHash` is calculated the canonical body is immutable (edits require a new id/hash/nonce); `schemaVersion` is required and the Host rejects unknown versions instead of partial-apply; status is `draft` -> `pendingApply` -> terminal `applied` | `rejected` | `expired`. Ops HTTP exposes create/preview/`request-apply`/status only - never an endpoint named `/apply`. Native Host confirmation uses Apply once (not browser-only confirm). Replace requires matching `previousHash`; no replace-if-changed. Reach and authority stay split: non-loopback may view/ask; proposal create and request-apply require a local Host session marker unless a later product decision loosens that. Large-scale refactors stay editor-first. Editor handoff is the first-class escape for open-ended or out-of-policy work.
- Why: HTML Ops is replacing canvas as the regular-user desk. Without a write boundary locked before the UI is beloved, request-apply drifts into remote Invoke-Expression with buttons. Dual-pass validation and Host-only apply keep teacher/coworker reach useful without granting anonymous disk authority.
- See: [SECURITY.md](../SECURITY.md), Cursor plan `attention_resolve_actions_bcb3e7aa`, [Future-Development.local.md](Future-Development.local.md) (Secure Ops scar)

## 2026-08-04 - Self-doc refresh is a required step after route changes

- Decision: `.\metra.ps1 selfdoc` regenerates standing route examples from the merged registry into the self-documentation canvas embed, `docs/Overview.md` markers, `docs/selfdoc-routes.json`, and the tracked canvas template. `Export-MetraSnapshot` / `.\metra.ps1 snapshot` also invokes selfdoc. After registry trigger, purpose, or project-row changes that should appear in the explain surface, operators and agents must run `selfdoc` (or snapshot) - do not hand-edit the generated route table or `SELFDOC_ROUTES` embed.
- Why: Leadership asked for visual self-docs; those docs go stale the first time a route changes unless refresh is an explicit, repeatable product operation.
- See: `scripts/private/SelfDocumentation.ps1`, `docs/Context-Routing.md`, `.\metra.ps1 selfdoc`

## 2026-08-04 - Self-documentation is a Cursor canvas; Overview.md is the prose twin

- Decision: Rename `docs/Demo.md` to `docs/Overview.md`. The visual primary for Metra self-documentation is the Cursor canvas `metra-self-documentation.canvas.tsx` (tracked template: `integrations/cursor/metra-self-documentation.canvas.tsx.template`). Pictures-first: route diagram, thin stack, two channels. Overview.md remains the sendable email/print twin. Ops Ask and the Ops board canvas stay separate UI leaders; this canvas is the explain surface, not the ops desk.
- Why: Leadership feedback (Thomas) - technical questions are answered faster with pictures than more prose. Demo naming no longer matched a leave-behind or a self-doc site.
- See: Cursor projects canvases path, `docs/Overview.md`, `integrations/cursor/metra-self-documentation.canvas.tsx.template`
- Supersedes: 2026-08-04 "Demo.md is an audience leave-behind" (role moves to Overview + canvas)

## 2026-08-04 - Demo.md is an audience leave-behind, not talk notes

- Decision: `docs/Demo.md` is a standalone brief for colleagues and leadership after a walkthrough (or without one). Lead with middle path, what Metra is, vision/institutional fit (including growth paths and light campus posture contrast), how it works, and Q&A. No speaker stage directions. Live demo beats stay optional in chat or a separate presenter cut if needed later.
- Why: The CIO/audience need something sendable. Talk-note framing ("say this slowly," "if faces look blank") does not travel well as email or handout.
- See: `docs/Demo.md`, README / Brand / Customizing / Integrations pointers
- Supersedes in part: 2026-08-03 "coworker talk is pitch-first" (story spine remains; document role is leave-behind)
- **Superseded by:** 2026-08-04 Self-documentation canvas + Overview.md

## 2026-08-03 - Ops desk prefers http://metra/ when port 80 is free

- Decision: Prefer a port-free Ops URL **`http://metra/`** when TCP port 80 is free and hosts + HTTP.sys URL ACL can be set for the current user. Persist the choice in `docs/ops-preferences.local.json` (`opsPort`, `browserHost`, `preferFriendlyUrl`). When port 80 is busy or elevation fails, fall back to **`http://127.0.0.1:7380/`** (safe default for every install). Interactive `.\metra.ps1 setup` asks once when port 80 is free; non-interactive setup auto-prefers friendly when free. Explicit CLI `-Port` still wins. HttpListener registers both `http://127.0.0.1:80/` and `http://metra:80/` so probes and the hostname URL work. Ask sidecar stays on 7381.
- Why: Operators should not memorize 7380. Port 80 cannot be a hard product default because coworkers may already run IIS/Docker there - detect and ask/fallback instead.
- See: `scripts/private/OpsBinding.ps1`, `Initialize-MetraOpsDeskBinding`, `Invoke-MetraSetup`, `docs/ops-preferences.local.json`

## 2026-08-03 - Ops supervision adopts, retries, and reports

- Decision: The tray supervisor keeps the desk up under three rules. **Adopt:** any live desk on the supervised port is supervised, including one started by console `ops` or restarted outside the tray - the host no longer declines to watch a child it did not spawn. **Retry with backoff, never surrender:** a dead desk is restarted on a widening interval (5s, 15s, 60s, then 300s) until it answers or the operator chooses **Stop desk**; the previous one-restart budget is gone. **Report:** `ops-host-state.json` carries a heartbeat (`updatedAt`, `childPid`, `consecutiveFailures`, `hostPid`) written on change or every 30 seconds, and supervision events append to `%LOCALAPPDATA%\Metra\ops-host.log` (rotates at 256 KB). Process liveness stays the health signal, so a desk busy with a long Ask is never restarted. Reboot coverage is the per-user Startup shortcut ("Start with Windows"); a Scheduled Task that also revives a dead **tray host** mid-session stays deferred.
- Why: The board went offline for hours while the tray sat healthy. Two latches caused it: the tick returned early whenever the child was not host-owned, and a single failed restart disabled supervision permanently. Neither wrote state or a log, so the state file still read "running" and there was no evidence of when the desk died.
- See: `scripts/private/OpsHost.ps1` (tray tick, `Get-MetraOpsHostRestartDelaySeconds`, `Update-MetraOpsHostHeartbeat`, `Write-MetraOpsHostLog`), `tests/Metra.Tests.ps1` (Metra Ops host)

## 2026-08-03 - Canvas board stays alongside the HTML Ops desk

- Decision: Keep the Cursor canvas Ops board as a supported surface for now. The HTML Ops desk remains the primary board, and the canvas stays a read-mostly in-editor view refreshed by `snapshot`. Retiring the canvas is not scheduled; revisit only if maintaining both surfaces starts costing more than the in-editor view returns.
- Why: The canvas is useful when the desk is not open or the operator is already in Cursor, and it survives desk restarts. Removing it now would trade a working surface for a small maintenance saving.
- See: `scripts/private/Snapshot.ps1` (canvas embed), `docs/canvas-snapshot.json`, `.\metra.ps1 snapshot`

## 2026-08-03 - Durable-write home classification (before propose)

- Decision: When Metra would recommend a durable write (remember / promote / playbook / note), **classify the home first**, then propose only that home. Do not default to OCC. Classification:

  | Kind of durable fact | Home | Not |
  |---|---|---|
  | Soft collaboration rhythm across the portfolio | OCC / `profile` | Project playbooks |
  | Portfolio-wide product / routing / persona policy | `docs/Decisions.md` or base `metra-persona.mdc` | OCC |
  | Project-local how-to / triage / runbook | That project's `AGENTS.md` (or README) | OCC, Decision Registry |
  | Recurring ticket pattern with reusable write-up | TicketTracker `solutions/` (+ index) | OCC |
  | Operator-private why-we-chose scar for a stop | Decision Registry | OCC, AGENTS.md dump |
  | Ticket evidence / session outcome | TicketTracker `note` / `post` / `recommend` | OCC |

  OCC refuse list expands beyond portfolio-wide product rules: also **refuse** OCC promote for project-local playbooks, module runbooks, single-project triage order, and TicketTracker solution write-ups. Name the correct home and ask whether to write there instead. When proposing a durable write in chat, say the home explicitly (e.g. "Colleague AGENTS.md, not OCC").
- Why: A stuck-Colleague playbook was almost proposed as an OCC soft guideline. OCC is always-on and capped; stuffing per-module runbooks there blurs homes and bloats the learned overlay. The Portfolio Operations Principles map already named the homes; agents still needed an explicit classify-before-propose rule.
- See: `.cursor/rules/metra-persona.mdc` (Operator Communication Contract), `AGENTS.md`, [Customizing-Metra.md](Customizing-Metra.md), Portfolio Operations Principles in this file

## 2026-08-01 - Ops host is a desktop app before a service

- Decision: Metra behaves like a **desktop application** before it behaves like a **Windows Service**. The normal front door is a **user-session tray supervisor** (`.\metra.ps1 host` / Start Menu Metra Ops) that keeps the HTML Ops desk alive without a console window. Ownership chain is mandatory: **Host -> Ops -> Ask** - the tray starts and stops only the Ops child; Ops alone starts and stops the Ask engine. Second Start Menu click opens the browser when the desk is already up (no second instance, no bind conflict). Optional "Start with Windows" lives in the tray menu only - no installer checkbox or SCM registration in this bite. Console `.\metra.ps1 ops` remains the operator/debug escape hatch. A true Windows Service, Tailscale/non-loopback bind, and installer-bundled Node stay deferred until installer packaging, AI engines, and user-state ownership are fully settled. Host debug state lives in `%LOCALAPPDATA%\Metra\ops-host-state.json`.
- Why: Closing the browser (or the PowerShell console) previously killed Metra and made it feel like a script. User-session hosting keeps user secrets, user state, and tray identity aligned; jumping to SCM early forces account and secret questions before Ask packaging is ready.
- See: `scripts/private/OpsHost.ps1`, `scripts/bootstrap/Start-MetraOpsHost.ps1`, `Metra-Ops.cmd`, `.\metra.ps1 host`, [Future-Development.local.md](Future-Development.local.md)

## 2026-08-01 - Ask engine (Metra gets a voice)

- Decision: Architectural center of gravity for the regular-user arc moves from routing polish to **user experience**. HTML Ops established the desk ("where do I click?"); Ask establishes the **voice** ("what do I do?"). Target flow: Open Metra -> Ask Metra -> route correctly -> answer -> optional open Cursor to build. **Cursor is one engine under Engine**, not the product - users say "I asked Metra," not "I opened Cursor." Ask is AI-by-default when a selected engine is available, behind a replaceable contract (`GET /health`, `POST /v1/complete` on loopback). **Route-first is mandatory** (Ask never bypasses routing; differentiator is start-from-the-right-place then answer). **HTML Ops is answer-only**; Cursor IDE is for builds - no half-editing from the browser. Capability discovery distinguishes not-runnable / available / selected via `ask.enabled` + `ask.engine` in config. Degraded Ask is brutally honest (no greeting regex theater, no routing preview dressed as chat). v1 Cursor engine is a Node sidecar (`engines/cursor`, `@cursor/sdk` local) auto-started with `.\metra.ps1 ops` when selected and Node + API key exist - **operator-tier temporary**. Shipping Node + sidecar in the installer for non-technical users is explicit follow-on debt, not forgotten. Ollama/local model is a later engine behind the same contract. Classify stays routing-only. Inside-Cursor Plan-mode build handoff is deferred.
- Why: Ask shell without a model made the chat UI imply a conversation partner it could not be. Replaceable engines, route-first, and answer-only boundaries age better than wrapping Metra around Cursor.
- See: `engines/cursor/`, `scripts/private/AskEngine.ps1`, `scripts/private/Snapshot.ps1`, `scripts/private/OpsServer.ps1`, `metra.config.example.json`, `.\metra.ps1 ops`, [Future-Development.local.md](Future-Development.local.md)

## 2026-08-01 - Ops desk stops on Ctrl+C, not on the host

- Decision: The Ops accept loop must never register a scriptblock `ConsoleCancelEventHandler`. Interrupt handling relies on PowerShell's own Ctrl+C: poll `BeginGetContext` with timed waits so a pipeline stop lands between statements, then release the listener in `finally`. A desk records its process id under `%LOCALAPPDATA%\Metra\ops-<port>.pid`; `.\metra.ps1 ops -Stop [-Port n]` frees a port, falling back to the HTTP.sys request-queue owner when the pid file is gone. Launching `ops` against a port that already answers opens the running desk instead of throwing.
- Why: `[System.ConsoleCancelEventHandler] { ... }` is invoked on the console control thread, where the scriptblock cannot run while the runspace sits in the accept loop; the resulting failure killed the whole terminal and left an orphaned process holding port 7380, which then blocked every restart with a bind conflict. Related: `Import-PowerShellDataFile` does not reliably resolve from module scope under Windows PowerShell, so `/api/meta` reads the module version instead; the bootstrap must splat a hashtable, since array splatting binds positionally and silently dropped `-Port` and every switch.
- See: `scripts/private/OpsServer.ps1`, `scripts/bootstrap/Start-MetraOps.ps1`, `.\metra.ps1 ops -Stop`

## 2026-08-01 - Metra is home destination

- Decision: Treat **Metra** (this orchestration checkout) as a real **destination project** and the **default / home route** until another project wins confidently. Shared registry entry `Metra` with `routing.homeDestination` / `defaultEntry` = `Metra`. Sibling folder scans still skip `_meta` / `_metra` / `Metra` folder names, but `Get-MetraProjects` injects Name=`Metra` mapped to `Get-MetraRoot()`. Routing / desk Ask / Classify stay on Metra when no match or only weak incidental scores (`score < 2`). Ticket/helpdesk work still starts in TicketTracker when ticket triggers score. Metra-Bing-Review remains a local review checkout and must not steal bare "metra" asks.
- Why: HTML Ops "Hello Metra" was routing to Metra-Bing-Review because Metra itself was not a destination. Users need a place to stand on the product until work clearly belongs elsewhere.
- See: `projects.json`, `scripts/private/Projects.ps1`, `scripts/private/Routing.ps1`, `scripts/private/Snapshot.ps1`, `.\metra.ps1 ops`, `.\metra.ps1 routing -Query`

## 2026-08-01 - HTML Ops primary desk (home screen)

- Decision: For non-technical users, the primary Metra surface is the **installer + HTML Ops desk**. **Cursor (including the Ops canvas) is an advanced IDE interface**, not the default. HTML Ops defaults to **Route-first General** (Ask, one next-attention item, Classify/Handoff). Additional tabs (Projects, Recent, Health) are **opt-in via Settings (Advanced desk)**. Stack: **Vite + React face** under `ops/` with a **PowerShell localhost API** brain; ship prebuilt `ops/dist` so end users need **no Node** for the desk face. **One brain, many faces** - a shared desk/snapshot payload feeds the HTML desk and the Cursor canvas (do not invent separate Canvas/Desk/Installer payload builders). Health on the desk is **visibility only**: missing AGENTS, git not checked / unavailable, snapshot stale - no scores, grades, or percent. Ask is the voice path: when an Ask engine is selected and available it answers after routing; when not, Ask degrades honestly (see Ask engine decision). Durable portfolio state stays CLI/chat - the desk is a retrieval surface.
- Why: Deven-class use showed the pain is needing a place to stand after install, not more Foundation routing/coverage polish. People tolerate weak features; they do not tolerate not knowing where to click. Operator-shaped multi-tab homes push non-technical users away. Layers for prioritization:

```text
Foundation   Done enough   (routing, ctx, decisions, coverage, topology)
Product      Shipped       (installer, website, home folder, setup, upgrades)
Experience   Primary focus (HTML desk, Ask, project activation, local AI)
```

- See: `ops/`, `scripts/private/OpsServer.ps1`, `.\metra.ps1 ops`, `scripts/private/Snapshot.ps1`, [Brand.md](Brand.md), `docs/Future-Development.local.md`

## 2026-08-01 - Plain-language landing (GitHub Pages)

- Decision: Ship a **separate** plain-language landing under `site/` on GitHub Pages (`https://jaxnoth.github.io/Metra/`), not by rewriting the operator README. Content: problem/value, Windows installer CTA, Documents home folder, one short PowerShell glossary - no CLI/registry dump. README gets a short **Who this page is for** pointer plus Get Metra link. Treat the Pages URL as a portable stop; a fuller marketing host may replace it later without changing product architecture.
- Why: Non-coder review found the GitHub README overwhelming; installer alone does not explain what Metra is. A thin linked site keeps audiences split while staying in-repo for now.
- See: `site/index.html`, `site/styles.css`, `README.md`, [Brand.md](Brand.md)

## 2026-08-01 - Product installer with full upgrades (architecture)

- Decision: Treat the Windows installer as **product distribution architecture**, not optional polish. Three channels stay separate: developers use `git clone`; technical consumers may use ZIP + `Metra-Setup.cmd` / `unblock`; non-technical consumers use `MetraSetup.exe`. **Installer owns product files** (stable AppId `B7C8D9E0-1A2B-4C5D-8E9F-0A1B2C3D4E5F`, `UsePreviousAppDir`, version from `scripts/Metra.psd1` ModuleVersion). **User owns state** (config, `projects.local.json`, Decision Registry, OCC, `*.local.mdc`, generated packs - never staged in the payload). **`setup` reconciles capabilities** - wizard task "Run Metra setup now" is checked by default on first install and upgrade and launches `Metra-Setup.cmd` (Start Menu the same). Optional Persona Add-ons remain `import-profile` / `setup -Profile` - no Inno feature checkboxes. Process-scoped Bypass only; never mutate machine ExecutionPolicy. No v1 auto-adopt of an existing git/ZIP tree. Unsigned SmartScreen: document More info -> Run anyway; signing deferred.
- Why: Non-technical users must not learn Git, ZIP, mark-of-the-web, or execution policy. Upgrades must replace product bits, preserve user state, and activate new features via setup so "I installed the new version" matches expectation. Keeping packs out of Inno prevents a second configuration system.
- See: `packaging/Build-MetraInstaller.ps1`, `packaging/inno/Metra.iss`, `packaging/README.md`, `Metra-Setup.cmd`, `README.md` (Windows installer)

## 2026-08-01 - ZIP mark-of-the-web unblock path (interim)

- Decision: Ship a lean no-Git ZIP recovery path: root `Metra-Setup.cmd` launches `scripts/bootstrap/Start-MetraSetup.ps1` under **process-scoped** `-ExecutionPolicy Bypass` (never mutates machine policy), clears Zone.Identifier via `Unblock-MetraCheckout`, then runs `setup`. CLI `.\metra.ps1 unblock` is the recovery/diagnostics anchor; return shape is `BlockedDetected` / `FilesUnblocked` / `AlreadyClean` / `Failed`. `verify` WARNs (does not FAIL) when checkout scripts still carry mark-of-the-web. Prefer unblocking the `.zip` before extract when possible. Script signing stays out of scope. An actual installer remains the durable non-technical distribution channel; ZIP is a correct fallback, not the primary non-coder story.
- Why: Extracted GitHub ZIPs preserve mark-of-the-web, so `RemoteSigned` blocks unsigned `metra.ps1` before setup can run. Detection inside `metra.ps1` cannot be the primary rescue; a `.cmd` bootstrap can. Unblock tooling also helps OneDrive / email / copied archives after day one.
- See: `Metra-Setup.cmd`, `scripts/bootstrap/Start-MetraSetup.ps1`, `scripts/private/Install.ps1`, `.\metra.ps1 unblock`, `.\metra.ps1 verify`, `README.md` (No Git? Download the ZIP)

## 2026-08-01 - Decisions review (knowledge decay visibility)

- Decision: Ship **`.\metra.ps1 decisions review`** as ledger-hygiene **visibility only**. Canonical helper `Get-MetraDecisionRegistryReview` reports three work classes: stale candidates (same cutoff as `decisions gc` via shared `Split-MetraDecisionRegistryCandidatesByStale`), superseded confirmed inventory, and MissingWhy (blank why on candidates or confirmed; unique by id). Gap lists alphabetical/stable, capped at 12; counts full. CLI writer derives command hints from facts; snapshot/Stewardship "Ledger hygiene" strip carries facts only (no SuggestedCommands, no score, no age averages). Review never mutates; operator still runs `gc` / `promote` / `forget`.
- Why: Stewardship already showed recent decisions and candidates without a preview of what `gc` would remove, or of missing-why debt and superseded inventory. Operators need the same cutoff as gc so review and mutate cannot disagree.
- See: `scripts/private/DecisionRegistry.ps1`, `.\metra.ps1 decisions review`, `integrations/cursor/metra-ops-board.canvas.tsx.template`, `docs/Context-Routing.md`

## 2026-08-01 - Knowledge coverage visibility (not a score)

- Decision: Ship knowledge coverage as **visibility only** via canonical helper `Get-MetraKnowledgeCoverage`. One present registry-on-disk population feeds every with/missing/uncovered dimension. Dimensions: AGENTS on disk, non-empty `serves`, and at least one **active confirmed** Decision Registry row (not candidates, not superseded). `Uncovered` means missing all three. Surfaces: `.\metra.ps1 coverage`, Ops Stewardship Gaps strip, and snapshot `coverage` (keep existing aggregate counts; add capped gap lists). Gap name lists are alphabetical, deduped, capped at 12; counts stay full. No percent, grade, or health score. Out of scope: decisions review/decay, cap-100, auto-filling serves/AGENTS.
- Why: Stewardship already showed aggregate coverage counts without listing AGENTS gaps or uncovered projects, and there was no CLI without the canvas. Operators need the gap names to tend knowledge without inventing a second scoring system.
- See: `scripts/private/Snapshot.ps1` (`Get-MetraKnowledgeCoverage`, `Write-MetraKnowledgeCoverage`), `.\metra.ps1 coverage`, `integrations/cursor/metra-ops-board.canvas.tsx.template`, `docs/Context-Routing.md`

## 2026-08-01 - Project story + related in ctx

- Decision: Surface registry **`related`** (reuse the existing field; do not add `relatedProjects`) and a bounded **project story** in `.\metra.ps1 ctx`. Story is a composition of existing metadata (`purpose`, `triggers`, `serves`, `related`, optional `whenPresent`) - no new registry story field and no generated prose. Canonical helper `Get-MetraRelatedProjects` preserves registry order, dedupes, drops unknowns, keeps same-root only, caps at 6, returns `{ Name, Present }`. Context pack and `routing -Name` / `-Query` primary consume that helper only. Related remains **topology, not permission** to multi-repo search.
- Why: Agents need portfolio topology at the stop pick without inventing memory soup or auto-opening neighbors. Registry stays authoritative; story regenerates deterministically.
- See: `scripts/private/Routing.ps1` (`Get-MetraRelatedProjects`), `scripts/private/Context.ps1`, `docs/Context-Routing.md`, `.\metra.ps1 ctx -Query "..."`

## 2026-08-01 - Public GitHub vs non-coder audience (deferred)

- Decision: Treat the **GitHub README / repo page as an operator and coder onboarding surface**, not the primary explainer for non-coders. Do not dilute the PowerShell-first README into plain-language marketing that fails both audiences. A **separate website** (or equivalent plain-language landing) is the planned home for non-coder understanding; that work is deferred, not in the current public-repo ship.
- Why: Non-coder review of the live GitHub page - a teacher with some technical skills found the language not meaningful across the whole page and overwhelming. Feedback concluded a separate website is probably essential for that audience. Concrete vocabulary gaps that needed live explanation: what **PowerShell** is, and what it means to **create a base folder** (checkout / `_metra` / project root). Those terms must not be assumed on the non-coder surface. When creating a home folder, the natural choice was **Documents** (not a developer `C:\Projects`-style root) - treat that as a valid personal-root default in non-coder guidance. **Git was not installed** - `git clone` is a hard stop for that audience; the non-coder path must offer get-Metra without installing Git. The ZIP workaround then hit a second wall: files extracted from a downloaded ZIP carry the Windows mark-of-the-web, so `RemoteSigned` refuses to run unsigned `metra.ps1` even after the documented `Set-ExecutionPolicy` step. Any no-Git path must cover unblocking (ZIP Properties -> Unblock before extract, or `Unblock-File`); the README `Set-ExecutionPolicy` line alone is only sufficient for a real `git clone`.
- See: `README.md`, [Brand.md](Brand.md) (public mark / GitHub), plan `github_public_audience_revision` (Cursor plans), operator index `docs/Future-Development.local.md` (Bucket A)
- Future / not in this release:
  1. ~~Separate plain-language website (or landing) for non-coders~~ **done** (`site/` + GitHub Pages; may move host later)
  2. Keep GitHub README operator/coder-dense; ~~Who-this-is-for pointer~~ **done**; ZIP unblock and installer README **done**
  3. Re-test the non-coder surface with a similar reviewer profile before calling it done
  - Out of scope for that revision: rewriting Metra itself into a non-technical product; family/classroom ticketing (TicketTracker); persona add-ons as a substitute for plain docs; requiring Git for first-run non-coder setup; treating manual ZIP + Unblock as the final non-coder deploy story

## 2026-07-31 - Metra Ops as one interchange (retrieval surface)

- Decision: Keep **one** Metra Ops canvas with three tabs organized around operator questions: **Route** (default - classify request and hand off Where/What/Why/For whom/Next), **Portfolio** (what needs attention), **Stewardship** (what knowledge needs tending, including a compact Portfolio Operating Model card). The board **retrieves from existing homes rather than becoming a new home** - routing registry, Decision Registry, OCC, audit/verify stay canonical; the canvas is read-only for durable portfolio state. Route scoring in the board is a labeled preview of PowerShell routing; authoritative Why Here remains `routing -Query` / `ctx -Query`. Quick snapshots must mark git/verify as not checked rather than healthy zeroes.
- Why: The first Ops board reported on Metra as a health dashboard. The operating model now needs a UI that *is* Metra - route before execute, illuminate homes, tend knowledge - without inventing a competing editor or second scoring system.
- See: `integrations/cursor/metra-ops-board.canvas.tsx.template`, `scripts/private/Snapshot.ps1`, `docs/Context-Routing.md`, `docs/Brand.md`

## 2026-07-31 - Route-mark identity (paths and hubs)

- Decision: Keep the public Metra mark as a teal three-node route with an open labeled center interchange ([`docs/assets/metra-mark.svg`](assets/metra-mark.svg)). Terminal nodes stay the same Signal Teal family as the line - no blue/amber/multicolor endpoints. Brand story stays short: Metra connects endpoints; the open center is classification before work moves on. Future operator-facing chrome prefers paths, nodes, routes, connections, hubs - not brains, robots, assistants, or mascots. Documented in [Brand.md](Brand.md) Motif.
- Why: The geometry already matches portfolio operations (route → classify → continue). Extra endpoint colors and AI cliches dilute a mark that is unusually aligned with the product without needing a post-hoc story.
- See: `docs/assets/metra-mark.svg`, `docs/Brand.md`, README header image

## 2026-07-31 - For whom? (project serves)

- Decision: Ship **For whom?** as optional project-registry `serves` (`string[]`), same shape as `triggers` / `capabilities`. Audience of the work (roles, teams, consumer systems), never people memory - portfolio memory, not CRM. Surfaces: `routing -Name` / `routing -Query` print a **For whom?** question block when non-empty (before Why Here); `ctx` includes `serves` in JSON and markdown (`- serves:` per project; `## For whom?` for query primary). Full `routing` table stays quiet. Seed shared stubs TicketTracker and Solarwinds. Why Here stays Decision Registry; serves stays project registry (do not stuff audiences into the Decision Registry). v1 is plain strings only - no `{ name, kind }` objects.
- Guardrail: Metra may describe audiences served by work. Metra does not maintain memory of individuals, requesters, owners, approvers, performance history, or interpersonal relationships. Ticket requester facts stay in TicketTracker evidence when needed.
- Why: Completes the homes map without inventing people-profiling Who. Stable role/team audiences teach the portfolio at route time.
- See: `projects.json` (`serves`), `Write-MetraForWhom`, `.\metra.ps1 routing -Name Solarwinds`, `docs/Context-Routing.md`
- Future: structured `{ name, kind }` only if string[] proves too weak; Decision Registry `for` remains out of scope until needed

## 2026-07-31 - Portfolio Operations Principles

- Decision: Adopt an explicit **portfolio operations** operating model for Metra. Lead rule: **every portfolio fact should have a home.** Homes map (operator cheat sheet; does not replace the marketed product triangle of routing + context + communication):

  | Question | Home |
  |---|---|
  | Where? | Routing registry / `.\metra.ps1 routing` |
  | What? | Context / `ctx`, project `AGENTS.md` |
  | Why? (operational scars) | Decision Registry + Why Here |
  | Why? (product policy) | `docs/Decisions.md` |
  | How? (collaboration rhythm) | OCC / `profile` + communication model / professional sink |
  | Health? | Ops board / `audit` / `verify` / status |
  | For whom? | Project registry `serves` / `routing` / `ctx` (not people profiling) |

  Operating principles: (1) every portfolio fact has a home; (2) route before execute; (3) context is retrieved, not dumped; (4) decisions are preserved with rationale (ledger why + confidence + evidence; never invent operational why); (5) communication follows the same operating model as the tooling. Health is first-class for ops but is not a fourth marketing triangle leg. Metra overlaps portfolio management, knowledge management, and configuration-management ideas; it is an operating model for developers and agents, not a single Wikipedia discipline. Boundaries: product policy -> Decisions.md; operational scars -> Decision Registry; collaboration rhythm -> OCC; project-local guidance -> that project's `AGENTS.md`.
- Why: Portfolio chaos is usually information with no obvious home. Naming the model keeps future features (relationships, Ops board wisdom) from inventing parallel homes or dumping wiki-scale knowledge into prompts.
- See: `README.md` (Portfolio operations homes), Why Here / For whom / Decision Registry / OCC / product-triangle entries in this file
- Future: see Why Here entry (relatedProjects, Ops board wisdom, and related items) - do not duplicate that list here

## 2026-07-31 - Why Here? routing explanations

- Decision: Ship **Why Here?** as ledger-backed routing explanations attached when a primary stop is named or query-picked. Private helpers `Get-MetraWhyHere` / `Write-MetraWhyHere` / `Write-MetraWhyNot`; `Search-MetraDecisionRegistry -Project` scopes hits. Surfaces: `.\metra.ps1 routing -Name` (Why Here per present named project), `.\metra.ps1 routing -Query` (primary + Why Here; close runner-up + Why not), `ctx -Query` (markdown `## Why here?` / optional `## Why not?`; JSON `whyHereFor`, `relatedDecisions`, optional `whyNotFor` / `runnerUpDecisions`). Full `routing` table without Name/Query stays an index with no Why Here dump. Confidence shown only when not `high`. Ambiguity when score gap ≤ 1 or runner-up ≥ 50% of primary (primary ≥ 2). Persona may cite ledger Why Here / Why not; never invent operational why. No always-on decisions rule.
- Why: Portfolio knowledge should appear as Why? at the moment of the stop pick, not as a separate hunt or model-generated lore.
- See: `.\metra.ps1 routing -Name TicketTracker`, `.\metra.ps1 routing -Query 'gateway msal'`, `scripts/private/DecisionRegistry.ps1`, `scripts/private/Routing.ps1`
- Future / not in this release:
  1. ~~Why Here?~~ **Done** (this entry)
  2. ~~Ops board Recent Decisions / Portfolio Wisdom~~ **Done** - Stewardship tab on Metra Ops interchange (bounded strip; board remains a retrieval surface)
  3. ~~Knowledge coverage visibility (not a score)~~ **Done** - see Knowledge coverage visibility entry
  4. ~~Project story + relatedProjects in ctx~~ **Done** - see Project story + related in ctx entry
  5. ~~decisions review (knowledge decay)~~ **Done** - see Decisions review entry
  6. Cap headroom toward 100 if retrieval stays useful
  7. ~~**For whom?**~~ **Done** - see For whom? (project serves) entry
  - Deprioritized: more persona add-ons; more Ops board health metrics
  - Operator parking-lot index (gitignored): `docs/Future-Development.local.md`; Cursor plan `metra_future_development_buckets`

## 2026-07-31 - Decision Registry (Operational Why Memory)

- Decision: Ship an operator-private **Decision Registry** for operational why-we-chose memory, separate from `docs/Decisions.md` (product policy) and the Operator Communication Contract (collaboration rhythm). Ledger is gitignored `docs/decision-registry.json` (`candidates` + `confirmed`). Flow: note/harvest -> promote; never auto-promote. Required on promote: non-empty `why`, `confidence` (`high`|`medium`|`low`), and at least one `evidence` item. Also store `source` and `origin` (`operator`|`backfill`|`harvest`). Cap 50 active confirmed. Retrieved only via `.\metra.ps1 decisions search|get` and bounded `ctx -Query` top 3 `relatedDecisions` - no always-on `.mdc`. CLI also includes `harvest` (candidates only from project `AGENTS.md`) and `seed` (curated local backfill). Travels with `export-profile` / `import-profile`. Boundary test: would every Metra clone benefit? If yes, use Decisions.md instead.
- Why: Institutional operational scars had no home that was neither routing, personality, nor product docs. Explicit promote plus retrieval-only load keeps trust and avoids memory soup in every prompt.
- See: `.\metra.ps1 decisions`, `docs/decision-registry.example.json`, `scripts/private/DecisionRegistry.ps1`
- Future: see Why Here entry (item 1 done); remaining relationship-surfacing items listed there.

## 2026-07-31 - One generated workspace file

- Decision: `workspace.outputs` ships a single entry: `Metra.code-workspace` inside the Metra checkout (`metraFolderPath: "."`, `projectPathPrefix: "../"`). Do not generate a second copy beside the projects root. The generated file is gitignored; the tracked starter is `Metra.code-workspace.example`. Fresh clones run `.\metra.ps1 setup`, which writes the real workspace locally.
- Why: Two generated copies split Cursor chat history, because Cursor tracks agent transcripts per workspace identity. The second copy also collided with a tracked starter of the same name, so a routine `git` restore silently reverted a generated workspace back to the Metra-only sample and dropped the operator's sibling folders. One generated, gitignored output keeps chat context stable and keeps real project names out of the repo.
- See: `metra.config.example.json`, `profiles/sample/metra.config.json`, `.gitignore`, `Update-MetraWorkspace`

## 2026-07-31 - Operator Communication Contract

- Decision: Ship an **Operator Communication Contract** for the shared operating rhythm between Metra and the operator (how we collaborate - soft working guidelines), not a user profile or hidden memory. Ledger is gitignored `docs/operator-contract.json` (`candidates` + `confirmedGuidelines`). Always-on load is gitignored `.cursor/rules/metra-learned.local.mdc` rendered as a confirmed soft-guideline list plus a fixed Interpretation footer - no auto-generated prose brief. Flow: candidate -> propose -> confirm -> promote; never auto-promote. Hard cap 20 confirmed guidelines. Portfolio-wide corrections (routing, professional sink, root isolation, evidence hierarchy, public product framing, base persona policy) must refuse personal promote and point at Decisions / README / base persona instead. CLI: `.\metra.ps1 profile` (private helpers; no new public module export). Travels with `export-profile` / `import-profile`. Base policy always wins on conflict.
- Why: Communication discipline that never evolves feels fake across sessions and model swaps. Explicit promotion and a deterministic guideline list keep trust inspectable without hidden memory or interpretation drift from synthesized briefs.
- See: `.\metra.ps1 profile`, `docs/operator-contract.example.json`, `.cursor/rules/metra-learned.local.example.mdc`, `docs/Customizing-Metra.md`

## 2026-07-31 - Product triangle: routing + context + communication

- Decision: Market and document Metra as **routing + context + communication discipline** - one operating model, not "CLI plus a persona feature." Prefer the terms **communication model** / **communication discipline** over repeating "communications surface/layer/voice/adapter." Surface the **professional sink** early (chat may have voice; tickets, commits, ADRs, and handoffs do not). Include a clear "Why not just use a coding agent?" differentiation. Refine earlier peer-surface wording: ops still means PowerShell routing/context tooling; the persona is the communication half of the same workflow, framed as capability rather than character.
- Why: External README review - the differentiator is treating communication as part of the operating model. Risk is visitors reading Metra as "just another PowerShell toolkit," not "too much persona."
- See: `README.md`, earlier Decision "Ops and communications are peer product surfaces"

## 2026-07-30 - Operator-private cloud continuity

- Decision: Cross-device Cursor Cloud Agent continuity is **operator-private**, not a shared Metra product surface. Do not teach it in README, Demo, or Integrations. Optional code may stay in-tree but must stay inert without a personal API key; how-to belongs in gitignored `docs/*.local.md`. Shared product still owns the brainstorm-vs-implement persona rule and local `chats`.
- Why: Personal Cursor account wiring and API keys do not travel cleanly with coworker or public clones.
- See: `.gitignore` (`docs/*.local.md`)

## 2026-07-30 - Ops and communications are peer product surfaces

- Decision: Treat Metra as two peer product surfaces: **ops** (`metra.ps1`, module, registries, `ctx`) and **communications** (Metra chat persona, Teaching Mode, professional artifact sink). Do not describe the persona as optional garnish, "not the product," or merely riding on the CLI. Routing and root isolation still win over personality for folder choice. Cursor remains the nicest auto-load adapter; CLI-only operators still get full ops value without persona chrome.
- Why: The persona is how Metra communicates during agent sessions - route-first voice, Teaching Mode delivery, and a clear split between chat tone and durable professional writes. Demoting it undercuts that half of the product while over-correcting against "AI project with scripts bolted on."
- See: `README.md`, `.cursor/rules/metra-persona.mdc`, `docs/Customizing-Metra.md`

## 2026-07-30 - Product framing: PowerShell first

- Decision: Position Metra as a PowerShell product with an AI integration layer, not an AI project with PowerShell tooling. Primary ops surfaces are `metra.ps1`, the importable module (`scripts/Metra.psd1`), registries, and `ctx` packs. Cursor persona auto-load, Teaching Mode, and transcript search are first-class product surfaces for communications (refined in "Ops and communications are peer product surfaces") - not Cursor-only theater.
- Why: A curated CLI and module surface serves CLI operators, PowerShell users, portfolio operators, and AI users. Framing Metra as Cursor-only shrinks the audience and undercuts the module / setup / help work.
- See: `README.md`, `scripts/Metra.psd1`, `docs/Integrations.md`

## 2026-07-30 - Curated exports and Get-Help docs sink

- Decision: Treat the 17 supported `*-Metra*` commands in `scripts/Metra.psm1` (`$script:MetraPublicFunctions`) as the public API. Prefer extending an existing public command or a private helper over adding an 18th export. Comment-based help on those commands is the source of truth for parameters, examples, and outputs (`Get-Help <command> -Full`). README and workflow docs stay example-oriented; do not hand-maintain a parallel API markdown reference. Compatibility exports and `*-Meta*` aliases remain one-release only and are not taught as the product surface.
- Why: Each new export is a stability commitment. Curated surfaces stay discoverable; duplicated docs drift. External review confirmed this boundary after the public/private split.
- See: `scripts/Metra.psm1`, `scripts/Metra.psd1`, `scripts/public/`, `README.md` (PowerShell-native commands)

## 2026-07-30 - Public/private PowerShell module split

- Decision: Keep one Metra module but split implementation by domain under `scripts/private/` and supported commands under `scripts/public/`. `Metra.psm1` is a thin loader with an explicit 17-command public list. Full comment-based help lives on supported public commands. Existing implementation exports and former `*-Meta*` aliases remain one-release compatibility surfaces only.
- Why: The single module reached 3,300 lines and mixed supported commands with implementation helpers. Domain files improve maintenance, while an explicit manifest and `Get-Help` boundary make the CLI usable without creating multiple submodules or duplicated reference docs.
- See: `scripts/Metra.psm1`, `scripts/Metra.psd1`, `scripts/public/`, `scripts/private/`

## 2026-07-30 - PowerShell-native command surface

- Decision: Keep `metra.ps1` as the shell-friendly dispatcher and also ship an importable `scripts/Metra.psd1` module with approved verb-noun commands such as `Get-MetraProject`, `Get-MetraRouting`, and `Export-MetraContext`. Complete dynamic `-Name` and `-Root` values from the configured portfolio.
- Why: Command-line-oriented operators expect PowerShell command discovery, parameter binding, help, and Tab completion. Thin wrappers preserve one implementation underneath both interfaces.
- See: `scripts/Metra.psd1`, `scripts/Metra.psm1`, `README.md` (PowerShell-native commands)

## 2026-07-30 - setup command and work-only example config

- Decision: Ship `.\metra.ps1 setup` as one-shot onboarding (seed `metra.config.json` from example when missing, optional `-Profile`, roots gloss, workspace regenerate, routing, ctx). Example and sample configs use a work root only; personal/cloud roots are documented snippets (iCloud, OneDrive, generic) in Customizing-Metra - never vendor-detect. Existing local config is never overwritten by the example; `-Force` applies only to profile import.
- Why: Fresh clones hit execution policy, missing config, unexplained routing/ctx, and roots-vs-workspace confusion as separate steps. An iCloud personal root in the example was noisy on machines without iCloud.
- See: `Invoke-MetraSetup`, `README.md` Quick start, `docs/Customizing-Metra.md`

## 2026-07-30 - CLI / module / config rename to Metra

- Decision: Canonical names are `metra.ps1`, `scripts/Metra.psm1`, `*-Metra*` functions, `metra.config.json`, `metra-profile.json`, and workspace keys `metraFolderName` / `metraFolderPath`. Docs and rules teach only those names. Silent one-release compatibility: `meta.ps1` shim, config/profile filename fallbacks, `metaFolder*` dual-read, and exported `*-Meta*` aliases. Live checkout folder may stay `_meta` (Cursor state). Remove shims in a later pass after muscle memory settles.
- Why: Product, persona, canvas, and recommended folder already said Metra; keeping `meta.*` trained two brands.
- See: `metra.ps1`, `meta.ps1`, `scripts/Metra.psm1`, `docs/Brand.md`

## 2026-07-30 - Recommended checkout folder `_metra`

- Decision: Recommended local checkout name is **`_metra`**. Still accepted: `_meta`, `Metra`, `metra` (and legacy `meta`). `Test-MetraSelfFolderName` recognizes all of them. Do not require renaming an existing `_meta` live checkout.
- Why: Leading underscore keeps orchestration at the top of the sibling list; `_metra` matches the product name better than `_meta` without losing that sort behavior.
- See: `README.md` (Naming), `Test-MetraSelfFolderName`, `docs/Brand.md`

## 2026-07-30 - Ship teaching-gentle Persona Add-on

- Decision: Ship `profiles/addons/teaching-gentle/` as the second Persona Add-on. Installs `metra-teaching-gentle.local.mdc`. Activates gentler pacing only when the operator explicitly requests kid/family/beginner/educational or teaching-gentle mode - never infer audience. While active, suppress humor-desk sarcasm. `Get-MetraProfileFileMap` includes the new local rule path.
- Why: Family / educational Cursor sessions need a shareable tone dial without baking audience assumptions into base Metra.
- See: `profiles/addons/teaching-gentle/`, `profiles/addons/README.md`

## 2026-07-30 - Persona Add-ons: tone only (Bing guardrail)

- Decision: Public name is **Persona Add-ons** (`profiles/addons/`). They may alter chat tone only. They may not alter routing, project selection, root isolation, evidence hierarchy, professional artifact rules, or incident handling defaults. Changes that need those behaviors belong in a base-rule discussion. Rename deferred dial `children-friendly` to `teaching-gentle` (style, not audience); apply only when the operator explicitly requests kid/family/beginner/educational mode - never infer. Humor-desk: humor is additive, not substitutive. Defer `list-addons` / `disable-addon` CLI; import = install, delete local rule = remove. Keep README ops-first; document add-ons under customization, not as the product hero.
- Why: Clean split (base = policy, overlay = identity, add-ons = optional preferences) matches the routing-registry pattern and prevents persona soup and ops-first dilution.
- See: `profiles/addons/README.md`, `docs/Customizing-Metra.md`, earlier Decision "Optional persona add-on packs (humor-desk first)"

## 2026-07-30 - Optional persona add-on packs (humor-desk first)

- Decision: Ship optional persona dials as `profiles/addons/<id>/` packs that import into gitignored `.cursor/rules/*.local.mdc` files. Public base `metra-persona.mdc` stays lean. First pack: `humor-desk` (desk-partner humor palette). `Get-MetraProfileFileMap` includes `.cursor/rules/metra-humor.local.mdc` so import/export can carry it. Further packs only when someone would actually import them.
- Why: Operators want louder chat tone without forcing it on every clone or bloating always-on base. Same install path as sample profile; easy to remove by deleting the local rule.
- See: `profiles/addons/README.md`, `profiles/addons/humor-desk/`, `docs/Customizing-Metra.md`

## 2026-07-30 - Keep Metra.psm1 single-file for public v1

- **Superseded** by [Public/private PowerShell module split](#2026-07-30---publicprivate-powershell-module-split). Kept for history.
- Decision: Keep `scripts/Metra.psm1` as one module for public v1. Split internally by operational concern (Core, Projects, Registry, then Context/Audit/Profile/Workspace) only when feature velocity or contributor readability requires it. Public function names stay stable; do not split by line count alone.
- Why: The file is large but coherent as one CLI surface. Premature multi-file layout turns maintenance into a scavenger hunt - the problem Metra exists to avoid.
- See: `scripts/Metra.psm1`, `Export-ModuleMember`, `SECURITY.md` (`run` trust boundary)

## 2026-07-30 - Public README: 90-second + Why Metra

- Decision: Keep a short "90-second understanding" and a brief "Why Metra?" near the top of `README.md`. Full Origin stays in `docs/Customizing-Metra.md`. Do not grow Teaching Mode into prompt coaching, skill levels, quizzes, or reflection loops.
- Why: First-time GitHub visitors need the portfolio/routing story before dense CLI tables. Teaching Mode must stay delivery changes for getting work done - not a second educational product.
- See: `README.md`, `docs/Customizing-Metra.md` (Origin), `.cursor/rules/metra-persona.mdc`

## 2026-07-30 - Quiet verify smoke

- Decision: `.\metra.ps1 verify` uses quiet `ctx` (`-Path -`) and quiet `import-profile -Preview` so fixture smoke does not rewrite `docs/context-pack.*` or spam host output. Focused Pester under `tests/` covers routing rows, import refuse/Preview, quiet ctx, and verify Ok.
- Why: Smoke should be pass/fail without mutating generated packs or drowning the result table.
- See: `Invoke-MetraVerify`, `tests/Invoke-MetraTests.ps1`, `docs/Routing-Scenarios.md`

## 2026-07-30 - Routing fixture smoke via verify

- Decision: Prefer `.\metra.ps1 verify` for Routing-Scenarios fixture checks. Keep the raw PowerShell list in that doc as the human-readable source of truth for what verify covers. Exit `0` with WARN-only; exit `1` on any FAIL.
- Why: Agents need structured PASS/WARN/FAIL instead of eyeball-only smoke.
- See: `docs/Routing-Scenarios.md`, `Invoke-MetraVerify`, `.\metra.ps1 verify`

## 2026-07-30 - Origin note off the always-on hot path

- Decision: Keep a short Metra origin / operating-philosophy note in `docs/Customizing-Metra.md` (Origin). Do not paste the full essay into `.cursor/rules/metra-persona.mdc`.
- Why: Always-on already encodes routing, evidence, incident tone, humor, and Teaching Mode as compact behaviors. The origin text explains those habits for onboarding and continuity without paying token cost every turn or inviting lore growth.
- See: `docs/Customizing-Metra.md` (Origin), `.cursor/rules/metra-persona.mdc`

## 2026-07-29 - sessionStart Ops refresh without workspace rewrite

- Decision: On agent chat `sessionStart`, refresh the Ops board with `snapshot -Quick` only when the snapshot is stale (age > 4h or registry/config newer). Never auto-run `workspace` from that hook.
- Why: Full snapshot is slow; rewriting `Metra.code-workspace` can reload Cursor mid-session. Stale-gated Quick keeps board truth without desk churn.
- See: `.cursor/hooks/session-snapshot.ps1`, `docs/Integrations.md`, `.\metra.ps1 snapshot -Quick`

## 2026-07-29 - Dual-mode brand without a Cursor skin

- Decision: Metra Ops follows host theme tokens (`useHostTheme()`). Brand kit (Signal Teal / Mist / Amber) is intent documentation; optional local `colorCustomizations` may push teal into host accent. No full Cursor theme extension.
- Why: Thin product boundary; coworkers keep their own IDE theme; light and dark both first-class.
- See: `docs/Brand.md`

## 2026-07-29 - Plain English over slash commands

- Decision: Prefer natural-language asks. Do not ship slash commands (`/triage`, `/route`, `/snapshot`) as the primary workflow for this operator.
- Why: Shortcuts help humans who remember them; always-on rules and `AGENTS.md` already encode the procedures for the agent.
- See: `docs/Integrations.md`

## 2026-07-29 - Chat first person; professional sink for artifacts

- Decision: Chat body uses I/we (banner still names Metra). Tickets, commits, ADRs, and redistribution drafts stay ordinary professional prose with no Metra voice.
- Why: Coworker tone in chat without polluting iSupport or git history.
- See: `.cursor/rules/metra-persona.mdc`, `AGENTS.md`

## 2026-07-29 - Product naming

- Decision: Product name is **Metra**. Recommended checkout folder was `_meta` at the time (later updated to `_metra`; see 2026-07-30 Decision). Also accepted: `Metra`, `metra`. CLI was still `meta.ps1` at the time (renamed later; see 2026-07-30 CLI rename Decision). Do not rename the live folder for branding.
- Why: Branding without breaking paths, remotes, or Cursor state slugs.
- See: `docs/Brand.md`, `README.md`

## 2026-07-31 - Ops home answers next and resolve

- Decision: Make the Route home answer two operator questions first: what needs attention next, and where to resolve the current issue. Show a capped, prioritized queue with one next command per item beside the request classifier. Keep project inventory and operating-model evidence in Portfolio and Stewardship. Do not treat workspace pinned folders as routing favorites.
- Why: The board is an operator work surface and Metra faceplate, not a telemetry wall. Wayfinding is the product identity: surface real work, classify the issue, and hand off to the existing home without inventing a second durable store.
- See: `integrations/cursor/metra-ops-board.canvas.tsx.template`, `docs/Brand.md`, `docs/Integrations.md`

## 2026-07-31 - Ask Metra preferred over terminal paste

- Decision: On Resolve this, lead with issue-specific summary/detail/done-when. Prefer Ask Metra (`newComposerChat`) so the agent continues the work in chat. Offer Copy for terminal as the optional self-serve path. Do not put command/copy controls on Needs attention rows - Resolve opens the briefing instead.
- Why: Operators were unsure whether the board expected paste-into-terminal or agent handoff. Metra's face is wayfinding into chat or CLI homes, not a command wallpaper.
- See: `integrations/cursor/metra-ops-board.canvas.tsx.template`, `docs/Brand.md`

## 2026-07-31 - Route home stays useful when the queue is clear

- Decision: When Needs attention is empty and no query is typed, the Route home shows Standing routes (default entry plus pinned present projects) that open the normal handoff, and the empty queue explains why it is empty with a full-snapshot re-scan action.
- Why: A clean portfolio left the home blank, which read as a broken board. Standing routes restore direct access to working homes without reviving pinned hubs as a routing signal.
- See: `integrations/cursor/metra-ops-board.canvas.tsx.template`, `docs/Brand.md`

## 2026-07-31 - Demo is face-first (Ops board before chat prompts)

- Decision: Coworker demo leads with Metra Ops Route (Needs attention / Resolve this / Standing routes), then the routing CLI table, then Trivia chat + professional-sink draft. Rename `Demo-5min.md` to `Demo.md` (recommended ~8 min; keep a strict 5-minute cut). Do not demo Canva/MCP, Decision Registry, OCC, personal roots, or live ticket posts in the default talk.
- Why: The Ops board is the product face for wayfinding; a chat-first script under-taught the desk and over-taught an AI primer.
- See: `docs/Demo.md`, `docs/Brand.md`, `docs/Integrations.md`
- Superseded: 2026-08-03 pitch-first rewrite (middle path story before live clicks).

## 2026-08-03 - Coworker talk is pitch-first (middle path), not a feature demo

- Decision: `docs/Demo.md` is a sales pitch for coworkers. Lead with the balancing act - neither carte blanche AI nor chatbot-only - then optional Ops Ask / routing proof. Live clicks are support, not the spine. Keep non-tech language; drop CLI-heavy face tours as the default path.
- Why: Feature-timed demos were hard to deliver and under-sold what is unique: Metra steers AI to one project, keeps chat useful, and keeps durable writes professional and on request.
- See: `docs/Demo.md`, `docs/Brand.md`

## 2026-07-31 - MCP tool bindings are documented pointers, never tracked credentials

- Decision: External agent tool connections (first case: the Canva remote MCP server) are per-machine harness bindings. Metra tracks a URL-only `integrations/cursor/mcp.example.json` plus a table in Integrations; live `.cursor/mcp.json` is gitignored, and entries carrying `headers` / tokens / API keys stay local. Bindings are optional - when a server is absent, say so rather than inventing a workflow. Profile-pack syncing of `mcp.json` is deferred until a secrets guard exists.
- Why: The connection that matters is a pointer plus per-user OAuth, so sharing it costs nothing and grants nothing. Shipping live config would either leak keys or hand forks an authorization prompt for a subscription they do not have.
- See: `docs/Integrations.md`, `integrations/cursor/mcp.example.json`, `SECURITY.md`

## 2026-07-31 - workspace.exclude keeps folders routable but unmounted

- Decision: `metra.config.json` `workspace.exclude` drops named projects from the generated `Metra.code-workspace` while leaving them in the routing registry. Document the key in Customizing-Metra; ship an empty array in `metra.config.example.json`.
- Why: Frozen review checkouts (for example Metra-Bing-Review) need to stay discoverable without loading a stale `AGENTS.md` as an always-applied Cursor rule in the live workspace.
- See: `scripts/public/Workspace.ps1`, `docs/Customizing-Metra.md`, `metra.config.example.json`

## 2026-08-01 - Ops host supervises by process liveness, not HTTP probe

- Decision: The tray host treats the Ops desk as alive whenever its recorded child process is running. An HTTP probe only confirms a desk when no child process exists, and the host never stops a live child on a failed probe. One restart per failure episode still applies once the child has exited.
- Why: The Ops accept loop is single-threaded, so a long Ask cannot answer `/api/meta`. Probe-only supervision read a busy desk as a dead one and killed the request in flight, which surfaced as "Failed to fetch" in the browser.
- See: `scripts/private/OpsHost.ps1`, `tests/Metra.Tests.ps1`

## 2026-08-01 - Routing scores whole words; Ask stays terse without handoff chrome

- Decision: Query token scoring matches whole words in name/triggers/purpose (not substrings) and drops English stop words. Ask answers omit the Classify handoff card; the Ask engine prompt requires verdict-first brevity and forbids reprinting Where/What/Why/Next.
- Why: Substring hits on "to"/"in"/"the"/"or" inside Trivia purpose text beat real IWUDATA triggers, so Ask opened the wrong cwd and the desk showed a Trivia routing card under a warehouse answer.
- See: `scripts/private/Routing.ps1`, `engines/cursor/server.mjs`, `ops/src/App.tsx`

## 2026-08-04 - Datamart is reference-only; IWUDATA-SQL owns warehouse SQL

- Decision: `Datamart` is a legacy reference tree only - do not edit or deploy from it. Drive warehouse SQL changes in `IWUDATA-SQL`. If an object is missing there, retrieve the live definition from SQL Server and check it into IWUDATA-SQL before changing.
- Why: Operators were editing and deploying from the old Datamart checkout while IWUDATA-SQL is the intended working copy, which split source of truth and risked shipping stale scripts.
- See: `Datamart/AGENTS.md`, `IWUDATA-SQL/AGENTS.md`, `projects.local.json`
