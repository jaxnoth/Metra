import Foundation

struct Session: Identifiable, Hashable, Sendable {
    let sessionId: String
    /// Monotonic turn counter for stale-route (ios-conversation-policy).
    private(set) var turnCounter: Int
    var activeTurn: ActiveTurn?
    var ephemeralEpisode: EphemeralEpisode?

    var id: String { sessionId }

    static func fresh() -> Session {
        Session(
            sessionId: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            turnCounter: 0,
            activeTurn: nil,
            ephemeralEpisode: nil
        )
    }

    /// Allocate next turnId and mark it active (call at send time).
    mutating func beginTurn(
        retentionClass: RetentionClass? = nil,
        executionTarget: ExecutionTarget? = nil
    ) -> String {
        turnCounter += 1
        let turnId = String(turnCounter)
        activeTurn = ActiveTurn(
            conversationId: sessionId,
            turnId: turnId,
            retentionClass: retentionClass,
            executionTarget: executionTarget
        )
        return turnId
    }

    mutating func clearEphemeral(reason: String = "explicit_clear") {
        ephemeralEpisode?.end(reason: reason)
        ephemeralEpisode = nil
    }

    /// Background ends the ephemeral episode and clears activeTurn so an in-flight
    /// HTTP completion cannot pass stale-route and display (network may still finish).
    mutating func invalidateOnBackground() {
        if var ep = ephemeralEpisode {
            ep.applyBoundary(
                intentLeavesRelational: false,
                policyLeavesCompany: false,
                appBackgrounded: true,
                explicitClear: false
            )
            ephemeralEpisode = ep.active ? ep : nil
        }
        // Drop the active turn correlation - late replies must not land.
        activeTurn = nil
    }
}

enum MessageRole: String, Sendable {
    case user
    case assistant
    case system
}

struct Message: Identifiable, Hashable, Sendable {
    let id: String
    let sessionId: String
    let role: MessageRole
    let text: String
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: String,
        role: MessageRole,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}
