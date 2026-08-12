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

## 2026-08-12 - Host opens operator loopback for Settings authority

- Decision: With Tailscale Serve, `BrowserUrl` / `ShareUrl` stay the peer reach URL. Local Host / Ops browser open uses `OperatorUrl` (`http://127.0.0.1:<port>/`) via `Get-MetraOpsOperatorOpenUrl`. Settings Save role, issue-sync-token, and other local-authority UI stay on that operator desk. Serve peers remain view/ask without inheriting loopback authority.
- Why: Opening the Serve MagicDNS URL on HQ made Save role look broken - Serve strips same-machine authority and `/api/local-session` is loopback-only.
- See: `scripts/private/OpsBinding.ps1`; `scripts/private/OpsHost.ps1`; `scripts/private/OpsServer.ps1`; Ops Settings

## 2026-08-11 - Product update apply is async outside the Ops listener

- Decision: Settings Metra/Ollama Update uses a single-flight background apply job (`%LOCALAPPDATA%\Metra\updates-apply.local.json`) outside the Ops HttpListener request thread. `POST /api/updates` returns **202** with `applyJob` (or **409** `updateAlreadyRunning` / **422** `updateNotApplicable` with no job). `GET /api/updates` while `applyJob.state === running` returns cached Metra/Ollama version fields plus live `applyJob` (no winget/GitHub refresh). Progress is phase + message only for v1 (`percent` always null). Metra self-update may restart or interrupt Ops; interrupted reconciliation surfaces verify-and-retry and best-effort deletes known installer temps only. No auto-apply, no concurrent apply jobs, no generic Ops job framework, no fake percent bar, no shutdown handshake / job resurrection.
- Why: Synchronous apply (especially a ~1.5 GB Ollama setup download) froze the Ops request loop and Settings global `busy` with no progress.
- See: `scripts/private/Updates.ps1`, `scripts/private/OpsServer.ps1`, `ops/src/App.tsx`, plan `non-blocking_product_updates_d09d5386`, [Shipped.local.md](Shipped.local.md) (non-blocking product updates)

## 2026-08-11 - Attention volume handling (composer-first)

- Decision: When Attention exceeds the operator's preferred visible count (`attentionVisibleCount`, fail-closed default 1, clamp 1-10): show compact summary rows; render exactly one focused detail card; contain overflow within a bounded scroll region (Show all expands compact rows only); preserve composer-first access via a sticky presence shell on compact viewports. Held / Keeping in view stays the prior one-card picker in this bite. Voice (`data-voice-state`) and Attention posture (`data-attention`) remain orthogonal on the desk mark.
- Why: Attention may become denser without displacing the primary Ask / Put work surface (presence-first scar).
- See: `ops/src/App.tsx`, `ops/src/attentionVisibleCount.ts`, `ops/src/MetraPresence.tsx`, `Normalize-MetraAttentionVisibleCount` / `Get-MetraAttentionVolumeView` in `scripts/private/Snapshot.ps1`, `tests/Metra.Tests.ps1` (Attention volume contract), [ops/README.md](../ops/README.md), [Brand.md](Brand.md) (desk presence mark)

## 2026-08-11 - Bing file code review required for Metra changes

- Decision: Future Metra code changes are not done until Bing has reviewed the touched files for hardening (validation, ShouldProcess honesty, path safety, contracts, fail-closed edges). Plan review alone is not enough - paste the changed files (or a focused diff) after implementation, fold accepted fixes, then park residuals under Future-Development Bing follow-ups when they are polish-only. Exceptions: pure docs/parking-lot edits with no executable surface, and urgent incident/hotfix when the operator explicitly waives the gate (record the waiver in chat).
- Why: Pre-ship Bing file reviews caught release blockers that plan review missed; keep that gate for ongoing Metra work.
- See: `docs/Future-Development.local.md` (Verify who / Plan + file review loop), Bing module hardening follow-ups

## 2026-08-11 - Public Export-MetraContext re-review: no blockers

- Decision: Leave `Export-MetraContext` as the prior hardened contract (Limit, AsString/Path '-', path parent/directory checks, optional Query). Re-review found no release blockers; only normalize whitespace Path to null before invoke and splat Quiet when true. No ValidateNotNullOrEmpty on Query; overwrite policy stays in `Export-MetraContextPack`.
- Why: Bing Context re-review scored 9.7/10 - further changes would be polish, not risk reduction.
- See: `scripts/public/Context.ps1`

## 2026-08-11 - Start-MetraSetup bootstrap hardening

- Decision: `Start-MetraSetup.ps1` fails closed on PreferFriendly+NoPreferFriendly and on Quiet Satellite without OpsBaseUrl; validates OpsBaseUrl as absolute http/https; warns when Quiet Satellite omits SyncToken; checks module path before Import-Module; starts transcript before installer-log copy with fail-soft warnings if logging fails; only splats true setup switches into Initialize-Metra. Keeps Quiet=>NoPause, hashtable splat, SkipSetup/Preview shortcut, and Wait-MetraBootstrapPause.
- Why: Bing Setup bootstrap review - installer entrypoint needs early validation and non-fatal logging so onboarding does not die on transcript permissions.
- See: `scripts/bootstrap/Start-MetraSetup.ps1`

## 2026-08-11 - Start-MetraOpsHost bootstrap hardening

- Decision: `Start-MetraOpsHost.ps1` validates Port 0-65535 (0 = auto), checks `scripts\Metra.psd1` before Import-Module, sanity-checks the resolved port, and refuses `-Stop` with startup switches. CLI `host` mirrors Stop/startup conflict and port sanity. No SupportsShouldProcess on the launcher.
- Why: Bing Ops host bootstrap review - long-lived host start needs clearer failures without adding cmdlet machinery.
- See: `scripts/bootstrap/Start-MetraOpsHost.ps1`, `metra.ps1`

## 2026-08-11 - Start-MetraOps bootstrap hardening

- Decision: `Start-MetraOps.ps1` validates Port 1-65535, refuses `-Full` with `-Quick`, checks `metra.ps1` exists before invoke, and exits with LASTEXITCODE or 0. Keeps in-process hashtable splat (no nested powershell.exe).
- Why: Bing Ops bootstrap review - launcher polish only; stay simple and predictable.
- See: `scripts/bootstrap/Start-MetraOps.ps1`

## 2026-08-11 - Public Update-MetraWorkspace polish

- Decision: `Update-MetraWorkspace` adds OutputType, ConfirmImpact Low, Months 1-120 / ScanDepth 1-100 (Nullable + post-config range check), UTF-8 no-BOM writes, LiteralPath / Directory.CreateDirectory, and return fields ScanDepth + Preview. `-WhatIfPreview` kept with alias `-Preview` for CLI compatibility; help prefers native `-WhatIf`. Invalid project names with path separators are skipped. CLI workspace only splats true Preview/WhatIf and Months/ScanDepth when >= 1.
- Why: Bing Workspace review - already SupportsShouldProcess; remaining work was validation, encoding, and aligning preview with PowerShell-native WhatIf.
- See: `scripts/public/Workspace.ps1`, `metra.ps1`

## 2026-08-11 - Public Test-MetraInstallation contract hardening

- Decision: `Test-MetraInstallation` declares OutputType bool+pscustomobject and reads Ok via Get-MetraProp (default false) so a null/malformed verify report fails closed as Boolean false. `-Detailed` stays; no ShouldProcess / Force / WhatIf / Quiet / category filters.
- Why: Bing Verify public review - already release-ready; only dual-output metadata and defensive Ok access were missing.
- See: `scripts/public/Verify.ps1`

## 2026-08-11 - Public Export-MetraSnapshot contract hardening

- Decision: `Export-MetraSnapshot` uses SupportsShouldProcess (ConfirmImpact Low), OutputType, and ScanDepth ValidateRange 1-100 via Nullable so omitted ScanDepth keeps the helper default. `-WhatIf` returns before the expensive scan/write. `-Quick` remains the only fast path; `-RefreshSelfDocumentation` stays opt-in. No Force/Quiet/parameter sets. Private `Export-MetraCanvasSnapshot` mirrors ScanDepth range and adds SnapshotPath / Quick / GeneratedUtc on the result (OutPath retained). CLI snapshot only splats true switches and forwards WhatIf.
- Why: Bing Snapshot public review - write-capable export needed native WhatIf and early ScanDepth rejection while staying intentionally small.
- See: `scripts/public/Snapshot.ps1`, `scripts/private/Snapshot.ps1`, `metra.ps1`

## 2026-08-11 - Public Initialize-Metra onboarding hardening

- Decision: `Initialize-Metra` uses SupportsShouldProcess (ConfirmImpact Medium) and OutputType. `-Preview` stays for setup planning; `-WhatIf` maps to the Preview planning path (no writes). Months 1-120 and ScanDepth 1-100 use Nullable ValidateRange. OpsBaseUrl is `[uri]` requiring absolute http/https. PreferFriendly vs NoPreferFriendly conflict fails closed. Role rules: AcceptAsk / PreferFriendly / Advanced refuse Satellite; BindTailscale is Hq-only. SyncToken stays plain string for v1. Result objects add Success and summary flags without removing prior properties. Quiet remains output/prompt only. Private `Invoke-MetraSetup` mirrors validation; CLI setup only splats true switches and forwards WhatIf.
- Why: Bing Setup review - onboarding is the primary public UX and must be PowerShell-native, predictable, and role-safe.
- See: `scripts/public/Setup.ps1`, `scripts/private/Setup.ps1`, `metra.ps1`

## 2026-08-11 - Public Get-MetraRouting contract hardening

- Decision: `Get-MetraRouting` declares OutputType, ValidateNotNullOrEmpty on Name, pipeline Name (value or property), and documents that `-SharedOnly` + `-MissingOnly` may be combined. Implementation buffers pipeline names in begin/process/end so the registry merge runs once. No ShouldProcess / Force / ValidateSet on dynamic project names. Capability/trigger filter parameters stay deferred.
- Why: Bing Routing review - read-only Tier-1 surface needed discoverability and composition, not safety theater.
- See: `scripts/public/Routing.ps1`, `scripts/private/Routing.ps1`

## 2026-08-11 - Public Projects contract hardening

- Decision: `New-MetraProject` uses SupportsShouldProcess, ValidateNotNullOrEmpty Name, LiteralPath / Directory.CreateDirectory, `git -C` (no Push-Location), and returns the resolved root name (not the literal `primary`). Get-* project helpers declare OutputType, document exact `-Name` vs `-Filter` wildcards, and accept pipeline Name. `Update-MetraProject` / `Invoke-MetraProjectCommand` use SupportsShouldProcess; Invoke help matches private parsing (whitespace executable+args, never Invoke-Expression). `Copy-MetraProjectFile` fails fast when Source is missing. Private `Invoke-AcrossProjects` / `Update-MetraProjects` / `Copy-AcrossProjects` mirror ShouldProcess and the source-file guard. CLI `new` / `apply` only splat true switches.
- Why: Bing Projects review (Tier-1 public surface) - mutating project ops needed native WhatIf, literal paths, honest Root labels, and help that matches the hardened command runner.
- See: `scripts/public/Projects.ps1`, `scripts/private/Projects.ps1`, `metra.ps1`

## 2026-08-11 - Public Projects path/WhatIf follow-up

- Decision: `New-MetraProject` rejects empty/invalid template names (`^[A-Za-z0-9._-]+$`) and requires the resolved template dir under `templatesDir` via `Test-MetraPathWithinRoot`. `Copy-MetraProjectFile` / `Copy-AcrossProjects` reject rooted RelativePath, `..` segments, and control chars, and contain the destination under each project root. Public Update/Invoke/Copy forward `WhatIf` / explicit `Confirm` into helpers that already call `$PSCmdlet.ShouldProcess`. Invoke `.PARAMETER Command` documents non-shell quoting (use ScriptBlock for spaces).
- Why: Bing Projects re-review - template traversal, RelativePath escape, and honest WhatIf pass-through were the remaining release blockers; false WhatIf is worse than none.
- See: `scripts/public/Projects.ps1`, `scripts/private/Projects.ps1`

## 2026-08-11 - Profile public API security hardening

- Decision: `Export-MetraProfile` refuses non-empty folder / existing zip without `-Force`, uses SupportsShouldProcess, zip staging cleanup in finally, filters manifest file details to exported paths, and records `source` as MachineName. `Import-MetraProfile` uses SupportsShouldProcess, hardened manifest JSON parse, and optional per-file hash verification via `Assert-MetraProfilePlanHashes`. `Sync-MetraProfile` / status use native WhatIf (SupportsShouldProcess), HTTP timeouts, unique temp zip names, empty-download checks, DontShow RemoteStatus, and warning on failed check-in. CLI export/sync pass Force/WhatIf only when true.
- Why: Bing Profile review - security-sensitive surface needs destination safety, native ShouldProcess, network timeouts, and integrity checks before public readiness.
- See: `scripts/public/Profile.ps1`, `scripts/private/Profile.ps1`, `metra.ps1`

## 2026-08-11 - Public Export-MetraContext contract hardening

- Decision: `Export-MetraContext` validates Limit 1-100, declares OutputType string+pscustomobject, fails early when a file Path parent is missing or Path is a directory, and adds `-AsString` (alias PassThru) as the discoverable stdout mode equivalent to `-Path '-'`. Query stays optional. Private `Export-MetraContextPack` mirrors Limit ValidateRange. CLI `metra.ps1 ctx` accepts `-AsString`.
- Why: Bing public Context review - release-ready surface after bounds + output metadata; path/AsString are QoL for cleaner public failures and PowerShell discoverability.
- See: `scripts/public/Context.ps1`, `scripts/private/Context.ps1`, `metra.ps1`

## 2026-08-11 - Public Get-MetraChat contract hardening

- Decision: `Get-MetraChat` uses Search vs Ticket parameter sets (`-Query` / `-Ticket` exclusive), ValidateRange on Days/Limit, OutputType, pipeline Name, and fails fast unless `-Name`, `-Query`, `-Ticket`, or `-IncludeMetra` is supplied. Private `Get-MetraProjectChats` mirrors Days/Limit ranges and rejects Query+Ticket. CLI `metra.ps1 chats` matches those guards and only splats true switches.
- Why: Bing public Chats review - Tier-1 surface needed bounds, exclusive search modes, empty-search guard, and pipeline Name without ValidateSet on registry names.
- See: `scripts/public/Chats.ps1`, `scripts/private/Chats.ps1`, `metra.ps1`

## 2026-08-11 - Public audit contract: validate ranges and exclusive modes

- Decision: `Test-MetraProjectContext` uses parameter sets so `-DriftOnly` and `-MetadataOnly` are mutually exclusive; documents that `-Name` is exact-match only (wildcards via `-Filter`); validates `LargeFileBytes` / `HighCardinalityCount` / `ScanDepth` ranges; declares `[OutputType([PSCustomObject])]`; accepts pipeline `Name` (string or property). Private `Invoke-MetraProjectContextAudit` mirrors ValidateRange and throws if both mode switches are set. CLI `metra.ps1 audit` only splats a mode switch when true (false switch keys break exclusive sets).
- Why: Bing public Audit review - Tier-1 surface needed validation, OutputType, and clear Drift vs Metadata semantics without changing audit behavior.
- See: `scripts/public/Audit.ps1`, `scripts/private/Audit.ps1`, `metra.ps1`

## 2026-08-11 - Verify v3 covers snapshot, selfdoc, updates, Ask

- Decision: `Invoke-MetraVerify` is VerifyVersion 3. Beyond routing/foundation smoke it checks `Export-MetraCanvasSnapshot -Quick`, `Get-MetraDeskPayload`, read-only selfdoc route/behavior examples (+ Overview.md present), fail-soft `Get-MetraProductUpdates`, and `Get-MetraAskCapability` shape. Results include `Category`. TicketTracker related-set check renamed for clearer PASS meaning. Select-String uses `-LiteralPath`. Full `Update-MetraSelfDocumentation` is not run from verify (avoids mutating Overview/canvas during smoke).
- Why: Bing Verify review - suite still routing-centric while Metra grew Ops/selfdoc/updates/Ask; need versionable check set without silent doc rewrites.
- See: `scripts/private/Verify.ps1`, `scripts/public/Verify.ps1`, `.\metra.ps1 verify`

## 2026-08-11 - Updates cache atomic writes and installer honesty

- Decision: Product update status cache uses temp + Move-Item. GitHub release discovery exposes `hasInstallerAsset` / asset name / size and does not invent a latest-download URL when MetraSetup.exe is missing (`canUpdate` stays false). Winget calls resolve an explicit exe path via Get-Command. Successful Metra installer apply returns `restartRequired: true` and stamps `lastUpdatedAt` / last product versions on the cache. Setup does not invoke update checks.
- Why: Bing Updates review - non-atomic cache; winget.Source ambiguity; silent latest/download fallback; API needed restartRequired for Settings UX.
- See: `scripts/private/Updates.ps1`, `ops/src/types.ts`, `ops/src/App.tsx`

## 2026-08-11 - TicketWatch module import and Affirm A Force override

- Decision: TicketWatch resolves TicketTracker via `Resolve-MetraTicketTrackerModule` (wraps Routing's `Get-MetraTicketTrackerProject`) and imports through `Import-MetraTicketTrackerModule` without forced reload when already loaded. Evidence-next notes are skipped when text is unchanged. Affirm A Confirm with `-Force` on thin evidence prepends a durable operator-override line to the iSupport recommendation body and sets `warning`. Structured `New-TicketDraftAnalysis` Similar/Solutions are preferred over analyze-note regex parsing. `autoStoreRecommend` remains config-visible but never auto-writes.
- Why: Bing TicketWatch review - function-name confusion vs routing helper; repeated Import-Module -Force; evidence-next churn; Force writes needed a durable audit trail; fragile note parsing.
- See: `scripts/private/TicketWatch.ps1`, `scripts/private/AttentionMemory.ps1`, `scripts/private/Routing.ps1`

## 2026-08-11 - Snapshot export stays focused; desk state writes are atomic

- Decision: `Export-MetraCanvasSnapshot` no longer refreshes self-documentation by default. Use `-RefreshSelfDocumentation` when needed; setup already pairs context pack + selfdoc. Snapshot, desk preferences, and Ask journal writes use temp-file + `Move-Item`. Ask journal appends take a named mutex. Git folder probes use `git -C`. Desk payload `homeLabel` is the checkout leaf; `meta.metraRoot` is omitted for Ops HTTP callers without local authority. Full file splits (ask-journal / desk-payload) stay deferred with a domain map comment at the top of `Snapshot.ps1`.
- Why: Bing Snapshot review - implicit selfdoc side effects on every export; non-atomic board/journal state; Push-Location git probes; journal race; remote path exposure; module scope creep.
- See: `scripts/private/Snapshot.ps1`, `scripts/public/Snapshot.ps1`, `scripts/private/OpsServer.ps1`

## 2026-08-11 - Capture Inbox: ledger safety and promote boundaries

- Decision: Capture Inbox stays a thin intake ledger - immutable `derivedFrom`, never auto-loaded into routing or Ask prompts, durable writes only via operator promote. Ledger reads sort by `at` descending; saves use temp-file then `Move-Item`. Suggestion helpers always receive `-MetraRoot`. Project name matches use `-ieq`. Cross-root path checks use `Test-MetraPathWithinRoot` (not raw StartsWith). Markdown stubs flatten multiline summaries and avoid tool-specific "Bing plan" wording (`operator review required`). TicketTracker and ProjectAgents remain suggest-only promote refusals.
- Why: Bing Capture review - MetraRoot drift on suggest paths; file-order ledger reads; non-atomic write; case-sensitive project labels; `_meta` / `_meta2` prefix false positive; multiline TODO injection; product-agnostic parking copy.
- See: `scripts/private/Capture.ps1`, `tests/Metra.Capture.Tests.ps1`

## 2026-08-11 - Audit drift metrics and README trigger ceiling

- Decision: `Invoke-MetraProjectContextAudit` returns both `DriftProjects` (distinct projects with drift, including registry-missing) and `DriftFindings` (actionable finding increments). `DriftCount` remains as a backward-compatible alias of `DriftFindings` for Snapshot/Ops. Stop-word trigger advisories compare `ToLowerInvariant()` keys so case-sensitive stop lists still match. README trigger suggestions use `Get-MetraAuditSuggestedTriggersFromText` with a 200 KB ceiling. Generated-path coverage helper extraction stays deferred.
- Why: Bing Audit review - DriftCount mixed findings vs projects; README regex had no size bound; stop-word Contains needed explicit lowercasing for non-IgnoreCase sets.
- See: `scripts/private/Audit.ps1`, `tests/Metra.Audit.Tests.ps1`, `tests/Metra.AuditMetadata.Tests.ps1`

## 2026-08-11 - Ask secrets: bearer length and connection shapes

- Decision: Ask secrets keeps refuse-vs-redact (PEM refuse; github/aws/slack/api_key/bearer/connection redact). Bearer tokens require at least 20 token characters after `Bearer ` so documentation placeholders (`Bearer test`) are not scrubbed. Connection-string detection covers quoted, brace, and unquoted `Password=` / `Pwd=` values; empty `Password=` and Integrated Security-only strings are left alone. Object walk handles `PSCustomObject` before generic `IEnumerable`. Azure storage keys and bare JWTs stay out of the pattern set until incident evidence warrants them (high signal over broad coverage).
- Why: Bing AskSecrets review - short Bearer matches were false-positive prone; connection edge cases needed explicit coverage; enumerable-before-PSCustomObject was a future footgun.
- See: `scripts/private/AskSecrets.ps1`, `tests/Metra.AskSecrets.Tests.ps1`

## 2026-08-11 - Ask recommend: Ollama trust and honest machine signals

- Decision: Ask recommend stays Ollama-first (never llama.cpp / GPT4All as default). Silent `OllamaSetup.exe` requires Authenticode `Status=Valid` and subject organization `O=Ollama Inc.` (anchored; same rule as Ollama install.ps1). `ollama serve` polling stops early when the process has exited. Undetected RAM is `ramDetected=false` / `ramGb=null` and defaults to medium with an explicit reason - not a fake 16 GB reading. Accept / `ask engine set ollama` merge `ask.ollama` while preserving unknown nested keys despite shallow `Save-MetraAskConfigPatch`.
- Why: Bing AskRecommend review - substring "Ollama" signer trust was weak; serve bind failures waited full timeout; missing RAM looked authoritative.
- See: `scripts/private/AskRecommend.ps1`, `tests/Metra.AskRecommend.Tests.ps1`

## 2026-08-11 - OpenAI-compat Ask health and enterprise capability states

- Decision: OpenAI-compatible Ask health (`Get-MetraAskOpenAICompatHealthResult`) treats only HTTP 2xx as healthy. 401/403/404 map to `auth_required` / `forbidden` / `not_found` (reachable-but-not-ready). Do not probe the base URL root. Enterprise capability surfaces `enterprise_key_missing`, `enterprise_forbidden`, `enterprise_api_missing`, and `enterprise_unreachable` distinctly; completion errors use stable codes (`enterprise_auth_failed`, `enterprise_request_failed`, `ollama_unreachable`, `llamacpp_unreachable`) instead of raw exception text. Context JSON ceiling is evidence `maxTotalChars` * 5. Enterprise prompts send project leaf name, not full local CWD. Ollama tagged model pins do not fuzzy-match different size tags.
- Why: Bing AskOpenAICompat review - 401 counted as healthy; enterprise credential vs unreachable were conflated; root URL and raw errors leaked misleading readiness.
- See: `scripts/private/AskOpenAICompat.ps1`, `scripts/private/AskEngine.ps1` (`Get-MetraAskCapability`), `tests/Metra.AskOpenAICompat.Tests.ps1`

## 2026-08-11 - Ask image resolve: quarantine containment and size

- Decision: `Resolve-MetraAskImages` only accepts Place-quarantined image files. Both metadata `fileName` and on-disk path must have an allowed image extension; the resolved path must pass `Test-MetraPathWithinRoot` against `Get-MetraPlaceQuarantineRoot`; per-file size is capped at 8 MB (aligned with Place upload). Journal pointers remain `id` + `fileName` only. MIME stays extension-derived for Ladder 3; magic-byte sniff is a future hardening note.
- Why: Bing AskImage review - metadata-only validation could pass arbitrary local paths to the Cursor sidecar; size was count-capped only.
- See: `scripts/private/AskImage.ps1`, `tests/Metra.AskImage.Tests.ps1`, `Get-MetraPlaceQuarantineRoot`

## 2026-08-11 - Ask evidence: ids not factual; live intent heuristic; CLI cap

- Decision: Ask evidence quality stays deterministic from route + collected items (not model confidence). Ticket **ids** in the prompt are identifier cues only (`factualSupport=false`); factual ticket/brief support requires content (brief/summary). Live-status intent uses phrase match plus a scored token heuristic. AGENTS CLI surfaces are capped at 2 evidence items so documentation does not fill the 6-item budget.
- Why: Bing AskEvidence review - ids were over-counting as factual; live phrasing was too narrow; CLI excerpts crowded out richer future evidence.
- See: `scripts/private/AskEvidence.ps1`, `tests/Metra.AskEvidence.Tests.ps1`

## 2026-08-11 - Ask engine normalized capability/invoke contract

- Decision: Ask engines are selected by configuration but exposed through one normalized capability/invoke contract (`Get-MetraAskSettings` / `Get-MetraAskCapability` / `Invoke-MetraAskEngine`). Cursor owns vision in this release. OpenAI-compatible engines (Ollama, enterprise, llama.cpp) are text-only unless explicitly upgraded. Secrets are scrubbed before engine calls and after engine responses.
- Decision: `Save-MetraAskConfigPatch` is a shallow merge into `ask.*` (nested engine objects replace wholesale). Cursor sidecar stop validates node/sidecar process identity before `Stop-Process`. Enterprise `apiKeyEnv` is optional unless `ask.enterprise.requireApiKey`; capability reports `enterpriseKeyPresent` and reason `enterprise_key_missing` when required. Operator-facing engine errors use stable codes (`engine_request_failed`) instead of raw HTTP exception text.
- Why: Multi-engine Ask needs a single desk language; Bing pre-ship review called out shallow-patch semantics, stale PID kill risk, credential vs unreachable distinction, and error leakage.
- See: `scripts/private/AskEngine.ps1`, `scripts/private/AskOpenAICompat.ps1`, `tests/Metra.AskEngine.Tests.ps1`

## 2026-08-11 - Ops local-authority helper and CORS removal

- Decision: Remove wildcard CORS from the Ops HttpListener (same-origin UI only). Centralize locality checks in `Test-MetraOpsRequestHasLocalAuthority` / `Assert-MetraOpsLocalAuthority` (same-machine Serve-aware or validated `X-Metra-Local-Session`). Gate refresh, watch, preferences PUT, ask/engine POST, attention mutations, place confirm/correct, settings, updates, open, and profile issue-sync-token. Keep Ask-class remote reach for ask, capture create/dismiss/propose, place upload/route, and read-only meta endpoints. Profile satellite roster is local-authority only (`GET /api/profile/satellites`; status fingerprint without roster for sync-token callers). `GET /api/local-session` rejects Serve-proxied requests. Default 1 MiB request body limit (10 MiB place multipart); static files require `Test-MetraPathWithinRoot` under `ops/dist`.
- Why: Wildcard CORS plus ungated mutation endpoints let any origin on a shared Tailscale URL act like a local operator; roster leak and missing body limits were Bing review blockers.
- See: `scripts/private/OpsServer.ps1`, [SECURITY.md](../SECURITY.md), [ops/README.md](../ops/README.md)

## 2026-08-11 - TicketWatch vocabulary proposals are evidence-driven

- Decision: Vocabulary proposals are evidence-driven. TicketWatch proposes additions from recurring ticket terminology that is not already represented in portfolio vocabulary. TicketWatch does not maintain a product catalog, product vocabulary list, or a growing product/noise word blacklist.
- Decision: Thin Preview may propose gaps with subject counts (propose only). Sighting gate: `df >= vocabularyMinSightings` (default 2), or `df == 1` and strong acronym (acronym-like and length >= 4). Language filler uses `Get-MetraRoutingStopWords`. Common tokens die via `vocabularyMaxSubjectShare`.
- Decision: Seed pending recognition keywords in TicketTracker solutions index (no write-up yet) from open ticket subjects; promote into write-up rows when durable guidance exists.
- Why: Blacklist-subtraction (`vocabularyStopWords`) recreated the same drift as hardcoded product cues. Portfolio owns vocabulary; TicketWatch observes and proposes.
- See: `Get-MetraTicketWatchSuggestedVocabulary`; `Get-MetraTicketWatchSubjectCorpusStats`; `TicketTracker/solutions/README.md` Recognition vocabulary

## 2026-08-11 - TicketWatch product cues consume portfolio vocabulary

- Decision: TicketWatch does not maintain a portfolio product catalog. Product cues are derived from portfolio sources (solutions keywords, registry triggers, and local overlays).
- Decision: Cue builder normalizes (trim, lowercase, length >= 3, unique, sort). Registry triggers are filtered aggressively for generic routing/ops words; solutions keywords remain the strongest recognition signal; `ticket-watch.local.json` `productCues` is the escape hatch for temporary gaps (e.g. ILLiad before a solutions row). Recognition (cue) is not routing (trigger) - do not add cues as TicketTracker `projects.json` triggers merely for recognition.
- Decision: TicketWatch may filter generic routing triggers when deriving product cues from the registry. That filter is not a vocabulary proposal blacklist and must not grow in response to ticket-subject noise.
- Decision: Product-cue recognition uses token-boundary matching for single-token cues (avoid substring false positives) and phrase substring for multi-word cues.
- Why: A hardcoded IWU product list in TicketWatch.ps1 drifted (ILLiad hand-add) and duplicated solutions + registry vocabulary ownership.
- See: `scripts/private/TicketWatch.ps1` (`ConvertTo-MetraTicketWatchNormalizedProductCues`, `Get-MetraTicketWatchProductCueList`, `Test-MetraTicketWatchTextHasCue`); `docs/ticket-watch.local.example.json`

## 2026-08-11 - Preview recommendation soft-gate (operator feedback)

- Decision: Attention **Preview recommendation** always drafts locally for Mine-eligible tickets. Thin evidence returns actionable next steps (no E1 jargon) and still saves a local recommend-draft. **Write recommendation** stays hard-gated unless Force.
- Decision: Thin-evidence Preview must not emit Findings / Suggested investigation Gaps template. It refreshes local analyze + evidence-next, then returns a **next-evidence brief** ("Not a recommendation yet"). Real recommend bodies require recommendable evidence or Force.
- Why: Hard-failing Preview with "E1 draftState is not recommendable" gave operators nothing to do with. Soft-gating into a fake Findings body was worse - it looked like routing/troubleshooting happened when only the subject was echoed.
- See: `scripts/private/TicketWatch.ps1` (`New-MetraTicketWatchNextEvidenceBody`, `Invoke-MetraTicketWatchEnsureAnalyzeEvidence`); Ops ResolveActions

## 2026-08-11 - Ticket Watch Attention ranks Update from first

- Decision: Attention ticket sort ranks `Update from Representative` / `Update from Customer` above `Open`, then by newest `updated` timestamp within the same status band. Waiting on Customer stays below Open.
- Decision: TicketTracker full open-queue SQL includes `Status LIKE 'Update from%'` so inbound update statuses cannot be dropped when StatusType is outside 1/4.
- Why: Update from and Open previously shared statusRank 0, so the desk sorted by ticket id text. Portfolio refresh never covers tickets, so operators rely on Scan tickets plus correct ranking to surface inbound replies.
- See: `scripts/private/TicketWatch.ps1`; `scripts/private/AttentionMemory.ps1`; `TicketTracker/providers/isupport/sql/open-tickets.sql`

## 2026-08-11 - Profile Sync Serve authority and freshness visibility

- Decision: Serve remotes must not inherit loopback authority. `Test-MetraOpsRequestIsSameMachine` treats Tailscale Serve identity headers (and non-loopback `X-Forwarded-For` / `X-Real-IP`) as remote even when `RemoteEndPoint` is loopback. After that deny, locality prefers loopback and a validated `X-Metra-Local-Session` over raw IP ownership.
- Decision: Profile fingerprints are publisher-side state. Satellite freshness is determined by comparing the published fingerprint with the last applied fingerprint (`.\metra.ps1 profile status`).
- Decision: HQ satellite roster is check-in only. HQ never invents unseen machines and never pushes profile state. Satellites POST `/api/profile/check-in` after status/sync; registry lives under `%LOCALAPPDATA%\Metra\profile-satellites.local.json`.
- Why: Tailscale Serve collapsed remote callers into local machine authority for profile status, issue-token, and other local-only routes. Operators also needed "Am I current?" and "Which satellites have checked in?" without daemons or pack push.
- See: `scripts/private/OpsOpen.ps1`; `scripts/public/Profile.ps1`; `scripts/private/OpsServer.ps1`; Ops Settings Profile Sync

## 2026-08-11 - Bootstrap calls Initialize-Metra directly (no array splat)

- Decision: `Start-MetraSetup.ps1` invokes `Initialize-Metra` with a hashtable splat. It must not array-splat switches through `metra.ps1`. `metra.ps1 setup` also ignores `$Rest` tokens that start with `-` when resolving a profile path.
- Why: On Windows PowerShell 5.1, `.\metra.ps1 setup -Quiet ...` via `@('setup','-Quiet',...)` put `-Quiet` in `$Rest`; setup treated it as a profile path (`...\-Quiet`) and aborted before SyncToken write / first sync.
- See: `scripts/bootstrap/Start-MetraSetup.ps1`; `metra.ps1` setup case

## 2026-08-11 - Satellite installer accepts optional Profile sync token

- Decision: Satellite connect page collects optional **Profile sync token** (password field) alongside **Main Metra address**. Quiet setup passes `-SyncToken` and writes `docs/profile-sync.local.json`, then best-effort `profile sync`. Token remains optional; address stays required.
- Why: Manual paste into profile-sync.local.json blocked easy Satellite first-run after the wizard already collected the HQ address.
- See: `packaging/inno/Metra.iss`; `Set-MetraProfileSyncClientToken`; `docs/Brand.md`

## 2026-08-11 - Quiet setup runs during install; no Finished checkbox

- Decision: After the wizard collects role and preferences, `Metra-Setup.cmd -Quiet ...` runs from `[Run]` during install (`runhidden waituntilterminated`), not as an Inno Finished `postinstall` checkbox. Files only still skips via `Check`. Finished is handoff-only (Metra Ops / Metra Setup).
- Why: A "Setting up Metra" checkbox after answering every question felt like a second decision and could be unchecked by accident.
- See: `packaging/inno/Metra.iss`; `packaging/README.md`

## 2026-08-11 - Installer defaults to Standalone; folder page always shown

- Decision: Installer role list order is Standalone (default) / HQ / Satellite / Files only. No machine detection. Select Dir always shows (`DisableDirPage=no`) while `UsePreviousAppDir=yes` prefills the prior AppId path when present.
- Why: Satellite-as-default was desk-story bias and a false start for most first installs; skipping the folder page on reinstall hid a real choice.
- See: `packaging/inno/Metra.iss`; `docs/Brand.md`; `packaging/README.md`

## 2026-08-11 - Brand owns operator vocabulary

- Decision: Operator-facing terminology is defined in `docs/Brand.md` (Operator vocabulary + voice/humor boundary). New operator surfaces (installer, Metra Ops Settings, onboarding) must use that glossary. Implementation names (`machineRole`, `opsBaseUrl`, Ask engine, etc.) are not operator-facing copy. Review standard: is this operator text? Check Brand.md. Product = Metra; primary UI = Metra Ops (introduced after install). Installer role = intent (Standalone / HQ / Satellite / Files only); no Run-setup checkbox. Dry humor boundary is in Brand; dials stay in persona / humor-desk.
- Why: Glossary drift (Main Metra machine vs HQ Ops vs jumpbox vs OpsBaseUrl) makes a simple architecture feel hard; Brand as single mouth keeps installer and Settings aligned after ship.
- See: `docs/Brand.md`; `packaging/inno/Metra.iss`; `ops/src/App.tsx` Settings machine-role row

## 2026-08-11 - Installer collects all first-run setup choices

- Decision: Inno wizard pages collect machine role, Satellite OpsBaseUrl, and for HQ/Standalone: PreferFriendly / NoPreferFriendly, HQ BindTailscale, and AcceptAsk. Post-install runs `Metra-Setup.cmd -NoPause -Quiet` with those switches hidden. No terminal quiz on first install. Start Menu Metra Setup remains interactive.
- Why: Operators already answered every former Read-Host question in the wizard; silencing without collecting left HQ choices unspoken.
- See: `packaging/inno/Metra.iss`; `scripts/bootstrap/Start-MetraSetup.ps1`; `metra.ps1 setup -Quiet -PreferFriendly|-NoPreferFriendly -BindTailscale -AcceptAsk`

## 2026-08-11 - Installer collects role; post-install setup is quiet

- Decision: Inno wizard pages collect `machineRole` (and Satellite `OpsBaseUrl`). The post-install task runs `Metra-Setup.cmd -NoPause -Quiet -Role ... [-OpsBaseUrl ...]` hidden (`runhidden waituntilterminated`). No terminal Read-Host quiz on first install. Start Menu Metra Setup remains interactive. Transcript stays in `docs/setup.local.log`.
- Why: Operators already answered in the wizard; a second console quiz feels broken.
- See: `packaging/inno/Metra.iss`; `scripts/bootstrap/Start-MetraSetup.ps1`; `metra.ps1 setup -Quiet`

## 2026-08-11 - Durable setup / installer logs under docs/*.local.log

- Decision: First-run bootstrap and `metra setup` append a transcript to `docs/setup.local.log`. When an Inno Setup log is found in `%TEMP%`, copy it to `docs/installer.local.log`. Both are gitignored and excluded from the installer stage. Setup prints the setup log path.
- Why: Laptop install failures (parse errors, nested paths, role prompts) left no durable transcript to share for troubleshooting; Inno `SetupLogging=yes` alone lands under TEMP with opaque names.
- See: `Start-MetraSetupTranscript`; `Copy-MetraInnoInstallerLog`; `packaging/README.md`

## 2026-08-10 - First-run setup stays short and role-first

- Decision: Interactive setup asks machine role before portfolio refresh. Human output is short summaries (roots lines, workspace count, routing present/missing counts) - not full routing tables or whenMissing walls. Satellite never gets local Ops host / Tailscale / Ask-accept prompts; Advanced networking is HQ/Standalone only. Satellite Next tips point at OpsBaseUrl and profile sync.
- Why: 0.1.2/0.1.3 first-run dumped developer registry noise before the role questions, and Satellite Advanced still asked port-80 / Tailscale host knobs.
- See: `Invoke-MetraSetup`; `Invoke-MetraMachineRoleSetup`; `Update-MetraWorkspace -Quiet`

## 2026-08-10 - Installer selected folder is the product root

- Decision: Inno Setup uses `AppendDefaultDirName=no`. The folder chosen on the Dir page is `{app}` (e.g. `C:\Projects\_metra` or Documents\Metra). Do not choose the portfolio parent (`C:\Projects`). The wizard refuses paths that look like a portfolio root (child TicketTracker or Solarwinds) unless `metra.ps1` is present or the leaf is Metra / `_metra` / `_meta` / `metra`.
- Why: With AppendDefaultDirName=yes, choosing `_metra` produced `_metra\Metra`, so seeded `"path": ".."` resolved to `_metra` instead of the portfolio parent.
- See: `packaging/inno/Metra.iss`; `packaging/inno/dir-readme.txt`; `packaging/README.md`

## 2026-08-10 - First-run begins with machineRole

- Decision: Setup persists `machineRole` (`Hq` | `Satellite` | `Standalone`) in `docs/ops-preferences.local.json` before networking knobs. Defaults apply role prefs (HQ: friendly when port 80 free, optional Tailscale offer; Satellite: loopback + OpsBaseUrl prompt, no Tailscale; Standalone: friendly when free else 7380, no Tailscale). Advanced (`setup -Advanced`) keeps per-knob prompts. Ops Settings shows a Machine role card. Runtime Desk Modes remain Standalone / HqClient / ForceLocal consumers of OpsBaseUrl.
- Why: Raw friendly-URL / Tailscale quizzes without role context confused satellite installs; HQ / Satellite / Standalone describe the machine on the network.
- See: `Invoke-MetraMachineRoleSetup`; `.\metra.ps1 setup -Role`; `docs/Cross-Device.local.md`

## 2026-08-10 - One authoritative Ask journal host (Desk Mode B)

- Decision: Metra maintains one authoritative Ask journal host. Satellite devices query the journal remotely and do not host Ask services unless explicitly started with `-ForceLocal`.
- Why: Avoid journal divergence, session-id collisions, and continuity ownership ambiguity across laptop/jumpbox/phone. Profile stays a replicated pull; Ask journal stays a centralized query.
- See: `docs/Cross-Device.local.md` (Desk Modes); `Get-MetraDeskMode`; `Invoke-MetraAskLogCommand`; `Assert-MetraOpsMayStartLocally`

## 2026-08-10 - Desk Mode B: one OpsBaseUrl for profile pull and Ask query

- Decision: Desk Mode B (HQ Client) means one configured OpsBaseUrl: profile sync pulls from HQ; Ask journal CLI queries HQ; local Ops hosting is refused unless `-ForceLocal`.
- Why: Shared control plane prevents profile-sync vs ask-client drift. `Get-MetraDeskMode -ForceLocal` owns the mode decision; callers only switch.
- See: `docs/Cross-Device.local.md`; next bite remains remote `POST /api/ask` (not this scar)

## 2026-08-10 - TicketWatch M3: recommend-draft before store-as-review; autoStore off on Mine

- Decision: M3 separates recommendation authorship from Affirm A storage. Preview writes a local `recommend-draft` note only. Confirm / Write recommendation calls TicketTracker `recommend` and must supersede the single `Metra AI Recommendation:` section (never accumulate versions). E1 `recommendable` gates willingness to draft; `-Force` overrides. `autoStoreRecommend` stays false through the Mine quality loop; reconsider only after M4. Affirm B (implement/resolve) remains out of TicketWatch. Ephemeral Basis summary may ground authoring; no confidence ledger.
- Why: Store-as-review is durable enough to preview; Mine tuning needs generate/read/improve/regenerate without short-circuiting via auto-store; E1 already owns evidence sufficiency.
- See: plan `ticket_watch_mine-first_89e19166` M3; F3.x; Bing M3 refine 2026-08-10

---

## 2026-08-10 - TicketWatch E1: next source not solution; quality not confidence; recommendable handoff

- Decision: E1 suggests the most promising **next evidence source**, not the most likely **solution**. E1 optimizes recommendation **quality**, not recommendation **confidence** (no scores, confidence ledgers, or ranking theater). Draft state is binary and ephemeral: `needsEvidence` (one source suggestion) or `recommendable` (`action: none` + desk cue Evidence appears sufficient / Ready for recommendation). Recommendable when any of: strong similar-ticket match, matching solutions/KB, product cue maps to established guidance, or operator supplied the sought fact - not a confidence percentage. E1 must not generate or write recommendations; M3 is the author. Conceptual ladder collapses duplicate KB steps to "institutional knowledge exhausted?" then M365, askOperator (blocked only), boundedWeb, none.
- Why: Keeps detective vs author split; answers when enough information exists without turning E1 into half of M3 or a second Attention/confidence system.
- See: plan `ticket_watch_mine-first_89e19166`; Bing E1 approve 2026-08-10; F3.x

---

## 2026-08-10 - TicketWatch E1: do not presume missing facts; subject/person likelihood first

- Decision: E1 Next-evidence routing must not treat thin ticket descriptions as automatic `askOperator`. Most tickets lack complete facts. Prefer ephemeral likelihood from **given information** (subject, product cue, mnemonic) and from probable prior tickets for **this subject** and/or **this person** (requester), then institutional KB / solutions, then org evidence, then askOperator only when the next step is blocked without a human fact, then bounded web. Do not persist probability scores, confidence ledgers, or evidence-accumulation memory - heuristics are in-memory for the single suggestion only.
- Why: Defaulting to ask-operator on incompleteness would spam the Mine review loop and skip the institutional memory TicketWatch exists to surface.
- See: plan `ticket_watch_mine-first_89e19166` E1 ladder; F3.x; Bing E1 tighten (no evidence ledger) same day

---

## 2026-08-10 - Ask: KB first, then explicit web-search offer

- Decision: Ops Ask evidence order for how-to / product questions is: check institutional KB (TicketTracker solutions index and related local knowledge) before concluding "unknown." On a KB miss, Ask may **offer an explicit prompt** to search the web (operator/coworker affirms). Do not unsupervised web-search on every Ask turn. Do not invent answers from the technical project alone when a KB check was skipped. TicketWatch E1 stays suggest-only for `boundedWeb` (query string); Ask may perform the fetch **after** an explicit yes on that offer. Channels stay separate (Ask != TicketWatch) but share the same knowledge ladder.
- Why: Morning 2026-08-10 phone Ask ("install a printer in Colleague") fail-closed on the Colleague module without a solutions KB pass - same knowledge gap TicketWatch must not repeat. Explicit web offer keeps honesty without stranding the user when the org KB is empty.
- See: Ask Journal session `agent-ca38d156-c44a-48f1-8ecd-798e24b42563`; F3.x / plan `ticket_watch_mine-first_89e19166` Next-evidence ladder; Decisions TicketWatch Affirm A/B same day

---

## 2026-08-10 - Metra TicketWatch: Observe -> Draft -> Review -> Apply; Mine Affirm A = store-as-review

- Decision: TicketWatch authority ladder is Observe -> Draft -> Review (Affirm A) -> Apply (Affirm B). Affirm A stores a durable `Metra AI Recommendation` for review; Affirm B is implement/resolve/Live change. On Mine scope, Affirm A is **store-as-review**: writing the recommendation to iSupport is the review surface (re-run/rewrite expected). A recommend write does not imply confidence, approval, implementation, or correctness. Tighten Affirm A (preview/confirm) only when Attention scope widens beyond Mine. E1 Next-evidence suggestions are non-binding, suggest-only (signal -> one source), and do not require a later recommend. M3 is the first bite that may drive store-as-review. E1 must not create evidence accumulation memory (scores/history/confidence ledger) or a second Ask product.
- Why: First-line triage needs a durable review artifact without collapsing recommend into Apply; Mine-only rollout keeps weak recommends off the team floor while quality is tuned.
- See: plan `ticket_watch_mine-first_89e19166`, `docs/Future-Development.local.md` F3.x

---

## 2026-08-10 - Metra TicketWatch: cache != Attention; mine-first gate

- Decision: TicketTracker sync cache is not Attention eligibility. Metra TicketWatch applies an Attention eligibility contract before upsert. Under `ticketWatch.scope=mine` (default), candidates must be active, match TicketTracker `meFilter` or `assigneeFilter` via `Test-TicketMatchesPersonFilter`, and normalize through `ConvertTo-TicketSensorObject`. Empty person filters fail closed (zero candidates). Explicitly not eligible: queueInclude-only, Unassigned that fails person filter, pull-only not-mine, watched-but-not-mine. Widen only via an explicit later scope bite (e.g. `mine+unassigned`). TT may still sync broadly.
- Why: Without a Metra gate, queueInclude / pull / future team cache membership becomes accidental Attention and turns troubleshooting into an implicit subscription.
- See: `scripts/private/TicketWatch.ps1`, `docs/Future-Development.local.md` F3.x, plan `ticket_watch_mine-first_89e19166`

---

## 2026-08-09 - Ask desk renders Metra replies as sanitized Markdown

- Decision: Ops Ask renders **Metra reply** bubbles as sanitized Markdown (`react-markdown` + `rehype-sanitize`). Session Journal / transport / Capture keep **raw Markdown text** - rendering is presentation only. Operator ("You") turns stay plain `pre-wrap` text. Links allow `http:` / `https:` only; intentionally deny `javascript:`, `data:`, `file:`, and other schemes (Metra replies must not create executable or local-file links). Explicit `code` / `pre` components distinguish inline vs fenced blocks with horizontal overflow on fences - no syntax highlighter. Do not use raw `dangerouslySetInnerHTML` for engine output.
- Why: Engines already emit Markdown; literal `pre-wrap` made replies hard to read (especially on phone). Edge-only render keeps export/index/summarize paths on original Markdown and treats multi-engine replies as potentially hostile.
- See: `ops/src/AskMarkdown.tsx`, `ops/src/App.tsx`, `ops/src/styles.css` (`.ask-md`), plan `ask_markdown_render_f9c7c21b`
- Explicit non-goals: syntax highlighting, Mermaid, tables, task lists, HTML passthrough, copy buttons, Markdown editors, Capture/Attention/Settings Markdown, prompt changes

## 2026-08-09 - Cursor Ask defaults to Auto Cost

- Decision: When `ask.engine=cursor`, Metra Ask **defaults** to Cursor Router **Auto Cost**: model id `auto-smart` with `optimize_for=cost` (`ask.cursor.optimizeFor`). This is the legacy Auto behavior (Cursor Models pool, bundled Auto pricing). Do **not** default to Auto Balance. Balance / Intelligence remain opt-in via `ask engine set cursor -Model auto-balance` (or `auto-intelligence`). Composer / Grok pins remain available for experiments.
- Why: Auto Balance billed routed third-party models into **Other Models** and hard-failed Ask when that pool hit 100% with on-demand off. Legacy Auto / Auto Cost stays on Cursor Models and degrades gracefully. Operator scar 2026-08-09: Balance exhausted Other Models while Cursor Models still had headroom; IDE Optimize for Cost is Ctrl+Alt+/.
- See: `engines/cursor/server.mjs`, `scripts/private/AskEngine.ps1`, `scripts/private/AskRecommend.ps1` (`Set-MetraAskEngine`), `metra.config.example.json`, Cursor docs Cursor Router / `auto-smart`

## 2026-08-09 - Cursor Ask pin to Composer when Other Models quota is exhausted (superseded default)

- Decision: **Superseded as the default** by Auto Cost above. A hard pin to `composer-2.5` remains a valid override when Auto Cost is unavailable or for A/B checks. Prefer Auto Cost over Composer pin for routine desk Ask.
- Why: Usage evidence 2026-08-09 - Other Models 100% used (mostly Balance routing); Cursor Models ~40% used. Composer pin restored availability; Auto Cost is the better durable default on the same pool.
- See: `ask engine set cursor -Model composer-2.5`, Cursor usage dashboard (Cursor Models vs Other Models)

## 2026-08-08 - Ladder 3 Done: Ask image intake (vision-read evidence)

- Decision: Ladder **3** Ask image intake (vision-read evidence) is **closed**. Shipped: Place quarantine resolve for png/jpeg/gif/webp (max 3), `POST /api/ask` `imageIds`, evidence kind `image` without FactualSupport for live status, Cursor sidecar path-based vision + attribution prompt contract, consumer Ollama/enterprise image degrade before call, Session Journal `images: [{ id, fileName }]` only, Ops attach/paste with Ask for image ids and Put somewhere for other types. L2 Classify and grounded-answer invariants remain authoritative - screenshots alone cannot ground live Orion/iSupport claims.
- Why: Layer A Pester `Ask image intake - Ladder 3` (5/5) including screenshot-only Orion, and smoke `tests/smoke-ask-image-intake.ps1` passed 2026-08-08.
- See: `docs/Shipped.local.md` (Ask image intake), `scripts/private/AskImage.ps1`, `scripts/private/AskEngine.ps1`, `engines/cursor/server.mjs`, `ops/src/App.tsx`, plan `ask_image_intake_4d17fccb`
- Explicit non-goals unchanged: no OCR subsystem; no PDF/video; no Route OCR-only; no Ollama vision catalog; no auto-Capture from images; no journal path/mime/base64; no Host apply from image

## 2026-08-08 - Ladder 3 Active: Ask image intake (vision-read evidence)

- Decision: Ladder **3** is **Active** as **Ask image intake (vision-read evidence)** (not OCR). Images enter Ask via Place quarantine under `%LOCALAPPDATA%\Metra\` only (permanent security rule - never Metra git checkout). Cursor sidecar is the only MVP vision path; consumer Ollama/enterprise with images always degrade before call. Media: png/jpeg/gif/webp, 8 MB, max 3 per turn. Journal stores `images: [{ id, fileName }]` only - no path, mime, binary, or base64. Vision may provide observations about visible content; it is not authoritative system state. L2 Classify and evidence invariants remain authoritative - attaching an image does not auto-ground live Orion/iSupport claims. Image-derived statements must be attributable ("The screenshot appears to show..."). Composer sends image-typed quarantine ids to Ask; non-image Place types stay Put somewhere. No auto-Capture from images; answer-only ceiling; no Host apply from image.
- Why: Ask was text-only while Place already staged screenshots; Bing second-pass locked Place quarantine as source of truth, Cursor-only vision, and honest Ollama degrade so pixels cannot override routing.
- See: `docs/Shipped.local.md` (Ask image intake; closed), plan `ask_image_intake_4d17fccb`, `SECURITY.md` (Ask image staging / ask-log pointers)
- Explicit non-goals: PDF/video OCR; Route OCR-only; iOS camera; live webcam; Ollama vision catalog / pin swap; Capture auto-create from image text; silent image drop; auto engine switch; inventing live system status from screenshots alone

## 2026-08-08 - Ladder 2b Done: Cross-product Ask Capture Host MVP

- Decision: Ladder **2b** Capture Inbox v2 Host MVP is **closed**. Shipped: registry-aware `Resolve-MetraCaptureSuggestedTarget` (soft ticket vs strong ticket), `Propose-MetraCaptureSplit` / `Add-MetraCaptureFromAskSplit` (accepted-only), `ProjectBacklog` TODO.md promote with `Test-MetraLocalAuthority` + cross-root confirm, ProjectAgents/TicketTracker fail closed, CLI `propose-from-ask` + promote `-Home`/`-Project`/`-CrossRootConfirm`, Ops `/api/capture/propose` + accepted create + promote fields, Ops compact Save sheet + Capture inbox selectors. Schema remains `schemaVersion: 1`.
- Why: Layer A Pester `Capture Inbox v2 - Ladder 2b` (6/6) and mixed-session smoke `tests/smoke-capture-inbox-v2.ps1` passed 2026-08-08.
- See: `docs/Shipped.local.md` (Capture Inbox v2), `scripts/private/Capture.ps1`, `scripts/private/OpsServer.ps1`, `ops/src/App.tsx`, plan `capture_inbox_v2_d3ef2d89`
- Explicit non-goals unchanged: no auto-promote; no silent cross-root; no invented projects; no Capture-to-AGENTS; no iSupport writes; no LLM auto-split required path

## 2026-08-08 - Ladder 2b Active: Cross-product Ask Capture Host MVP

- Decision: Unpark Ladder **2b** as a Host MVP implementation bite for Capture Inbox v2. Ask Save or CLI may propose up to five Capture candidate rows from one Ask turn or session window using registry-backed `suggestedProject` values. Capture ledger writes happen only after operator affirmation. `ProjectBacklog` promotes append to the registered project `TODO.md` and require Host/CLI/local-session authority. `ProjectAgents` and `TicketTracker` are suggest-only in MVP (promote fails closed with a next check). Cross-root writes require explicit confirmation. Schema remains `schemaVersion: 1`; proposal DTO is API-only.
- Why: Mixed Ask sessions (Metra product scars + personal-root ideas) were dumping into Metra Future Development; Capture v1 could not split or write registered project parking lots without Cursor hand-placement.
- See: `docs/Shipped.local.md` (Capture Inbox v2), `scripts/private/Capture.ps1`, plan `capture_inbox_v2_d3ef2d89`, prior Ask ideas may cross products Decision
- Explicit non-goals: no auto-promote; no silent cross-root; no invented projects; no remote rewrite of tracked AGENTS/`Decisions.md`; no Capture-to-AGENTS write in MVP; no iSupport writes from Capture; no LLM auto-segmentation as the required path

## 2026-08-08 - Ladder 2 Ask evidence contract closed

- Decision: Ladder **2** Ask evidence contract and grounded-answer semantics is **closed**. Shipped: `AskEvidence.ps1` (`New-MetraAskEvidenceItem` / `New-MetraAskEvidencePack` / `Get-MetraAskEvidenceQuality` / answer semantics), structured context with flat aliases, limits 6/400/2400, honesty short-circuits before pack/engine, engine-path `answered=true` only when `answerType=grounded`, none skips engine, dual scrub, Ops `/api/ask` forwards `answerType` / `evidenceQuality` / `nextStep`, Cursor `buildPrompt` + Ollama OpenAI-compat evidence ceilings. Deven freeze/send, Ollama pin swap, image intake, iOS, and cross-product Capture remain parked.
- Why: Required Layer A Pester (`L2 *`) and operator smoke (Metra purpose grounded/adequate; Orion live provisional/thin without inventing alert counts; ticket id bounded, no full brief dump) passed 2026-08-08.
- See: `docs/Shipped.local.md` (Ask evidence contract), `scripts/private/AskEvidence.ps1`, `scripts/private/Snapshot.ps1`, plan `ask_evidence_polish_269fe289`

## 2026-08-08 - Ladder 2 Ask evidence contract unparked (active)

- Decision: Ladder **2** is **Active** as **Ask evidence contract and grounded-answer semantics** (code harness): structured context (`route` / `evidence` / `continuity` / `capability`), mechanical `Get-MetraAskEvidenceQuality`, `answerType` invariants, dual scrub on the evidence pack, Cursor/Ollama prompt parity. **Honesty carve-out:** short-circuits (`greeting` / `observation` / `park`) stay before pack/engine and may keep `answered=true`. **Engine-path invariant:** `answered=true` only when `answerType=grounded`; `thin`/`none` never grounded. Deven freeze/send, Ollama pin swap, image intake, iOS, and cross-product Capture remain parked. Done-when requires Layer A Pester and operator smoke before Future-Dev Done.
- Why: Honesty (ladder 1) closed 2026-08-08; the remaining Ask weakness is thin context and missing mechanical quality gates - not model shopping.
- See: plan `ask_evidence_polish_269fe289`, prior Phase 0 Decision 2026-08-06, `docs/Shipped.local.md` (evidence polish)

## 2026-08-08 - Ask desk honesty S05-S08 closed (circuit breakers)

- Decision: Ladder **1** Ask desk honesty hotfixes (S05-S08) are **closed**. Fixes live in `Get-MetraDeskAskResult` short-circuits (greeting / observation / park) before `Invoke-MetraAskEngine`, plus UTF-8 body+journal chain, residual `Repair-MetraAskWritePromise`, Ops UI non-route kinds, and thin prompt parity. Do **not** implement `Get-MetraAskEvidenceQuality` / answerType here - that remains ladder **2** (parked). No Ollama pin swap for honesty.
- Why: Operator smoke 2026-08-08 (CLI + Pester) passed S05-S08; the lies were born in fall-through + sticky route rewrite, not model quality.
- See: `docs/Shipped.local.md` (Ask honesty S05-S08), `scripts/private/Snapshot.ps1`, plan `ask_desk_honesty_d2a6c5ff`

## 2026-08-08 - Ask ladder split: honesty before full polish; Deven outside polish

- Decision: After consumer Ask activation shipped, the human ladder **splits** former "ladder 2 polish" into (1) **Ask desk honesty hotfixes** (S05-S08 - greeting theater, invented continuity, promised-write, encoding) as the **active** next bite, and (2) **Ask evidence-gated polish** (full context contract / evidence.quality / answerType) as a parked XL bite that waits on honesty. **Deven / non-coder retest is outside polish** (Arc B) - gated on honesty being good enough, not on full evidence-gated harness. Do not model-shop to fix S05-S08.
- Why: Operator closeout 2026-08-08 - engine works; major desk honesty failures block useful Ask and family retest; bundling them into XL polish delays the fixes that matter.
- See: `docs/Shipped.local.md` (honesty + evidence); `docs/Future-Development.local.md` (Outside polish Deven), `docs/Ask-Eval-Set.local.md` S05-S08, prior Consumer Ask ladder 1 closed Decision

## 2026-08-08 - Consumer Ask ladder 1 closed

- Decision: Ladder **1** (consumer-ready Ask activation) is **closed**. Recommended path remains Ollama with frozen pins `qwen2.5:3b` / `qwen2.5:7b` / `qwen2.5:14b` (Modest/Balanced/large). Accept Recommended + Settings engine switch ship as product. Residual installer packaging (private `runtimes/node` not always staged in every checkout) and any remaining Accept/UX gaps are **bugs**, not open ladder-1 product work. Do not expand the engine menu. Resume evidence-gated Ask polish as ladder **2**.
- Why: Operator closeout 2026-08-08 - `ask engine show` healthy on Ollama `qwen2.5:7b`, Accept path available, prior desk smoke proved completions. Engine work is onboarding friction only.
- See: `docs/Shipped.local.md` (Consumer-ready Ask activation), `Get-MetraAskModelPinTable`, plan `ask_activation_closeout_1f6a514c`, prior Consumer Ask multi-engine Decision 2026-08-07

## 2026-08-08 - Ask ideas may cross products and roots

- Decision: A single Ask session may produce ideas that belong in **different** durable homes (Metra Future Development, another work project, a personal-root project such as BibleQuiz, OCC, Decision Registry). Capture Inbox must support **multi-home split**: recommend one or more `suggestedProject` / `suggestedHome` values per idea, keep immutable journal lineage per candidate, and promote on affirm into the **respective** Portfolio Operations home - not only Metra `Future-Development.local.md`. Cross-root promotes require explicit operator affirm (same isolation rule as chat). Host/CLI owns disk writes; Ask remains answer-only. Do not invent unregistered projects; do not auto-promote; do not dump every idea into Metra because promote only knows Metra homes.
- Why: Phone Ask on 2026-08-08 mixed Metra product scars and BibleQuiz feature ideas in one continuity window. Hand-split worked once; operators will do this often. Capture v1 (Journal + Inbox) is correct architecture but incomplete product: home classifier prefers TicketTracker on ticket vocabulary, and `capture promote` only auto-writes Future Development / Decision Registry / OCC candidates.
- See: Ask Session Journal + Capture Inbox Decision 2026-08-05, Route something Decision 2026-08-05, Portfolio Operations Principles, `scripts/private/Capture.ps1`, `docs/Shipped.local.md` (Cross-product Ask Capture)

## 2026-08-07 - Engine work is onboarding friction only (not a launcher)

- Decision: Engine packaging (Ollama / Cursor / enterprise OpenAI-compat / llama.cpp, health, pins, updates) ships **only** when it removes consumer onboarding friction toward `engineHealthy` + ask test. Metra is a portfolio **guide** (routing, context, decisions, memory discipline, portability across agents) - not an AI runtime installer, model catalog, or Ollama/Cursor wrapper product. After ladder 1 Accept Recommended succeeds, do not expand engine surface for elegance; resume evidence-gated Ask polish and image intake instead.
- Why: Bing Future-Development review 2026-08-07: the customer problem is "I don't know where to start," not "I wish I had a nicer model manager." Competing on model hosting drifts Metra off its moat (the portfolio map).
- See: Consumer Ask multi-engine Decision above, `docs/Shipped.local.md` (Consumer-ready Ask activation; Bing review scars), Ask engine Decision 2026-08-01

## 2026-08-07 - Settings projects folders: labeled multi-root list

- Decision: Ops **Settings** edits portfolio roots as a **labeled list** (any count), not a fixed Work + Personal pair. Each root has display **label**, **path**, one **primary**, and optional **optional** (may be missing). Stable config `name` is kept when present; otherwise derived from the label. `PUT /api/settings` prefers `roots: [{ name?, label, path, primary, optional }]`; legacy `primaryPath` / `personalPath` still work. Extra registry/cloud fields are preserved when renaming by matching name or path.
- Why: Operators often need more than two parent folders (lab, cloud, secondary machine paths) and need human labels that are not tied to the old Work/Personal slots.
- See: `Save-MetraSettingsPortfolio -Roots`, `Get-MetraRoots` Label, `/api/settings`, Ops Settings Projects folders UI

## 2026-08-07 - Product updates in Settings (Metra + Ollama, no auto-apply)

- Decision: The always-on Ops Host quietly checks for **Metra** (GitHub Releases / MetraSetup.exe) and **Ollama** (winget package version) updates, caches results under `%LOCALAPPDATA%\Metra\updates-status.local.json` (24h), and may balloon once when something new appears. **Settings** shows an **Updates** row with status, **Check for updates**, and **Update Metra** / **Update Ollama** buttons. Nothing installs without that button. Metra update downloads `MetraSetup.exe` and runs `/VERYSILENT`; Ollama reuses the silent upgrade path (hidden-start marker). Developer `.git` checkouts report `dev_checkout` and refuse the Metra installer Update button (use git pull / rebuild). APIs: `GET /api/updates`, `POST /api/updates` with `{ target: metra|ollama }` (operator machine only).
- Why: Consumers need a Settings surface for installer and Ask runtime currency; Host discovery without auto-apply matches the non-technical Settings principle and avoids surprise upgrades / desk restarts.
- See: `scripts/private/Updates.ps1`, Ops Settings Updates row, `Get-MetraProductUpdates` / `Invoke-MetraProductUpdate`, silent Ollama install Decision above

## 2026-08-07 - Ollama installs silently (no Launch UI)

- Decision: `ask accept` (ladder 1a) installs Ollama **silently** and hidden. It writes the `%LOCALAPPDATA%\Ollama\upgraded` marker so the desktop app starts hidden (tray + local API only), then runs the signed `OllamaSetup.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES`. Fallback order: signed setup download (Authenticode verified, signer must match Ollama) -> `winget --silent --override "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES"` -> teach `https://ollama.com/download`. After install Metra starts `ollama serve` hidden if the API is not already up. Consumer success stays `engineHealthy` + ask test.
- Why: The default winget/desktop install pops the Ollama Launch window after setup; consumers do not need the desktop UI since Ask only uses the local API. Mirrors Ollama's own install script (upgrade marker + `/VERYSILENT`).
- See: `Install-MetraAskOllamaRuntime` / `Set-MetraAskOllamaHiddenStartMarker` in `scripts/private/AskRecommend.ps1`, `engines/ollama/README.md`, Consumer Ask ladder 1 Decision below

## 2026-08-07 - Non-technical config surfaces in Ops Settings

- Decision: Any configuration a non-technical user must set for Metra to work (portfolio project roots as a labeled multi-folder list, Cursor Ask API key when that engine is chosen, and similar consumer-facing knobs) **must** be editable in Ops **Settings**. Hand-editing `metra.config.json` or env vars remains valid for operators and IT; it is not the consumer path. Advanced/engine overrides stay under Settings Advanced. Server-side mutations stay operator-machine local (loopback or Host session token).
- Why: Installer and Documents installs leave roots pointing at thin defaults; consumers cannot be expected to edit JSON. Ask multi-engine already put Accept recommended in Settings - roots and key were the remaining gap.
- See: `Get-MetraSettingsPortfolio` / `Save-MetraSettingsPortfolio`, `/api/settings`, Ops Settings UI, Consumer Ask ladder 1 Decision above, labeled multi-root Decision 2026-08-07 above

## 2026-08-07 - Consumer Ask multi-engine activation (ladder 1)

- Decision: Ladder **1** (consumer-ready Ask) ships a **simplified engine menu**: recommended path **Ollama** (Modest/Balanced = model pin size, not separate runtimes), premium **Cursor** (Advanced; bundled private Node + prebundled sidecar when chosen - no "install Node yourself"), IT **enterprise** OpenAI-compat endpoint (hidden unless configured), Advanced escape hatch **llama.cpp** (never auto-recommended). **GPT4All** is watch/docs only - not first-class. Implementers: PowerShell-native `openai_compat` for ollama/enterprise/llamacpp; Cursor keeps `@cursor/sdk` sidecar. Recommend-first UX (Accept recommended); overrides under Advanced. Consumer success = `engineHealthy` + ask test (install runtime 1a, then pull model 1b) - not config-written alone. No silent mid-Ask engine swap; Classify stays PowerShell. Ship order: adapter + recommend + health first; Cursor packaging second; exact pin tags after smoke. ZIP/Documents folder-lose stays out of this bite. Evidence-gated polish (former ladder-1 Phase 0 Decision 2026-08-06) remains parked as human ladder **2** until consumer Ask is available.
- Why: Bing plan review (R1 8.5/10 + R2 follow-ups) favored one recommended path, one premium, one IT, one power hatch over more engines. Local Ask must not require Node; Cursor Ask must be turnkey when selected.
- See: Cursor plan `ask_multi-engine_activation_a7644e08`, `docs/Shipped.local.md` (Consumer-ready Ask activation), Ask engine Decision 2026-08-01, `scripts/private/AskEngine.ps1`

## 2026-08-06 - Ask evidence-gated polish (ladder 1 Phase 0)

- Decision: Activate ladder **1** as **Ask engine polish: evidence-gated grounded answers** (not prompt polish, not model shopping). Bing plan review approved with edits 2026-08-06. Before Phase 2 code: freeze a Deven-class Ask eval set; ship a boring context contract (`route` / `evidence` / `continuity` / `capability`); compute `evidence.quality` in code via `Get-MetraAskEvidenceQuality` (`adequate|thin|none`, plus capability `degraded` path); enforce response invariants (`answered=true` only when `answerType=grounded`; thin/none never grounded; provisional may guide but not claim completion); dual scrub (pre-engine pack and pre-journal); Classify remains authoritative (Ask may enrich, must not silently override primary stop). Journal continuity is not factual evidence unless marked. Live system claims require bound route/tool evidence. Ollama, installer Node (1b), Ask image intake (1c), iOS voice (1d), Host apply from Ask, G3/G5 full fixtures, and cross-agent storytelling stay deferred. No material scars rejected this bite.
- Why: Ask already routes and degrades; the thin context bag is the bottleneck. Harness quality and measurable gen-verify beat model swaps (aligns with Ollama/SLM scar and Karpathy gen-verify crosswalk).
- See: Cursor plan `ask_engine_polish_b9dd3dc1`, `docs/Shipped.local.md` (Ask honesty + evidence-gated polish), Ollama/SLM scar above, Ask engine Decision 2026-08-01, Ask Ops secrets scrub, [Agentic-Maturity.md](Agentic-Maturity.md) (Metra Ops Ask)

## 2026-08-06 - Ask Ops secrets scrub (defense in depth)

- Decision: Ship code-path secrets scrubbing on the Ops Ask path. PowerShell is authoritative (`Invoke-MetraAskSecretsScrubText` / `Invoke-MetraAskSecretsScrubObject` in `AskSecrets.ps1`): scrub prompt and continuity context before `/v1/complete`, scrub engine responses before desk render, and scrub again at Session Journal write so raw matches are never stored. High-signal keys/tokens scrub-and-continue with `[REDACTED:<kind>]` placeholders, kind counts in the operator notice, and a heavy-redaction notice when `RedactedCharsRatio > 0.75`. PEM / private-key blocks refuse with reason `pem_private_key` and do not call the engine. Cursor sidecar mirrors the same patterns; IDE `askInChat` remains out of scope. Complements Host ProposalJail and answer-only ceilings - not prompt theater.
- Why: Users paste credentials into Ask; journal and recall re-entry were the long-term leak surface. False-positive budget must spare ticket ids and short git SHAs used constantly in ops workflows.
- See: [SECURITY.md](../SECURITY.md) (Ask secrets scrub), `scripts/private/AskSecrets.ps1`, `scripts/private/Snapshot.ps1`, `scripts/private/AskEngine.ps1`, `engines/cursor/server.mjs`, Future-Development ladder 1a

## 2026-08-06 - Karpathy gen-verify loop (preferred crosswalk)

- Decision: Prefer [Loop Engineering, Karpathy-Style: The Gen-Verify Loop](https://www.aibuilderclub.com/blog/loop-engineering-karpathy) as the operator-facing Karpathy / loop-engineering decode. Map leash → verifier, gen-verify speed → cheap checks, autonomy slider → Ceiling + open/closed loop forms. Execution path stays Best path **G1** (goal-judges) then G2/G3 - not a new product. Explicitly **not** planned: AutoResearch / bilevel meta-search clones (train.py experiment runners). Fold the crosswalk into [Agentic-Maturity.md](Agentic-Maturity.md); park the URL under Future-Development Best path.
- Why: Operator compared articles; gen-verify matches Metra governance better than research-meta write-ups and reduces "do we have the Karpathy loop?" confusion.
- See: [Agentic-Maturity.md](Agentic-Maturity.md) (Karpathy gen-verify), `docs/Future-Development.local.md` (Best path), prior Agentic maturity / Best path entries

## 2026-08-06 - Ops composer copy (collaborate, not block)

- Decision: Shared composer copy uses collaborative Metra voice without repeating one slogan. Heading: **Where should we start?** Quiet narration: **Clear for now. Toss me an idea whenever.** Busy: **One item ready for review - discuss it, or type what you're thinking.** (plural: discuss one). Placeholder: **Idea, question, or rough draft…** Do not use blocker phrasing such as "What's in the way?"
- Why: Operator feedback - negative framing undercuts encourage-first presence; repeating "move forward" across heading/narration/placeholder reads as slogan, not desk partnership.
- See: Ops presence-first correction below, [ops/README.md](../ops/README.md)

## 2026-08-06 - Ops presence-first correction (shared composer)

- Decision: Refine the three-layer Ops desk after operator phone review. **Presence comes before queue hierarchy.** On the primary desk, Metra's mark and one truthful first-person observation lead into a single shared composer. The composer keeps one draft and exposes explicit **Ask** and **Put somewhere** actions; the button selects the destination, so Ask and Place still use separate APIs, ledgers, and success conditions. Attachments remain Put-somewhere-only until Ask image intake ships. Attention follows as a compact expandable count on mobile and an expanded surface by default on wider screens. Ask remains visible first even when items are waiting; workload must not bury portable cognition. Counts support Metra's presence instead of replacing it.
- Why: The first three-layer implementation was architecturally correct but overfit an operations dashboard. On a phone, Attention pushed the operator's primary use - bouncing ideas with Metra that may become work later - below the fold and made the persona feel like queue chrome. UI review showed that "Attention promotes without hiding Ask" was not satisfied on mobile.
- See: Ops desk three-layer model below, [ops/README.md](../ops/README.md), [Brand.md](Brand.md) (desk presence mark), Future-Development presence / voice bites

## 2026-08-06 - Ops desk three-layer model

- Decision: Metra Ops is one desk experience built from three layers:
  1. **Awareness** - shared desk chrome that states countable truth, scan recency, and quiet/busy narration.
  2. **Work surface** - separate native systems for visible work and not-yet-visible work. Attention is work already visible. Ask is work not visible yet, or not ready to become work.
  3. **Motion** - quiet handoffs that move context between surfaces without merging stores or lifecycles (Discuss, Capture, Put somewhere, Keep in view). Motion is not automation or "go do the thing."
  Attention, Ask, and Place/Capture remain separate systems. Metra does not use a single Observation Desk inbox, shared ledger, or unified lifecycle for sensors, conversations, and routing recommendations. The UX should feel like one stop because the awareness strip and handoff actions are shared. Success conditions differ: Attention succeeds when the operator knows what deserves action; Ask when they understand the situation better; Route/Place when Metra recommends where something belongs without creating it automatically. Route belongs to Motion, not the Layer 2 work surface - recommendation-only intake. Design priority: optimize for transitions, not static pixel hierarchy.
- Why: Bing/Metra design review after Ops soft-gap work; operator needs both flow orientation and phone cognition without merging ledgers.
- See: [ops/README.md](../ops/README.md), [Brand.md](Brand.md) (desk presence + awareness strip), Ask Session Journal + Capture Decision 2026-08-05, Attention memory Decision 2026-08-05

## 2026-08-06 - Ask continuity soft gaps (summarization + episodic recall)

- Decision: Ship the memory-article soft gaps for Ops Ask without inventing a Universal Memory Engine. (1) **Session summarization** - when a Journal session exceeds keep-recent (default 4) or a char budget, build an extractive summary of older turns and keep recent turns verbatim; inject as labeled Ask-engine context (especially on new engine session / Resume / sidecar revive). (2) **Episodic recall** - deliberate only: `.\metra.ps1 ask get|recall`, `GET /api/ask/journal?sessionId=` / `?q=`, Ops Recent **Resume** and **Recall into Ask** (`recallSessionId` on `POST /api/ask`). Capture Inbox still never auto-loads into Ask or routing. Vectors stay deferred (Bucket E).
- Why: Operator asked to implement soft gaps now with Ops as the focus; continuity after desk/engine restart and "what did we discuss" needs are already useful.
- See: [Agentic-Maturity.md](Agentic-Maturity.md) (memory stores crosswalk), [ops/README.md](../ops/README.md), Memory stores alignment 2026-08-06, Ask Session Journal + Capture Decision 2026-08-05

## 2026-08-06 - Memory stores alignment (no product change)

- Decision: Confirm Building Agentic AI [Giving Your Agent Memory](https://buildingagenticai.com/blog/giving-your-agent-memory/) against existing Metra homes. The article's four/five stores map to buffer (in-thread), Journal/Attention (episodic), OCC (preferences), and deferred vectors (semantic) - **not** one memory feature. Keep Portfolio Operations Principles and Ask Session Journal + Capture Inbox unchanged: no Universal Memory Engine; Capture never auto-loads into Ask/routing; promote on affirm; vectors never replace `.\metra.ps1 routing`. Crosswalk only in [Agentic-Maturity.md](Agentic-Maturity.md) under AGENT **N**.
- Why: Operator check after prior memory work; article validates the split rather than demanding a new store.
- See: Ask Session Journal + Capture Decision 2026-08-05, Portfolio Operations Principles, [Agentic-Maturity.md](Agentic-Maturity.md) (memory stores crosswalk), Future-Development Bucket E (memory soup / vectors-as-map)

## 2026-08-06 - Production readiness checklist crosswalk

- Decision: Fold Building Agentic AI [The AI Agent Production Readiness Checklist](https://buildingagenticai.com/blog/ai-agent-production-readiness-checklist/) into [Agentic-Maturity.md](Agentic-Maturity.md) as a **crosswalk only** (not a second ladder, not an Ops score): twelve checks in five bands (Scope, Authority, Proof, Operations, Outcome); gate = named answerer + artifact; do not average greens; hard blocks (data access, cost ceilings, security review, deployment ownership) vs compensating controls with retire dates. Map checks to Metra homes (Host write gates, `verify`/G5 eval, G3 traces, G4 caps, AGENTS runbooks, named operator ownership). Use the board when raising autonomy or claiming production-ready; keep risk-proportional for answer-only Ask.
- Why: Reinforces Metra "visibility not vanity," fail-closed / Host authority, and Best path G3-G5 without inventing a readiness percentage that outvotes one red.
- See: [Agentic-Maturity.md](Agentic-Maturity.md) (Production readiness checklist), `Future-Development.local.md` (Best path G3-G5 footnotes), prior AGENT / Best path Decisions

## 2026-08-06 - Ollama / SLM system-bottleneck scar

- Decision: Attach Building Agentic AI [When the Small Language Model Isn't the Bottleneck](https://buildingagenticai.com/blog/small-language-model-bottleneck/) as the design scar for Future-Development ladder **1** (Ask engine polish / Ollama swap). After a local model clears an early faithfulness + safety screen, prefer fixing routing, context assembly, realistic eval language, and **code-path** refusals (Host apply, secrets scrub, honest degrade) over repeated model swaps. Non-negotiable guardrails do not rely on the SLM abstaining. Ollama stays one engine behind `GET /health` + `POST /v1/complete`; do not implement until the bite is activated and Bing reviews the plan.
- Why: Operator asked to park the article on the future Ollama path; the piece matches Metra's route-first / harness-over-model stance and warns against blaming generation for system failures.
- See: `docs/Future-Development.local.md` (ladder 1, F2 Ollama swap scar), Ask engine Decision 2026-08-01, [Agentic-Maturity.md](Agentic-Maturity.md) (Metra Ops Ask)

## 2026-08-06 - Voice Ask scar (iOS listen mode)

- Decision: Attach Building Agentic AI [Why Voice AI Agents Are Harder Than Chatbots](https://buildingagenticai.com/blog/voice-ai-agents-harder-than-chatbots/) as the design scar for Metra's parked **iOS voice + listen** path (hands-free Ask while driving). Treat voice as a real-time, lossy, single-pass medium - not "Ask chatbot + microphone." Required scars when activated: ~1s streamed STT/Ask/TTS budget, barge-in, noisy-ASR confirmation before irreversible actions, silence/turn-taking, warm handoff into desk Capture/Attention (not contact-center SIP/ACD). Voice remains Ask-class; Host still gates durable writes. Do not build native voice until the parked iOS bite is activated and Bing reviews the plan.
- Why: Operator asked for full voice/listen on iOS for drive-time use; the article names the failure modes that kill demos that ignore the clock and interruptions.
- See: `docs/Future-Development.local.md` (Metra iOS + ladder 1d), [Brand.md](Brand.md) (presence `listening`/`speaking`), Ask Session Journal + Capture Decision 2026-08-05

## 2026-08-06 - Ticket-first watch desk write ladder

- Decision: Metra watch intake may observe TicketTracker changes and create Attention observations while the operator is away. The write ladder is: (1) Attention observation, (2) local draft/note only (opt-in), (3) iSupport recommendation only after operator affirmation, (4) post/resolve/status only after explicit operator review, (5) Live/prod implementation remains outside watch automation. Ticket watch items are observations, not task status. Attention remains continuity memory, not a work-management system. Dismissal stays sticky until the evidence signature changes (ticket Updated timestamp or Status). Ownership: TicketTracker = facts about tickets; Metra = what to notice next. Watch intake code and Attention live in Metra. TicketTracker stays sensor + ticket-ops CLI. Phase 2 affirm UX (Metra) must call TicketTracker `recommend` - no parallel iSupport writer in Metra. Maturity: separate scorecard **Metra ticket watch intake** (Target L3 intake; loop form turn-based CLI / time-based Snapshot; not L4/L5 theater) from **TicketTracker ticket-ops** (L3 turn-based).
- Why: Operator asked Metra to watch tickets for issues without creating an unattended help desk. Separating intake from ticket mutation keeps durable writes gated and maturity scores honest.
- See: [Agentic-Maturity.md](Agentic-Maturity.md) (Metra ticket watch intake), `Future-Development.local.md` (F3.x), `.\metra.ps1 watch tickets`, Attention memory Decision 2026-08-05

## 2026-08-06 - AGENT crosswalk and reversibility in maturity model

- Decision: Fold Building Agentic AI [What Counts as Agentic AI](https://buildingagenticai.com/blog/what-counts-as-agentic-ai/) into [Agentic-Maturity.md](Agentic-Maturity.md) as crosswalk only (not a second ladder): AGENT letters (A/G/E technical; N/T deployable), external autonomy 0-5 vs Metra L1-L6 map with explicit "do not equate numbers" warning, and **reversibility routing** (easy-to-undo runs free; irreversible pauses for operator/Host - agent proposes, person disposes). Optional scorecard fields: Reversibility, AGENT notes. Park soft follow-ons in Future-Development: **G4** step/cost caps (runaway loop fence), **G5** ops playbook eval sets (destination + route) - after G1 prove; do not jump Best path queue.
- Why: Article aligns with Metra "higher is not always better" and write ceilings; crosswalk prevents ladder-number confusion and names the reversibility pattern already embodied in Propose-Confirm-Apply.
- See: [Agentic-Maturity.md](Agentic-Maturity.md), `Future-Development.local.md` (Best path footnotes G4/G5), prior Best path / Agentic maturity entries

## 2026-08-06 - Best path closes Agentic Engineering gaps

- Decision: After comparing Metra to System Design One [Agentic Engineering](https://newsletter.systemdesign.one/p/agentic-engineering), park a sequenced **Best path** in Future-Development (Arc G): **G1** goal-judges for incomplete L5 playbooks (first); **G2** AGENTS.md as code (lean, human-curated, Makefile discipline); existing procedure skills spike after G2; **G3** agent session tracing last (retrieve Cursor/transcripts before new SaaS). Shared hard offs: skills marketplace, LangSmith-as-product, Ops maturity %, auto-promote from traces. Metra stays ahead on institutional routing and write ceilings; Best path closes goal-judge reliability, config hygiene, and provable L6 - not framework chasing.
- Why: Operator asked to be at Metra's best; gap close must stay sequenced and demotable vs Arc A.
- See: `docs/Future-Development.local.md` (Best path), [Agentic-Maturity.md](Agentic-Maturity.md), agent trends glean entry

## 2026-08-06 - Agentic maturity loop forms by exit

- Decision: Add **forms of loops (by exit)** under L5/L6 in [Agentic-Maturity.md](Agentic-Maturity.md): turn-based (closes on operator), goal-based (closes on judge/check), time-based (closes on clock), proactive (re-arms on events). Not new maturity levels - exit vocabulary for control loops. Rule: pick the loop by its exit, not its trigger; do not grant L5 for timer exits or human skim. Goal-based is the default shape for claiming L5. Proactive stays high-ceiling (safety/policy) and is refused for unsupervised systems-of-record writes without an allowlist. Optional scorecard field `Loop form`. Source: operator TikTok glean (Claude Code agentic loops / forms of loops); interim screenshots under operator `AI Work` drop folder.
- Why: Starting loops is over-taught; stopping them is the governance scar. Exit taxonomy prevents `/loop` vs `/goal` confusion from inflating maturity scores.
- See: [Agentic-Maturity.md](Agentic-Maturity.md) (Forms of loops), prior Agentic maturity entries in this file, `Future-Development.local.md` (Ask image intake interim path)

## 2026-08-06 - Agentic maturity Bing review scars

- Decision: Keep [Agentic-Maturity.md](Agentic-Maturity.md) as workflow governance (not AI prestige). Fold Bing review additions without new levels: (1) **Evidence quality** annotation on scorecards (`weak` / `adequate` / `authoritative`) - tool available is not tool trusted; no L3a/L3b. (2) **Ceiling reason** (`policy` / `safety` / `compliance` / `cost` / `technical` / `none`) so ceilings are not ambiguous later. (3) **On hard stop** recovery triplet for L5/L6 (what failed, where evidence, next operator action) so fail-closed is operational. Reaffirm: capability vs control split; institutional routing as L2; fail-closed required for L5; durable writes separated from maturity / Propose-Confirm-Apply; higher is not always better.
- Why: Review confirmed gaming resistance and governance fit; the three additions prevent forgotten ceiling intent, weak single-signal "grounding," and shrug-and-return validation theater.
- See: [Agentic-Maturity.md](Agentic-Maturity.md), prior Agentic maturity model entry in this file

## 2026-08-06 - Agentic maturity model (workflow completeness)

- Decision: Adopt [docs/Agentic-Maturity.md](Agentic-Maturity.md) as the shared **agentic maturity** reference for portfolio workflows. Levels L1-L6 (Basic, Router, Tool calling, Multi-agent, Autonomous check, Loop engineering). L1-L4 are capability layers; L5-L6 are control loops. Completeness means Current meets a **declared Target** with that level's required gates - not "everything is L6." Institutional routing (Metra `routing` / sticky primary) counts as L2. Durable writes stay operator- or Host-gated unless a workflow documents unsupervised authority. Agents use scorecards (Current / Target / Gaps / Completeness) when modeling current or future development; prefer gap lists over portfolio-wide percentages. Do not add a maturity score strip to Ops health (visibility, not vanity metrics). Homes cheat sheet gains **How mature?** -> `docs/Agentic-Maturity.md` (design metric, not a fourth marketing triangle leg).
- Why: Workflows needed a shared vocabulary and completeness metric for agentic design without inventing a second health dashboard or equating long chats with loop engineering.
- See: [Agentic-Maturity.md](Agentic-Maturity.md), [Context-Routing.md](Context-Routing.md), Portfolio Operations Principles in this file, `AGENTS.md`

## 2026-08-05 - Ask Session Journal + Capture Inbox

- Decision: Ask produces two artifacts only - **Session Journal** (canonical conversation evidence in `docs/ops-ask-log.local.json`) and **Capture Inbox** (thin portfolio intake in `docs/ops-capture.local.json` that references journal/place evidence via immutable `derivedFrom`). Do not invent a Universal Memory Engine or merge OCC + Decision Registry + Decisions + Future Development. Journal stores chrome-stripped operator-facing answers with `sessionId`, `turnIndex`, `origin`, and `client` (`X-Metra-Client`). Capture stores framing + lineage pointers - never a second full transcript. Capture is never auto-loaded into routing, ranking, classification, or Ask prompts. Observation is cheap (Ask-class journal/capture writes from desk/phone/iOS); governance is deliberate (promote on affirm into an existing Portfolio Operations home via CLI/Host - Future Development append is local; OCC/Decision Registry stay candidate-only; tracked policy/AGENTS stay Host/CLI). Keep in view (Attention Hold) is distinct from Save for portfolio (Capture). Cap/rotate is a recent continuity window - not permanent omniscience. Prefer `.\metra.ps1 ask` / `.\metra.ps1 capture` over inventing cross-chat recall. Phone must not write `Decisions.md` / OCC render / AGENTS directly.
- Why: Thin ask log could reconstruct neither the conversation nor the idea. Operators need remember + save without collapsing intake into always-on memory or collapsing observation into governance.
- See: `scripts/private/Capture.ps1`, `Add-MetraDeskAskEntry`, `/api/ask` + `/api/capture*`, [ops/README.md](../ops/README.md), [Customizing-Metra.md](Customizing-Metra.md), `AGENTS.md`, [SECURITY.md](../SECURITY.md)
- Future: native Metra iOS Ask+Capture client against the same HTTP contracts (parked in Future-Development.local.md); voice + listen design scar in Decisions 2026-08-06 Voice Ask scar; cross-product / multi-home Capture promote in Decisions 2026-08-08 and Future-Development Cross-product Ask Capture (ladder 2b)

## 2026-08-05 - Route something (portfolio landing zone)

- Decision: Route Something is Metra's landing zone. It accepts work in whatever form it arrives (text, clipboard paste, path refs, file upload to local quarantine) and recommends a durable home without creating one automatically. Classify / Handoff is retired from the Ops UI; `Get-MetraDeskHandoff` remains for Ask internals. Ask shows a quiet Where chip only when the route is weak or ambiguous, with optional "This belongs in…" corrections that create Decision Registry candidates and place memory. Recommendation cards teach with Recommended home, Why, What happens there, and Your move (Copy / Keep in view / affirm for learning). Keep in view maps to Attention Hold. Place learning stores confirmations/corrections in `docs/ops-place.local.json` and enriches Why on later routes. When `bindTailscale` is on, Ops orchestrates Tailscale Serve so the share URL is HTTPS (secure context for phone clipboard); Serve is not required to run Metra; Funnel stays out of scope. Quarantine uploads are Ask-class reach; durable homes stay Host-gated.
- Why: Operators shove ticket text, screenshots, and notes at Metra from phone-over-Tailscale - Classify was builder language, text-only intake felt fake, and plain HTTP blocked clipboard APIs.
- See: `scripts/private/Place.ps1`, `scripts/private/OpsServe.ps1`, `scripts/private/OpsBinding.ps1`, Ops Route panel, [ops/README.md](../ops/README.md), [SECURITY.md](../SECURITY.md)

## 2026-08-05 - Attention card copy is plain by default

- Decision: Next attention headlines, whyNext, resolveCopy, and doneWhen use plain language for every desk mode. Advanced desk reveals technical detail (original content, command, path, type/confidence meta). General mode stays action-first: what is wrong, why now, what to do.
- Why: Default Ops copy assumed CLI/git fluency and buried the next step under enums and meta tags - the desk is for operators who may not be technical.
- See: `Get-MetraAttentionPlainSummary`, `Get-MetraAttentionWhyNext`, Ops AttentionCard, [ops/README.md](../ops/README.md)

## 2026-08-05 - Open in editor is a desk-process launch, not a browser trick

- Decision: `POST /api/open` launches the operator's editor from the desk process. Preference `editorCommand` accepts `auto` (Cursor, then VS Code, then Windows default), `cursor`, `code`, `system`, or a full executable path; default is `auto`. `editorCommand` may be a custom executable path intentionally (not limited to cursor/code/system); a missing custom path falls back to Windows default. Path must be an existing folder inside a configured root or the Metra home (`Test-MetraPathWithinRoot`). Locality: deny Serve proxying, allow loopback, allow validated `X-Metra-Local-Session`, then own-IP match as supplemental. UI order stays bridge, then `/api/open`, then clipboard (with an `execCommand` fallback for plain-http origins).
- Why: Clipboard-only degrade was the whole feature in a browser, and the async clipboard does not exist on non-secure share URLs, so Open in editor silently did nothing. Identity signals beat brittle IP ownership for MagicDNS; a genuinely remote peer still cannot spawn processes.
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

## 2026-08-11 - Setup regenerates context pack and self-doc as a pair

- Decision: `.\metra.ps1 setup` / `Initialize-Metra` runs `Update-MetraSelfDocumentation` immediately after `Export-MetraContextPack`, returns `SelfDocumentation` / `Proposal` / `Tasks` on the result object, and declares the step inventory via `Get-MetraSetupTasks`. Setup also ensures the proposal store root exists (`Get-MetraProposalStoreRoot`). New setup capabilities should extend the task list rather than growing an ad-hoc god function.
- Why: Context pack without self-doc leaves Overview/canvas stale after onboarding; pairing them keeps "known-good checkout" trustworthy for adoption.
- See: `scripts/private/Setup.ps1`, `docs/Context-Routing.md`

## 2026-08-11 - Self-doc documents live routing behavior

- Decision: `.\metra.ps1 selfdoc` verifies standing sample asks with `Get-MetraRoutingAmbiguity` (present projects only). Featured order comes from `routing.featuredProjects` and/or project `featured: true` - not a hard-coded list in `SelfDocumentation.ps1`. Also writes `docs/selfdoc-routing-examples.json` as a living validation suite (ticket id, home fallback, verified asks). Overview and canvas show why (ticket-id / trigger-phrase / home-default / ...) so adoption docs cannot claim routes the engine will not take.
- Why: Registry-only examples drift from ticket precedence and home-first routing; behavior docs keep Overview/canvas trustworthy as the intelligence layer evolves.
- See: `scripts/private/SelfDocumentation.ps1`, `docs/Context-Routing.md`, `docs/selfdoc-routing-examples.json`
- Amends: 2026-08-04 "Self-doc refresh is a required step after route changes"

## 2026-08-04 - Self-doc refresh is a required step after route changes

- Decision: `.\metra.ps1 selfdoc` regenerates standing route examples into the self-documentation canvas embed, `docs/Overview.md` markers, `docs/selfdoc-routes.json`, and the tracked canvas template. After registry trigger, purpose, or project-row changes that should appear in the explain surface, operators and agents must run `selfdoc` (or `Export-MetraSnapshot -RefreshSelfDocumentation`) - do not hand-edit the generated route table or `SELFDOC_ROUTES` embed. (Amended 2026-08-11: examples are live-routing verified; snapshot no longer refreshes selfdoc by default - see "Snapshot export stays focused".)
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
  | What happened? (Ask evidence) | Session Journal (`docs/ops-ask-log.local.json`; recent window) |
  | What should change? (intake) | Capture Inbox (`docs/ops-capture.local.json`) then promote into a home above |
  | Health? | Ops board / `audit` / `verify` / status |
  | For whom? | Project registry `serves` / `routing` / `ctx` (not people profiling) |
  | How mature? (workflow design) | [Agentic-Maturity.md](Agentic-Maturity.md) - Current/Target scorecards; not an Ops vanity score |

  Operating principles: (1) every portfolio fact has a home; (2) route before execute; (3) context is retrieved, not dumped; (4) decisions are preserved with rationale (ledger why + confidence + evidence; never invent operational why); (5) communication follows the same operating model as the tooling. Health is first-class for ops but is not a fourth marketing triangle leg. Metra overlaps portfolio management, knowledge management, and configuration-management ideas; it is an operating model for developers and agents, not a single Wikipedia discipline. Boundaries: product policy -> Decisions.md; operational scars -> Decision Registry; collaboration rhythm -> OCC; project-local guidance -> that project's `AGENTS.md`; Ask evidence -> Journal; portfolio intake candidates -> Capture (never always-on routing fuel); workflow maturity targets -> Agentic-Maturity.md + per-workflow scorecards.
- Why: Portfolio chaos is usually information with no obvious home. Naming the model keeps future features (relationships, Ops board wisdom) from inventing parallel homes or dumping wiki-scale knowledge into prompts.
- See: `README.md` (Portfolio operations homes), Why Here / For whom / Decision Registry / OCC / product-triangle entries in this file, [Agentic-Maturity.md](Agentic-Maturity.md) (2026-08-06)
- Future: see Why Here entry (relatedProjects, Ops board wisdom, and related items) - do not duplicate that list here
- Note: **How mature?** row added 2026-08-06; see Agentic maturity model entry

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

## 2026-08-05 - One workspace output; skip outputs whose Metra folder is missing

- Decision: `Update-MetraWorkspace` warns when `workspace.outputs` has more than one entry, skips any output whose `metraFolderPath` does not resolve to a folder on disk, and throws only when every output is skipped. Example rules under `.cursor/rules/*.example.mdc` ship with `alwaysApply: false`.
- Why: A dual-output local config kept writing a second `Metra.code-workspace` with `metraFolderPath: "_meta"` after the checkout renamed to `_metra`. Opening that copy left Cursor with no bound Metra folder, so agent chat would not start, and the extra file also split chat history across two workspaces. Example overlays with `alwaysApply: true` loaded sample personas into every session alongside the live overlay.
- See: `scripts/public/Workspace.ps1`, `tests/Metra.Tests.ps1`, `.cursor/rules/metra-persona.local.example.mdc`
