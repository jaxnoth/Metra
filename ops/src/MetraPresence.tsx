/** idle = resting; listening = Ask/work in flight (pulse interchange); speaking = reserved for voice reply */
export type VoiceState = 'idle' | 'listening' | 'speaking'

/** Orthogonal to voice: route posture when waiting Attention is present */
export type AttentionPosture = 'quiet' | 'busy'

type MetraPresenceProps = {
  voiceState?: VoiceState
  /** When true, subtle route-line weight (not a count badge) */
  attentionBusy?: boolean
}

export function MetraPresence({
  voiceState = 'idle',
  attentionBusy = false,
}: MetraPresenceProps) {
  const working = voiceState === 'listening' || voiceState === 'speaking'
  const attention: AttentionPosture = attentionBusy ? 'busy' : 'quiet'
  const description =
    voiceState === 'listening'
      ? 'Metra wordmark over a three-node route - working on your question'
      : voiceState === 'speaking'
        ? 'Metra wordmark over a three-node route - answering'
        : attentionBusy
          ? 'Large Metra wordmark over a three-node route - Attention waiting'
          : 'Large Metra wordmark over a three-node route'

  return (
    <div
      className="metra-presence"
      data-voice-state={voiceState}
      data-attention={attention}
      aria-busy={working || undefined}
    >
      <svg
        className="metra-presence__logo"
        viewBox="0 0 320 118"
        role="img"
        aria-labelledby="metra-logo-title metra-logo-description"
      >
        <title id="metra-logo-title">Metra</title>
        <desc id="metra-logo-description">{description}</desc>

        <text className="metra-presence__wordmark" x="160" y="58" textAnchor="middle">
          Metra
        </text>

        <g className="metra-presence__route" strokeLinecap="round">
          <path className="metra-presence__line" d="M28 96H292" />
          <path className="metra-presence__stem" d="M160 68V96" />
          <circle className="metra-presence__terminal" cx="28" cy="96" r="7" />
          <circle className="metra-presence__interchange" cx="160" cy="96" r="8" />
          <circle className="metra-presence__terminal" cx="292" cy="96" r="7" />
        </g>
      </svg>
    </div>
  )
}
