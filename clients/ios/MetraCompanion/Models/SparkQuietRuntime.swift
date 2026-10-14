import Foundation

/// Company-only spark-or-quiet runtime (ios-conversation-policy §7).
/// Caps restrict, never authorize. Default deny. Cursor Agent must not emit sparks.
struct QuietEpisode: Sendable, Hashable {
    let id: String
    let startedAt: Date
    var sparkEmitted: Bool
    var lastSparkAt: Date?

    static func begin(now: Date = Date()) -> QuietEpisode {
        QuietEpisode(
            id: UUID().uuidString,
            startedAt: now,
            sparkEmitted: false,
            lastSparkAt: nil
        )
    }
}

enum SparkEligibility: Sendable, Hashable {
    case eligible
    case deny(reason: String)

    var isEligible: Bool {
        if case .eligible = self { return true }
        return false
    }
}

/// Rolling-hour spark ledger + per-episode / cooldown gates.
struct SparkQuietRuntime: Sendable {
    static let cooldownSeconds: TimeInterval = 5 * 60
    static let maxSparksPerHour: Int = 3

    var quietEpisode: QuietEpisode?
    /// Timestamps of Company sparks in the rolling hour.
    var sparkTimestamps: [Date] = []
    /// Policy must be Company and silenceOk for sparks to even be considered.
    var companySilenceAllowed: Bool = false

    /// Start a quiet episode when Company silence window opens. Spark does not start a new episode.
    mutating func beginQuietEpisodeIfNeeded(now: Date = Date()) {
        if quietEpisode == nil {
            quietEpisode = QuietEpisode.begin(now: now)
        }
    }

    mutating func endQuietEpisode() {
        quietEpisode = nil
    }

    /// Caps never authorize - eligibility is separate and default deny.
    func evaluateEligibility(
        openEnergy: Bool,
        isCompany: Bool,
        now: Date = Date()
    ) -> SparkEligibility {
        guard isCompany, companySilenceAllowed else {
            return .deny(reason: "not_company_silence")
        }
        guard openEnergy else {
            return .deny(reason: "closed_energy")
        }
        guard let episode = quietEpisode else {
            return .deny(reason: "no_quiet_episode")
        }
        if episode.sparkEmitted {
            return .deny(reason: "already_sparked_this_episode")
        }
        if let last = episode.lastSparkAt ?? sparkTimestamps.last {
            if now.timeIntervalSince(last) < Self.cooldownSeconds {
                return .deny(reason: "cooldown_5m")
            }
        }
        let hourAgo = now.addingTimeInterval(-3600)
        let inHour = sparkTimestamps.filter { $0 >= hourAgo }.count
        if inHour >= Self.maxSparksPerHour {
            return .deny(reason: "hourly_cap")
        }
        // Eligible ≠ obligatory - caller may still choose quiet.
        return .eligible
    }

    /// Record a spark only after an explicit emit decision. Does not start a new quiet episode.
    mutating func recordSpark(now: Date = Date()) -> Bool {
        let gate = evaluateEligibility(openEnergy: true, isCompany: true, now: now)
        guard gate.isEligible, var episode = quietEpisode else { return false }
        episode.sparkEmitted = true
        episode.lastSparkAt = now
        quietEpisode = episode
        sparkTimestamps.append(now)
        sparkTimestamps = sparkTimestamps.filter { $0 >= now.addingTimeInterval(-3600) }
        return true
    }
}

/// Anti-flatness seam + resume (Company / open energy only).
enum SeamAuthorization: Sendable, Hashable {
    case skip(reason: String)
    case allow(kind: SeamKind)

    enum SeamKind: String, Sendable {
        case callback
        case curiosity
        case parkOrContinue
    }
}

enum OpenEnergy: Sendable {
    /// Personal topic alone is closed; exploratory unfinished thread may be open.
    static func isOpen(
        exploratoryUnfinished: Bool,
        commandOrClosed: Bool,
        personalTopicAlone: Bool
    ) -> Bool {
        if commandOrClosed { return false }
        if personalTopicAlone && !exploratoryUnfinished { return false }
        return exploratoryUnfinished
    }
}

struct SeamResumeGate {
    static func authorizeSeam(
        openEnergy: Bool,
        isCompany: Bool,
        deskStrict: Bool,
        closedCommandTurn: Bool
    ) -> SeamAuthorization {
        if deskStrict { return .skip(reason: "desk_strict") }
        if !isCompany { return .skip(reason: "not_company") }
        if closedCommandTurn { return .skip(reason: "closed_command") }
        if !openEnergy { return .skip(reason: "closed_energy") }
        return .allow(kind: .parkOrContinue)
    }

    /// Resume only from a state-supported parked thread - never invent continuity.
    static func authorizeResume(parkedThreadId: String?) -> Bool {
        guard let id = parkedThreadId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return false
        }
        return true
    }
}
