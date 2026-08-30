import Foundation

struct Session: Identifiable, Hashable, Sendable {
    let sessionId: String

    var id: String { sessionId }

    static func fresh() -> Session {
        Session(sessionId: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
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
