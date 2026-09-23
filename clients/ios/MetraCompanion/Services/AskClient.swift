import Foundation

enum AskClientError: LocalizedError, Sendable {
    case missingOpsURL
    case offline
    case requestTimedOut
    case invalidURL
    case httpStatus(Int, String)
    case emptyMessage
    case decoding
    case writeNotAllowed(String?)
    case routeBoundaryViolation(String?)
    case visionPathUnavailable
    case cursorAuthError(String?)
    case cursorUsageLimit(String?)
    case cursorModelUnavailable(String?)
    case serveHttpsDown(String?)
    case contractError(String, String?)

    var errorDescription: String? {
        switch self {
        case .missingOpsURL:
            return "Set the Ops HTTPS URL in Settings."
        case .offline:
            return "Ops Ask is unavailable offline. LocalAssist is not answering in Phase 1."
        case .requestTimedOut:
            return "Ops Ask timed out waiting for a reply. The host may still be working - try again in a moment."
        case .invalidURL:
            return "Ops URL is not a valid HTTPS address."
        case .httpStatus(let code, let body):
            return "Ops Ask failed (\(code)): \(body)"
        case .emptyMessage:
            return "Ops returned an empty message."
        case .decoding:
            return "Could not read the Ops Ask response."
        case .writeNotAllowed(let detail):
            let suffix = detail.map { " (\($0))" } ?? ""
            return "Vision does not allow durable writes\(suffix)."
        case .routeBoundaryViolation(let detail):
            let suffix = detail.map { " (\($0))" } ?? ""
            return "Vision route boundary violation\(suffix). Report this - it is a server-side bug."
        case .visionPathUnavailable:
            return "Vision path unavailable. Check Ops / Tailscale, then retry."
        case .cursorAuthError(let detail):
            let suffix = detail.map { ": \($0)" } ?? ""
            return "Cursor auth failed on the Ops host\(suffix). Check CURSOR_API_KEY / sign-in on the desk machine."
        case .cursorUsageLimit(let detail):
            let suffix = detail.map { ": \($0)" } ?? ""
            return "Cursor usage or billing limit on the Ops host\(suffix)."
        case .cursorModelUnavailable(let detail):
            let suffix = detail.map { ": \($0)" } ?? ""
            return "Configured Cursor model is unavailable on the Ops host\(suffix)."
        case .serveHttpsDown(let detail):
            let suffix = detail.map { ": \($0)" } ?? ""
            return "Tailscale Serve HTTPS is down on the Ops host\(suffix). Phone Ask needs HTTPS."
        case .contractError(let reason, let detail):
            let suffix = detail.map { ": \($0)" } ?? ""
            return "Ops Ask contract error (\(reason))\(suffix)"
        }
    }
}

protocol AskClient: Sendable {
    func ask(session: Session, text: String) async throws -> Message
}
