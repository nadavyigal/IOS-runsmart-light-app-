import Foundation

nonisolated struct StravaTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var athleteID: Int?
    var athleteName: String?
}

/// A plain, thread-safe snapshot of a run, so the upload work does not touch main-actor models.
nonisolated struct StravaTrackPoint: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var time: Date
    var elevation: Double?
}

nonisolated struct StravaActivityDraft: Equatable, Sendable {
    var runID: UUID
    var name: String
    var notes: String?
    var startedAt: Date
    var elapsedSeconds: Int
    var distanceMeters: Double
    /// One array per continuous stretch (a pause starts a new one).
    var segments: [[StravaTrackPoint]]

    var pointCount: Int { segments.reduce(0) { $0 + $1.count } }
    /// A GPX file needs a line to draw; fewer than 2 points go up as a manual activity.
    var hasRoute: Bool { pointCount >= 2 }
    var externalID: String { StravaRequests.externalID(forRunID: runID) }

    init(run: RecordedRun) {
        runID = run.id
        name = RunTitle.displayTitle(for: run)
        notes = run.notes
        startedAt = run.startedAt
        elapsedSeconds = max(1, Int(run.movingTimeSeconds.rounded()))
        distanceMeters = run.distanceMeters
        segments = RoutePointSegments.split(run.routePoints).map { segment in
            segment.map {
                StravaTrackPoint(latitude: $0.latitude, longitude: $0.longitude, time: $0.timestamp, elevation: $0.altitude)
            }
        }
    }

    init(
        runID: UUID, name: String, notes: String?, startedAt: Date,
        elapsedSeconds: Int, distanceMeters: Double, segments: [[StravaTrackPoint]]
    ) {
        self.runID = runID
        self.name = name
        self.notes = notes
        self.startedAt = startedAt
        self.elapsedSeconds = elapsedSeconds
        self.distanceMeters = distanceMeters
        self.segments = segments
    }
}

/// What to do with a run when the runner (or the auto-upload setting) asks for Strava.
nonisolated enum StravaUploadDecision: Equatable {
    case alreadyOnStrava(Int)
    case notEligible
    case uploadGPX
    case createManual

    static func decide(for run: RecordedRun) -> StravaUploadDecision {
        if let id = run.stravaActivityID { return .alreadyOnStrava(id) }
        // Garmin and Health imports already live on those platforms; sending them could duplicate.
        guard run.source == .runSmart else { return .notEligible }
        // Same bar as the "Short activity" notice.
        guard run.distanceMeters >= 100, run.movingTimeSeconds >= 60 else { return .notEligible }
        let hasLine = RoutePointSegments.drawableSegments(run.routePoints).isEmpty == false
        return hasLine ? .uploadGPX : .createManual
    }
}

nonisolated enum StravaUploadStatus: Equatable {
    case notEligible
    case ready
    case sending
    case onStrava(Int)
    case failed

    var statusLine: String? {
        switch self {
        case .sending: "Sending to Strava..."
        case .onStrava: "On Strava"
        case .failed: "Strava upload failed. Retry"
        case .notEligible, .ready: nil
        }
    }
}

nonisolated enum StravaError: Error, Equatable {
    case notConfigured
    case notSignedIn
    case notConnected
    case missingScope
    case cancelled
    case stateMismatch
    case unauthorized
    case rateLimited
    case http(Int)
    case rejected(String)
    case malformedResponse
}
