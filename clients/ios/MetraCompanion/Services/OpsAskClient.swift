import Foundation

/// Phase 1: always Ops when online; fail closed when offline. URLSession is the reachability test.
struct OpsAskClient: AskClient {
    let baseURLString: String
    let deviceToken: String

    func ask(session: Session, text: String) async throws -> Message {
        let url = try Self.askURL(from: baseURLString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("ops-ios", forHTTPHeaderField: "X-Metra-Client")
        request.setValue(deviceToken, forHTTPHeaderField: "X-Metra-Device")
        request.timeoutInterval = 45

        let body: [String: Any] = [
            "prompt": text,
            "sessionId": session.sessionId,
            "client": "ops-ios",
            "clientHint": "phone",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AskClientError.decoding
            }
            guard (200..<300).contains(http.statusCode) else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                throw AskClientError.httpStatus(http.statusCode, String(raw.prefix(400)))
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AskClientError.decoding
            }
            let messageText = (json["message"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !messageText.isEmpty else {
                throw AskClientError.emptyMessage
            }
            let returned = (json["sessionId"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sessionId = (returned?.isEmpty == false) ? returned! : session.sessionId
            return Message(sessionId: sessionId, role: .assistant, text: messageText)
        } catch let error as AskClientError {
            throw error
        } catch let urlError as URLError where Self.isReachabilityFailure(urlError) {
            throw AskClientError.offline
        } catch {
            throw error
        }
    }

    /// HTTPS Ops base only; build `/api/ask` via URLComponents (no string concat, no path preflight).
    static func askURL(from baseURLString: String) throws -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AskClientError.missingOpsURL
        }
        guard
            let base = URL(string: trimmed),
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            let host = components.host,
            !host.isEmpty,
            components.user == nil,
            components.password == nil
        else {
            throw AskClientError.invalidURL
        }

        components.query = nil
        components.fragment = nil
        var path = components.path
        while path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        components.path = path.isEmpty ? "/api/ask" : "\(path)/api/ask"

        guard let url = components.url else {
            throw AskClientError.invalidURL
        }
        return url
    }

    private static func isReachabilityFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .cannotFindHost,
             .internationalRoamingOff,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}
