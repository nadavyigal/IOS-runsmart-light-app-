import Foundation

nonisolated protocol StravaTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionStravaTransport: StravaTransport {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StravaError.malformedResponse }
        return (data, http)
    }
}

nonisolated enum StravaUploadResult: Equatable, Sendable {
    case onStrava(activityID: Int)
    /// Strava accepted the file but had not finished creating the activity after the last poll.
    case processing(uploadID: Int)
}

/// Talks to the `strava_oauth` edge function and to the Strava API. It never logs, and holds no tokens.
nonisolated struct StravaClient: Sendable {
    var transport: StravaTransport
    var functionsBaseURL: URL
    var publishableKey: String
    var sleep: @Sendable (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    /// Wait before each of the (up to) five status checks.
    static let pollDelays: [TimeInterval] = [1, 2, 4, 8, 15]

    // MARK: Tokens (through the edge function)

    func tokens(
        _ action: StravaRequests.TokenAction,
        supabaseAccessToken: String,
        previous: StravaTokens? = nil
    ) async throws -> StravaTokens {
        let request = try StravaRequests.tokenRequest(
            action,
            functionsBaseURL: functionsBaseURL,
            publishableKey: publishableKey,
            supabaseAccessToken: supabaseAccessToken
        )
        let (data, http) = try await transport.send(request)
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401: throw StravaError.unauthorized
            case 400: throw StravaError.rejected("Strava did not accept the sign-in.")
            default: throw StravaError.http(http.statusCode)
            }
        }
        struct Response: Decodable {
            var accessToken: String
            var refreshToken: String
            var expiresAt: Double
            var athleteId: Int?
            var athleteName: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(Response.self, from: data),
              !response.accessToken.isEmpty, !response.refreshToken.isEmpty else {
            throw StravaError.malformedResponse
        }
        return StravaTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date(timeIntervalSince1970: response.expiresAt),
            athleteID: response.athleteId ?? previous?.athleteID,
            athleteName: response.athleteName ?? previous?.athleteName
        )
    }

    // MARK: Upload

    /// Sends the run as a GPX file and waits (briefly) for Strava to create the activity.
    @concurrent func uploadGPX(draft: StravaActivityDraft, accessToken: String) async throws -> StravaUploadResult {
        let gpx = Data(GPXBuilder.gpx(for: draft).utf8)
        let request = StravaRequests.upload(draft: draft, gpx: gpx, accessToken: accessToken)
        let (data, http) = try await transport.send(request)
        let body = try? Self.uploadDecoder.decode(UploadResponse.self, from: data)

        if !(200..<300).contains(http.statusCode) {
            if let activityID = body?.error.flatMap(Self.duplicateActivityID(in:)) {
                return .onStrava(activityID: activityID)
            }
            throw Self.error(forStatus: http.statusCode, message: body?.error)
        }
        guard let body else { throw StravaError.malformedResponse }
        if let activityID = body.activityId { return .onStrava(activityID: activityID) }
        if let message = body.error {
            if let activityID = Self.duplicateActivityID(in: message) { return .onStrava(activityID: activityID) }
            throw StravaError.rejected(message)
        }
        guard let uploadID = body.id else { throw StravaError.malformedResponse }
        return try await pollUpload(uploadID: uploadID, accessToken: accessToken)
    }

    /// Checks an upload up to five times, backing off between checks.
    func pollUpload(
        uploadID: Int,
        accessToken: String,
        delays: [TimeInterval] = StravaClient.pollDelays
    ) async throws -> StravaUploadResult {
        for delay in delays {
            await sleep(delay)
            let (data, http) = try await transport.send(StravaRequests.uploadStatus(uploadID: uploadID, accessToken: accessToken))
            let body = try? Self.uploadDecoder.decode(UploadResponse.self, from: data)
            guard (200..<300).contains(http.statusCode) else {
                throw Self.error(forStatus: http.statusCode, message: body?.error)
            }
            if let activityID = body?.activityId { return .onStrava(activityID: activityID) }
            if let message = body?.error {
                if let activityID = Self.duplicateActivityID(in: message) { return .onStrava(activityID: activityID) }
                throw StravaError.rejected(message)
            }
        }
        return .processing(uploadID: uploadID)
    }

    /// A run with no GPS line goes up as a manual activity.
    func createManualActivity(draft: StravaActivityDraft, accessToken: String) async throws -> Int {
        let (data, http) = try await transport.send(StravaRequests.manualActivity(draft: draft, accessToken: accessToken))
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(forStatus: http.statusCode, message: nil)
        }
        struct Created: Decodable { var id: Int }
        guard let created = try? JSONDecoder().decode(Created.self, from: data) else {
            throw StravaError.malformedResponse
        }
        return created.id
    }

    /// Best effort: the app forgets the tokens whether or not Strava answers.
    func deauthorize(accessToken: String) async {
        _ = try? await transport.send(StravaRequests.deauthorize(accessToken: accessToken))
    }

    // MARK: Parsing

    struct UploadResponse: Decodable {
        var id: Int?
        var error: String?
        var status: String?
        var activityId: Int?
    }

    private static var uploadDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Strava refuses a repeated `external_id` with "... duplicate of activity 123". That means
    /// the run is already there, so the id is kept and nothing is sent again.
    static func duplicateActivityID(in message: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"duplicate of[^0-9]*([0-9]+)"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else { return nil }
        return Int(message[range])
    }

    private static func error(forStatus status: Int, message: String?) -> StravaError {
        switch status {
        case 401: return .unauthorized
        case 429: return .rateLimited
        case 400..<500:
            if let message, !message.isEmpty { return .rejected(message) }
            return .http(status)
        default: return .http(status)
        }
    }
}
