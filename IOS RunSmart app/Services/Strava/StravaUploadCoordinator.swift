import Foundation
import Combine

/// Runs whose upload failed or is still being processed by Strava, kept for a retry on the next
/// app foreground. Only ids and timestamps are stored.
nonisolated struct StravaPendingUpload: Codable, Equatable {
    var runID: UUID
    /// Set when Strava accepted the file but had not created the activity yet.
    var uploadID: Int?
    var since: Date
}

nonisolated final class StravaPendingLedger {
    static let maximumAge: TimeInterval = 7 * 24 * 3_600

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "runsmart.strava.pendingUploads") {
        self.defaults = defaults
        self.key = key
    }

    func all() -> [StravaPendingUpload] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder.strava.decode([StravaPendingUpload].self, from: data) else { return [] }
        return list
    }

    func entry(for runID: UUID) -> StravaPendingUpload? {
        all().first { $0.runID == runID }
    }

    func upsert(runID: UUID, uploadID: Int?, now: Date = Date()) {
        var list = all()
        if let index = list.firstIndex(where: { $0.runID == runID }) {
            list[index].uploadID = uploadID ?? list[index].uploadID
        } else {
            list.append(StravaPendingUpload(runID: runID, uploadID: uploadID, since: now))
        }
        write(list)
    }

    func remove(runID: UUID) {
        write(all().filter { $0.runID != runID })
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }

    /// Entries still worth retrying, oldest first. Older ones are dropped.
    func retryable(now: Date = Date()) -> [StravaPendingUpload] {
        let fresh = all().filter { now.timeIntervalSince($0.since) <= Self.maximumAge }
        if fresh.count != all().count { write(fresh) }
        return fresh.sorted { $0.since < $1.since }
    }

    private func write(_ list: [StravaPendingUpload]) {
        guard let data = try? JSONEncoder.strava.encode(list) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
protocol StravaRunStoring {
    func storedRun(id: UUID) -> RecordedRun?
    func setStravaActivityID(_ activityID: Int, forRunID runID: UUID)
}

extension RunSmartLocalStore: StravaRunStoring {
    func storedRun(id: UUID) -> RecordedRun? {
        loadRuns().first { $0.id == id }
    }
}

/// Sends finished runs to Strava, remembers which ones are there, and retries failures quietly.
/// No error is ever shown as a blocking alert: the summary shows a one-line status instead.
@MainActor
final class StravaUploadCoordinator: ObservableObject {
    static let shared = StravaUploadCoordinator()

    private static let autoUploadKey = "runsmart.strava.autoUpload"

    @Published private(set) var statuses: [UUID: StravaUploadStatus] = [:]
    /// Default on: once Strava is connected, new runs go up without a tap.
    @Published var autoUploadEnabled: Bool {
        didSet { defaults.set(autoUploadEnabled, forKey: Self.autoUploadKey) }
    }

    private let connection: StravaConnectionService
    private let store: StravaRunStoring
    private let ledger: StravaPendingLedger
    private let defaults: UserDefaults
    private let makeClient: () -> StravaClient
    private var inFlight: Set<UUID> = []

    init(
        connection: StravaConnectionService = .shared,
        store: StravaRunStoring = RunSmartLocalStore.shared,
        ledger: StravaPendingLedger = StravaPendingLedger(),
        defaults: UserDefaults = .standard,
        makeClient: @escaping () -> StravaClient = {
            StravaClient(
                transport: URLSessionStravaTransport(),
                functionsBaseURL: SupabaseManager.functionsBaseURL,
                publishableKey: SupabaseManager.supabasePublishableKey
            )
        }
    ) {
        self.connection = connection
        self.store = store
        self.ledger = ledger
        self.defaults = defaults
        self.makeClient = makeClient
        autoUploadEnabled = (defaults.object(forKey: Self.autoUploadKey) as? Bool) ?? true
    }

    // MARK: Status

    func status(for run: RecordedRun) -> StravaUploadStatus {
        if let id = run.stravaActivityID { return .onStrava(id) }
        if let known = statuses[run.id] { return known }
        switch StravaUploadDecision.decide(for: run) {
        case .alreadyOnStrava(let id): return .onStrava(id)
        case .notEligible: return .notEligible
        case .uploadGPX, .createManual:
            if let pending = ledger.entry(for: run.id) { return pending.uploadID == nil ? .failed : .sending }
            return .ready
        }
    }

    // MARK: Upload

    /// After a run is saved and processed: uploads when Strava is connected and the setting is on.
    func autoUploadIfEnabled(_ run: RecordedRun) async {
        guard connection.isConnected, autoUploadEnabled else { return }
        await upload(run)
    }

    /// Never throws and never presents an alert. The result is in `statuses` and on the run.
    func upload(_ run: RecordedRun) async {
        let latest = store.storedRun(id: run.id) ?? run
        switch StravaUploadDecision.decide(for: latest) {
        case .alreadyOnStrava(let id):
            statuses[run.id] = .onStrava(id)
            ledger.remove(runID: run.id)
            return
        case .notEligible:
            return
        case .uploadGPX, .createManual:
            break
        }
        guard connection.isConnected, !inFlight.contains(run.id) else { return }
        inFlight.insert(run.id)
        statuses[run.id] = .sending
        defer { inFlight.remove(run.id) }

        do {
            let token = try await connection.validAccessToken()
            let draft = StravaActivityDraft(run: latest)
            let client = makeClient()
            let result: StravaUploadResult
            if let uploadID = ledger.entry(for: run.id)?.uploadID {
                result = try await client.pollUpload(uploadID: uploadID, accessToken: token)
            } else if StravaUploadDecision.decide(for: latest) == .createManual {
                result = .onStrava(activityID: try await client.createManualActivity(draft: draft, accessToken: token))
            } else {
                result = try await client.uploadGPX(draft: draft, accessToken: token)
            }
            switch result {
            case .onStrava(let activityID):
                store.setStravaActivityID(activityID, forRunID: run.id)
                ledger.remove(runID: run.id)
                statuses[run.id] = .onStrava(activityID)
            case .processing(let uploadID):
                ledger.upsert(runID: run.id, uploadID: uploadID)
                statuses[run.id] = .sending
            }
        } catch {
            if case StravaError.rejected = error, ledger.entry(for: run.id)?.uploadID != nil {
                // Strava refused the file it had accepted: start over next time.
                ledger.remove(runID: run.id)
            }
            ledger.upsert(runID: run.id, uploadID: nil)
            statuses[run.id] = .failed
        }
    }

    /// On app foreground: finishes uploads that failed or were still processing.
    func retryPending() async {
        guard connection.isConnected else { return }
        for entry in ledger.retryable().prefix(5) {
            guard let run = store.storedRun(id: entry.runID) else {
                ledger.remove(runID: entry.runID)
                continue
            }
            await upload(run)
        }
    }

    /// Sign-out or Strava disconnect: nothing pending is left to retry for this runner.
    func clearPending() {
        ledger.removeAll()
        statuses = [:]
    }
}
