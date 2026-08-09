export type DeskMode = 'general' | 'advanced'

export type EditCapability = 'safe' | 'unsafe' | 'git'

export type AttentionState = 'active' | 'snoozed' | 'dismissed' | 'autoClosed' | 'held'

export type AttentionConfidence = 'fresh' | 'likelyStale' | 'needsRevalidation'

export type AttentionSource = 'snapshot' | 'decision' | 'contract' | 'operator'

export type AttentionItem = {
  id: string
  key: string
  project?: string
  content: string
  detail?: string
  kind: string
  command?: string
  summary?: string
  askPrompt?: string
  doneWhen?: string
  editCapability?: EditCapability
  resolveCopy?: string
  proposalId?: string | null
  proposalStatus?: string | null
  projectPath?: string | null
  whyNext?: string
  confidence?: AttentionConfidence | string
  source?: AttentionSource | string
  state?: AttentionState | string
  evidenceSignature?: string
  firstSeenAt?: string | null
  lastSeenAt?: string | null
  lastScanMode?: string
  notRecheckedSince?: string | null
  snoozedUntil?: string | null
  closedAt?: string | null
  closedBy?: string
  note?: string
}

/** @deprecated Prefer AttentionItem; kept for nextAttention nullability. */
export type NextAttention = AttentionItem | null

export type AttentionQueue = {
  active: AttentionItem[]
  activeCount: number
  notRecheckedCount: number
  coveredKinds: string[]
  visibleCount: number
  held?: AttentionItem[]
  heldCount?: number
  holdRoutingHint?: string | null
}

export type ProjectRow = {
  name: string
  purpose: string
  present: boolean
  root: string
  status: string
  optional: boolean
  hasAgentsMd: boolean
  pinned?: boolean
  capabilities?: string[]
  serves?: string[]
  gitIsRepo?: boolean
  gitDirty?: number
  gitAhead?: number
  gitBehind?: number
  gitBranch?: string
  gitSummary?: string
  /** Relative folder holding the repo when it is not the project root. */
  gitRepoPath?: string
}

export type Health = {
  missingAgents: string[]
  missingAgentsCount: number
  gitChecked: boolean
  gitStatusLabel: string
  snapshotStale: boolean
  projectCount: number
  driftCount: number
}

export type Handoff = {
  query: string
  kind?: 'greeting' | 'route' | 'observation' | 'park'
  preview: boolean
  where: string | null
  what: string
  why: string[]
  forWhom: string[]
  next: string
  ambiguous: boolean
  runnerUp: string | null
  score: number
  note?: string | null
}

export type AskEntry = {
  id: string
  at: string
  prompt: string
  message?: string | null
  sessionId?: string | null
  turnIndex?: number | null
  origin?: string | null
  client?: string | null
  clientHint?: string | null
  handoff?: Handoff
  note?: string
}

export type AskSessionSummary = {
  id?: string
  sessionId: string
  turnCount: number
  at: string
  prompt: string
  where?: string
  origin?: string
  client?: string
  turns?: { id: string; turnIndex?: number; at?: string; prompt?: string }[]
}

export type CaptureProposal = {
  proposalId: string
  summary: string
  suggestedHome: string
  suggestedProject?: string | null
  confidence?: string
  reason?: string
  rootLabel?: string | null
  requiresCrossRoot?: boolean
  requiresHostSession?: boolean
  derivedFrom?: { type?: string; sessionId?: string; turnId?: string }
  accepted?: boolean
}

export type CaptureItem = {
  id: string
  at: string
  status: 'candidate' | 'promoted' | 'dismissed' | string
  summary: string
  body?: string | null
  source?: string
  derivedFrom?: { type?: string; sessionId?: string; turnId?: string; placeId?: string }
  suggestedHome?: string
  suggestedProject?: string
  origin?: string | null
  client?: string | null
  promoted?: { at?: string; home?: string; ref?: string } | null
}

export type Preferences = {
  deskMode: DeskMode
  attentionVisibleCount?: number
  /** auto | cursor | code | system | full executable path */
  editorCommand?: string
  updatedAt?: string | null
}

export type EditorInfo = {
  preference?: string
  kind?: string
  label?: string
}

export type AskCapability = {
  enabled: boolean
  selected: boolean
  available: boolean
  engine: string
  providerLabel?: string
  reason?: string
  model?: string
  ideInstalled?: boolean
  apiKeyPresent?: boolean
  nodeReady?: boolean
  sidecarReady?: boolean
  engineHealthy?: boolean
  runtimeReady?: boolean
  modelPresent?: boolean
  sizeBand?: string
}

export type AskEngineMenuItem = {
  id: string
  label: string
  kind: string
  disabled?: boolean
  note?: string
}

export type AskEnginePanel = {
  capability: AskCapability
  recommendation?: { summary?: string; modelPin?: string; sizeBand?: string }
  menu: AskEngineMenuItem[]
}

export type SettingsRoot = {
  name: string
  label?: string
  path: string
  rawPath?: string
  primary: boolean
  optional: boolean
  cloud?: boolean
  exists: boolean
}

export type SettingsRootInput = {
  name?: string
  label: string
  path: string
  primary: boolean
  optional: boolean
}

export type SettingsPortfolio = {
  metraRoot: string
  primaryPath: string
  personalPath: string
  hint?: string
  roots: SettingsRoot[]
  ask: { apiKeyPresent: boolean }
}

export type SettingsSaveResult = {
  ok: boolean
  rootsSaved?: boolean
  portfolio: SettingsPortfolio
}

export type ProductUpdateItem = {
  id: string
  label: string
  installed?: string | null
  available?: string | null
  updateAvailable: boolean
  canUpdate: boolean
  status: string
  message?: string | null
  channel?: string
  downloadUrl?: string | null
  releaseUrl?: string | null
}

export type ProductUpdates = {
  checkedAt: string
  anyUpdate: boolean
  metra: ProductUpdateItem
  ollama: ProductUpdateItem
}

export type ProductUpdateResult = {
  ok: boolean
  target: string
  status: string
  message?: string | null
  updates?: ProductUpdates
}

export type DeskPayload = {
  generatedAt: string
  mode: string
  stale: boolean
  gitChecked: boolean
  verifyChecked: boolean
  nextAttention: NextAttention
  /** Count of actionable attention items behind nextAttention (same brain as canvas). */
  attentionCount?: number
  /** Why the queue is empty - quick snapshot vs truly clear. */
  attentionEmptyHint?: string | null
  attention?: AttentionQueue
  projects: ProjectRow[]
  health: Health
  /** Recent conversations (session summaries - continuity window). */
  recent: AskSessionSummary[] | AskEntry[]
  captures?: CaptureItem[]
  preferences: Preferences
  ask?: AskCapability
  meta: {
    version?: string
    metraRoot: string
    homeLabel: string
    editor?: EditorInfo | null
  }
}

export type AskContinuity = {
  sessionId?: string | null
  recallSessionId?: string | null
  sessionSummary?: string | null
  recentTurns?: { turnIndex?: number | null; prompt?: string; message?: string }[]
  recallSummary?: string | null
  usedSummarization?: boolean
  summarizedTurnCount?: number
  recentTurnCount?: number
  totalTurnCount?: number
}

export type AskResult = {
  entry?: AskEntry
  handoff: Handoff
  message: string
  sessionId?: string | null
  capability?: AskCapability
  engine?: string | null
  model?: string | null
  answered?: boolean
  /** grounded | provisional | refusal | degraded | greeting | observation | park */
  answerType?: string | null
  /** adequate | thin | none */
  evidenceQuality?: string | null
  nextStep?: string | null
  /** Quiet Where chip when route is weak or ambiguous. */
  showWhere?: boolean
  /** Park short-circuit: highlight Save for portfolio (never auto-create Capture). */
  suggestCapture?: boolean
  continuity?: AskContinuity | null
  /** True when Ask scrubbed or refused secret-shaped content. */
  secretsScrubbed?: boolean
  secretsNotice?: string | null
  secretsKinds?: { kind?: string; Kind?: string; count?: number; Count?: number }[]
  secretsReason?: string | null
}

export type PlaceHomeId =
  | 'tickettracker'
  | 'decision-registry'
  | 'decisions-md'
  | 'occ'
  | 'agents-md'
  | 'keep-in-view'
  | 'future-development'

export type PlacePathRef = {
  path: string
  openPath: string
  isFile?: boolean
}

export type PlaceRecommendation = {
  ok: boolean
  error?: string
  homeId: PlaceHomeId | string | null
  homeLabel: string | null
  why: string[]
  whatHappensThere: string | null
  nextStep: string | null
  draft: string | null
  pathRefs: PlacePathRef[]
  attachments?: string[]
  learning?: { note?: string } | null
  recommendOnly?: boolean
  note?: string | null
}

export type PlaceUploadMeta = {
  id: string
  fileName: string
  contentType?: string
  size?: number
  path?: string
  at?: string
}

export type PlaceHome = {
  id: string
  label: string
  whatHappensThere: string
  draftHint: string
}
