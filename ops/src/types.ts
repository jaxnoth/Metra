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
  kind?: 'greeting' | 'route'
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
  handoff?: Handoff
  note?: string
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
  recent: AskEntry[]
  preferences: Preferences
  ask?: AskCapability
  meta: {
    version?: string
    metraRoot: string
    homeLabel: string
    editor?: EditorInfo | null
  }
}

export type AskResult = {
  handoff: Handoff
  message: string
  sessionId?: string | null
  capability?: AskCapability
  engine?: string | null
  model?: string | null
  answered?: boolean
  /** Quiet Where chip when route is weak or ambiguous. */
  showWhere?: boolean
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
