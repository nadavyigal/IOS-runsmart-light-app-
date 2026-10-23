import Foundation

/// Builds every Strava and edge-function request as a plain `URLRequest`, so tests can check the
/// fields without touching the network.
nonisolated enum StravaRequests {
    enum TokenAction: Equatable {
        case exchange(code: String)
        case refresh(refreshToken: String)
    }

    /// Strava dedupes uploads by this id, so a repeated upload of the same run is refused.
    static func externalID(forRunID id: UUID) -> String {
        "runsmart-\(id.uuidString.lowercased()).gpx"
    }

    // MARK: Edge function

    static func tokenRequest(
        _ action: TokenAction,
        functionsBaseURL: URL,
        publishableKey: String,
        supabaseAccessToken: String
    ) throws -> URLRequest {
        var body: [String: String]
        switch action {
        case .exchange(let code): body = ["action": "exchange", "code": code]
        case .refresh(let token): body = ["action": "refresh", "refresh_token": token]
        }
        var request = URLRequest(url: functionsBaseURL.appendingPathComponent("strava_oauth"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAccessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        return request
    }

    // MARK: Strava API

    static func upload(
        draft: StravaActivityDraft,
        gpx: Data,
        accessToken: String,
        boundary: String = "RunSmartBoundary-\(UUID().uuidString)"
    ) -> URLRequest {
        var form = MultipartForm(boundary: boundary)
        form.addField("data_type", "gpx")
        form.addField("activity_type", "run")
        form.addField("sport_type", "Run")
        form.addField("name", draft.name)
        if let notes = draft.notes, !notes.isEmpty { form.addField("description", notes) }
        form.addField("external_id", draft.externalID)
        form.addFile("file", filename: draft.externalID, contentType: "application/gpx+xml", data: gpx)

        var request = URLRequest(url: StravaConfig.apiBaseURL.appendingPathComponent("uploads"))
        request.httpMethod = "POST"
        request.httpBody = form.body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func uploadStatus(uploadID: Int, accessToken: String) -> URLRequest {
        var request = URLRequest(url: StravaConfig.apiBaseURL.appendingPathComponent("uploads/\(uploadID)"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// A run with no usable GPS line: created as a manual activity.
    static func manualActivity(draft: StravaActivityDraft, accessToken: String, timeZone: TimeZone = .current) -> URLRequest {
        var fields: [(String, String)] = [
            ("name", draft.name),
            ("sport_type", "Run"),
            ("start_date_local", localStartString(draft.startedAt, timeZone: timeZone)),
            ("elapsed_time", String(draft.elapsedSeconds)),
            ("distance", String(Int(draft.distanceMeters.rounded())))
        ]
        if let notes = draft.notes, !notes.isEmpty { fields.append(("description", notes)) }
        var request = URLRequest(url: StravaConfig.apiBaseURL.appendingPathComponent("activities"))
        request.httpMethod = "POST"
        request.httpBody = Data(formEncoded(fields).utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func deauthorize(accessToken: String) -> URLRequest {
        var request = URLRequest(url: StravaConfig.deauthorizeURL)
        request.httpMethod = "POST"
        request.httpBody = Data(formEncoded([("access_token", accessToken)]).utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: Encoding helpers

    /// Strava reads `start_date_local` as a wall-clock time, written with a trailing Z.
    static func localStartString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }

    static func formEncoded(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }
}

nonisolated struct MultipartForm {
    let boundary: String
    private var data = Data()

    init(boundary: String) { self.boundary = boundary }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, contentType: String, data fileData: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    /// The finished body, with the closing boundary.
    var body: Data {
        var result = data
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ text: String) {
        data.append(Data(text.utf8))
    }
}
