import Foundation

enum AskClientError: LocalizedError, Sendable {
    case missingOpsURL
    case offline
    case invalidURL
    case httpStatus(Int, String)
    case emptyMessage
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingOpsURL:
            return "Set the Ops HTTPS URL in Settings."
        case .offline:
            return "Ops Ask is unavailable offline. LocalAssist is not answering in Phase 1."
        case .invalidURL:
            return "Ops URL is not a valid HTTPS address."
        case .httpStatus(let code, let body):
            return "Ops Ask failed (\(code)): \(body)"
        case .emptyMessage:
            return "Ops returned an empty message."
        case .decoding:
            return "Could not read the Ops Ask response."
        }
    }
}

protocol AskClient: Sendable {
    func ask(session: Session, text: String) async throws -> Message
}
