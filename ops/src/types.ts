export type DeskMode = 'general' | 'advanced'

export type NextAttention = {
  id: string
  project: string
  content: string
  kind: string
} | null

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
  updatedAt?: string | null
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
  projects: ProjectRow[]
  health: Health
  recent: AskEntry[]
  preferences: Preferences
  ask?: AskCapability
  meta: {
    version?: string
    metraRoot: string
    homeLabel: string
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
}
