import Foundation

/// Vision Ask contract client - always contractVersion=1 / mode=vision.
struct OpsAskClient: AskClient {
    /// Client budget above server 180s engine TimeoutSec (180 + margin).
    static let askTimeoutInterval: TimeInterval = 195
    /// Short probe timeout for Settings `/api/meta`.
    static let metaProbeTimeoutInterval: TimeInterval = 8

    let baseURLString: String
    let deviceToken: String

    init(baseURLString: String, deviceToken: String) {
        self.baseURLString = baseURLString
        self.deviceToken = deviceToken
    }

    /// - Parameter inputModality: `voice` or `text` - voice turns still use Vision + Company posture (max personality).
    func ask(
        session: Session,
        text: String,
        turnId: String,
        inputModality: String = "text"
    ) async throws -> AskReply {
        let url = try Self.askURL(from: baseURLString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("ops-ios", forHTTPHeaderField: "X-Metra-Client")
        request.setValue(deviceToken, forHTTPHeaderField: "X-Metra-Device")
        request.timeoutInterval = Self.askTimeoutInterval

        // Vision requires intent=relational. Posture Company = max personality (humor / warmth packs).
        let body: [String: Any] = [
            "contractVersion": "1",
            "mode": "vision",
            "surface": "ios",
            "intent": "relational",
            "posture": "Company",
            "message": text,
            "conversationId": session.sessionId,
            "turnId": turnId,
            "capabilities": [
                "localAssistAvailable": false,
                "durableWritesAllowed": false,
            ],
            "context": [
                "client": "ops-ios",
                "clientVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                "teachingWanted": false,
                "inputModality": inputModality,
                "personalityWanted": true,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await Self.performAskRequest(request)
            guard let http = response as? HTTPURLResponse else {
                throw AskClientError.decoding
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AskClientError.decoding
            }

            if !(200..<300).contains(http.statusCode) {
                // Stable 409 askBusy - busy/contention, never offline / timeout / contract catch-all.
                if Self.isAskBusyResponse(statusCode: http.statusCode, json: json) {
                    throw AskClientError.askBusy
                }
                let status = (json["status"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let reason = (json["reason"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if status == "unavailable" || !reason.isEmpty {
                    throw Self.mapContractFailure(reason: reason, json: json)
                }
                let raw = String(data: data, encoding: .utf8) ?? ""
                throw AskClientError.httpStatus(http.statusCode, String(raw.prefix(400)))
            }

            return try Self.parseVisionEnvelope(json: json, session: session, requestTurnId: turnId)
        } catch let error as AskClientError {
            throw error
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AskClientError.requestTimedOut
        } catch let urlError as URLError where Self.isReachabilityFailure(urlError) {
            throw AskClientError.offline
        } catch {
            throw error
        }
    }

    /// Lightweight Settings probe - maps Serve-down and Ask degradedCode without a full Ask.
    static func probeMeta(baseURLString: String) async throws -> OpsMetaProbeResult {
        let url = try metaURL(from: baseURLString)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("ops-ios", forHTTPHeaderField: "X-Metra-Client")
        request.timeoutInterval = metaProbeTimeoutInterval

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AskClientError.decoding
            }
            guard (200..<300).contains(http.statusCode) else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                throw AskClientError.httpStatus(http.statusCode, String(raw.prefix(200)))
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AskClientError.decoding
            }
            return OpsMetaProbeResult(json: json)
        } catch let error as AskClientError {
            throw error
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AskClientError.requestTimedOut
        } catch let urlError as URLError where isReachabilityFailure(urlError) {
            throw AskClientError.offline
        } catch {
            throw error
        }
    }

    /// One early-reachability retry only. Never retry after a full-budget timedOut.
    private static func performAskRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where isEarlyReachabilityFailure(urlError) {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            return try await URLSession.shared.data(for: request)
        }
    }

    /// HTTPS Ops base only; build `/api/ask` via URLComponents (no string concat, no path preflight).
    static func askURL(from baseURLString: String) throws -> URL {
        try endpointURL(from: baseURLString, pathSuffix: "/api/ask")
    }

    static func metaURL(from baseURLString: String) throws -> URL {
        try endpointURL(from: baseURLString, pathSuffix: "/api/meta")
    }

    private static func endpointURL(from baseURLString: String, pathSuffix: String) throws -> URL {
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
        components.path = path.isEmpty ? pathSuffix : "\(path)\(pathSuffix)"

        guard let url = components.url else {
            throw AskClientError.invalidURL
        }
        return url
    }

    private static func parseVisionEnvelope(
        json: [String: Any],
        session: Session,
        requestTurnId: String
    ) throws -> AskReply {
        let status = (json["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reason = (json["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if status == "unavailable" || !reason.isEmpty {
            throw mapContractFailure(reason: reason, json: json)
        }

        // Misconfig: server returned desk-legacy shape despite Vision contract request.
        let contractVersion = (json["contractVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if contractVersion.isEmpty,
           json["response"] == nil,
           (json["message"] as? String)?.isEmpty == false || json["voice"] != nil {
            throw AskClientError.visionPathUnavailable
        }

        var messageText = ""
        if let response = json["response"] as? [String: Any],
           let text = response["text"] as? String {
            messageText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if messageText.isEmpty {
            if let voice = json["voice"] as? [String: Any],
               let display = voice["display"] as? String {
                messageText = display.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if messageText.isEmpty {
            messageText = (json["message"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard !messageText.isEmpty else {
            if !reason.isEmpty {
                throw mapContractFailure(reason: reason, json: json)
            }
            throw AskClientError.emptyMessage
        }

        _ = json["diagnostics"] as? [String: Any]
        _ = (json["presentation"] as? [String: Any])?["mood"] as? String

        let corr = json["correlation"] as? [String: Any]
        let returnedCid = (corr?["conversationId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let returnedTid = (corr?["turnId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionId = (returnedCid?.isEmpty == false) ? returnedCid! : session.sessionId
        let turnId = (returnedTid?.isEmpty == false) ? returnedTid! : requestTurnId

        let envelope = json["policyEnvelope"] as? [String: Any]
        let retRaw = (envelope?["retentionClass"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let execRaw = (envelope?["executionTarget"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let retention = retRaw.flatMap { RetentionClass(rawValue: $0) }
        let execution = execRaw.flatMap { ExecutionTarget(rawValue: $0) }

        let message = Message(sessionId: sessionId, role: .assistant, text: messageText)
        return AskReply(
            message: message,
            conversationId: sessionId,
            turnId: turnId,
            retentionClass: retention,
            executionTarget: execution
        )
    }

    /// HTTP 409 + `error: askBusy` (Ops SemaphoreSlim single-flight). Not offline or retryable reachability.
    private static func isAskBusyResponse(statusCode: Int, json: [String: Any]) -> Bool {
        guard statusCode == 409 else { return false }
        let error = (json["error"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return error == "askbusy"
    }

    private static func mapContractFailure(reason: String, json: [String: Any]) -> AskClientError {
        let detail = (json["detail"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch reason {
        case "write_not_allowed":
            return .writeNotAllowed(detail.isEmpty ? nil : detail)
        case "route_boundary_violation":
            return .routeBoundaryViolation(detail.isEmpty ? nil : detail)
        case "vision_unavailable", "ops_unreachable":
            return .visionPathUnavailable
        case "cursor_auth_error":
            return .cursorAuthError(detail.isEmpty ? nil : detail)
        case "cursor_usage_limit":
            return .cursorUsageLimit(detail.isEmpty ? nil : detail)
        case "cursor_model_unavailable":
            return .cursorModelUnavailable(detail.isEmpty ? nil : detail)
        case "askBusy", "ask_busy":
            return .askBusy
        case "invalid_contract", "unsupported_contract_version",
             "engine_failure", "desk_requires_connectivity":
            return .contractError(reason, detail.isEmpty ? nil : detail)
        default:
            if reason.isEmpty {
                return .visionPathUnavailable
            }
            return .contractError(reason, detail.isEmpty ? nil : detail)
        }
    }

    /// Full-budget timeout is NOT reachability - surfaces as requestTimedOut separately.
    private static func isReachabilityFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
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

    /// Early connect-class failures eligible for one retry (never timedOut).
    private static func isEarlyReachabilityFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost,
             .dnsLookupFailed,
             .cannotFindHost,
             .networkConnectionLost:
            return true
        default:
            return false
        }
    }
}

// MARK: - Tailscale WhoIs device pair (POST /api/profile/pair)

enum OpsPairResult: Sendable {
    case paired(deviceId: String, token: String, message: String)
    case pending(requestId: String, message: String)
}

enum OpsPairError: LocalizedError {
    case invalidBaseURL
    case httpStatus(Int, String)
    case decoding
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Ops base URL is not a valid HTTPS URL."
        case .httpStatus(let code, let body):
            return "Pair failed (HTTP \(code)): \(body)"
        case .decoding:
            return "Pair response was not valid JSON."
        case .rejected(let message):
            return message
        }
    }
}

extension OpsAskClient {
    /// Pair this phone over Tailscale WhoIs; store host-minted device token in Keychain.
    static func pairWithOps(baseURLString: String, label: String) async throws -> OpsPairResult {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed),
              let scheme = base.scheme?.lowercased(),
              scheme == "https",
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else {
            throw OpsPairError.invalidBaseURL
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.isEmpty ? "/api/profile/pair" : "/\(path)/api/profile/pair"
        guard let url = components.url else { throw OpsPairError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("ops-ios", forHTTPHeaderField: "X-Metra-Client")
        request.timeoutInterval = 30
        let body: [String: Any] = ["label": label]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpsPairError.decoding }
        let rawBody = String(data: data, encoding: .utf8) ?? ""
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        // Pending approve is HTTP 202 with JSON body.
        if http.statusCode == 202 {
            let requestId = (json?["requestId"] as? String) ?? ""
            let message = (json?["message"] as? String) ?? "Pairing pending Ops approve."
            return .pending(requestId: requestId, message: message)
        }

        if !(200..<300).contains(http.statusCode) {
            let err = (json?["error"] as? String) ?? rawBody
            if http.statusCode == 403 {
                throw OpsPairError.rejected(err.isEmpty ? "Peer identity not allowlisted." : err)
            }
            throw OpsPairError.httpStatus(http.statusCode, String(err.prefix(400)))
        }

        guard let json else { throw OpsPairError.decoding }
        if (json["pending"] as? Bool) == true {
            let requestId = (json["requestId"] as? String) ?? ""
            let message = (json["message"] as? String) ?? "Pairing pending Ops approve."
            return .pending(requestId: requestId, message: message)
        }

        guard let token = json["token"] as? String, !token.isEmpty else {
            throw OpsPairError.decoding
        }
        guard DeviceTokenStore.write(token) else {
            throw OpsPairError.rejected("Paired with Ops, but Keychain could not store the device token.")
        }
        let deviceId = (json["deviceId"] as? String) ?? ""
        let message = (json["message"] as? String) ?? "Paired."
        return .paired(deviceId: deviceId, token: token, message: message)
    }
}

struct OpsMetaProbeResult: Sendable {
    let serveOk: Bool
    let serveError: String?
    let bindTailscale: Bool
    let askSelected: Bool
    let askHealthy: Bool
    let degradedCode: String?

    init(json: [String: Any]) {
        serveOk = json["serveOk"] as? Bool ?? false
        let err = (json["serveError"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        serveError = err.isEmpty ? nil : err
        bindTailscale = json["bindTailscale"] as? Bool ?? false
        let ask = json["askEngine"] as? [String: Any] ?? [:]
        askSelected = ask["selected"] as? Bool ?? false
        askHealthy = ask["healthy"] as? Bool ?? false
        let code = (ask["degradedCode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        degradedCode = code.isEmpty ? nil : code
    }

    /// Operator-facing status line for Settings (nil when healthy enough).
    var statusMessage: String? {
        if bindTailscale && !serveOk {
            let detail = serveError.map { ": \($0)" } ?? ""
            return "Tailscale Serve HTTPS is down on the Ops host\(detail). Phone Ask needs HTTPS."
        }
        if let code = degradedCode {
            switch code {
            case "cursor_auth_error":
                return "Ask engine is up but Cursor auth failed on the Ops host. Check CURSOR_API_KEY."
            case "cursor_usage_limit":
                return "Ask engine is up but Cursor usage/billing limit is hit on the Ops host."
            case "cursor_model_unavailable":
                return "Ask engine is up but the configured Cursor model is unavailable."
            default:
                return "Ask engine degraded (\(code))."
            }
        }
        if askSelected && !askHealthy {
            return "Ask engine selected but not healthy. Ops will retry Ensure on its health poll."
        }
        return nil
    }
}
