import Foundation

/// Normative retentionClass values (ios-conversation-policy). Never CE posture aliases.
enum RetentionClass: String, Sendable, Hashable {
    case normal
    case light
    case ephemeral
    case refuse
}

enum ExecutionTarget: String, Sendable, Hashable {
    case ops
    case local
}

/// Active turn correlation for stale-route protection.
struct ActiveTurn: Sendable, Hashable {
    let conversationId: String
    let turnId: String
    var retentionClass: RetentionClass?
    var executionTarget: ExecutionTarget?
}

/// In-memory ephemeral episode (support/companionship). No durable body store.
struct EphemeralEpisode: Sendable, Hashable {
    let conversationId: String
    var startedAt: Date
    var lastActivityAt: Date
    var active: Bool
    var endReason: String?

    static let idleLimitSeconds: TimeInterval = 15 * 60

    static func start(conversationId: String, now: Date = Date()) -> EphemeralEpisode {
        EphemeralEpisode(
            conversationId: conversationId,
            startedAt: now,
            lastActivityAt: now,
            active: true,
            endReason: nil
        )
    }

    mutating func end(reason: String) {
        active = false
        endReason = reason
    }

    mutating func touch(now: Date = Date()) {
        guard active else { return }
        lastActivityAt = now
    }

    /// Normative end conditions: leave Company, leave support, 15m idle, background, clear.
    mutating func applyBoundary(
        intentLeavesRelational: Bool,
        policyLeavesCompany: Bool,
        appBackgrounded: Bool,
        explicitClear: Bool,
        now: Date = Date()
    ) {
        guard active else { return }
        if explicitClear {
            end(reason: "explicit_clear")
            return
        }
        if appBackgrounded {
            end(reason: "background")
            return
        }
        if policyLeavesCompany {
            end(reason: "leave_company")
            return
        }
        if intentLeavesRelational {
            end(reason: "leave_support")
            return
        }
        if now.timeIntervalSince(lastActivityAt) >= Self.idleLimitSeconds {
            end(reason: "idle_15m")
        }
    }
}

enum StaleRouteDecision: Sendable, Hashable {
    case accept
    case drop(detail: String)

    var isAccept: Bool {
        if case .accept = self { return true }
        return false
    }
}

enum ConversationPolicyGate {
    /// Delayed reply may show only when ids + retention/exec still match the *live* active turn.
    /// Callers must pass current session.activeTurn (not a send-time snapshot) so background
    /// invalidation (activeTurn cleared) drops in-flight completions without cancelling HTTP.
    static func staleRoute(
        responseConversationId: String?,
        responseTurnId: String?,
        responseRetention: RetentionClass?,
        responseExecution: ExecutionTarget?,
        active: ActiveTurn?,
        ephemeralEpisodeActive: Bool? = nil
    ) -> StaleRouteDecision {
        guard let active else {
            return .drop(detail: "no_active_turn")
        }
        let respCid = (responseConversationId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let respTid = (responseTurnId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !respCid.isEmpty, !respTid.isEmpty else {
            return .drop(detail: "missing_ids")
        }
        guard respCid == active.conversationId else {
            return .drop(detail: "conversationId_mismatch")
        }
        guard respTid == active.turnId else {
            return .drop(detail: "turnId_mismatch")
        }
        if let respRet = responseRetention, let actRet = active.retentionClass {
            if respRet == .ephemeral && actRet != .ephemeral {
                return .drop(detail: "retentionClass_incompatible")
            }
            if respRet == .refuse {
                return .drop(detail: "retentionClass_incompatible")
            }
            if respRet != actRet {
                return .drop(detail: "retentionClass_incompatible")
            }
        }
        // Ephemeral completion cannot land after the episode ended (e.g. background).
        if responseRetention == .ephemeral, let epActive = ephemeralEpisodeActive, !epActive {
            return .drop(detail: "ephemeral_episode_ended")
        }
        if let respExec = responseExecution, let actExec = active.executionTarget, respExec != actExec {
            return .drop(detail: "executionTarget_mismatch")
        }
        return .accept
    }
}
