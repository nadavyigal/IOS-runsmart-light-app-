import Foundation
import Combine

/// Runs whose upload failed or is still being processed by Strava, kept for a retry on the next
/// app foreground. Only ids and timestamps are stored.
nonisolated struct StravaPendingUpload: Codable, Equatable {
    var runID: UUID
    /// Set when Strava accepted the file but had not created the activity yet.
    var uploadID: Int?
    var since: Date
    /// Set before a manual (no GPS) activity is created. If it is still set on the next try, the earlier
    /// call may have succeeded without the app hearing about it, so Strava is searched before creating again.
    var manualAttemptStarted: Bool? = nil
    /// The title and notes that went up with the file, kept while Strava is still processing it, so a later
    /// change can be sent once the activity exists.
    var sentTitle: String? = nil
    var sentNotes: String? = nil
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

    func upsert(runID: UUID, uploadID: Int?, now: Date = Date(), sentTitle: String? = nil, sentNotes: String? = nil) {
        var list = all()
        if let index = list.firstIndex(where: { $0.runID == runID }) {
            list[index].uploadID = uploadID ?? list[index].uploadID
            list[index].sentTitle = sentTitle ?? list[index].sentTitle
            list[index].sentNotes = sentNotes ?? list[index].sentNotes
        } else {
            list.append(StravaPendingUpload(runID: runID, uploadID: uploadID, since: now, sentTitle: sentTitle, sentNotes: sentNotes))
        }
        write(list)
    }

    /// Written before the create call, so a crash or a lost response leaves a trace.
    func markManualAttempt(runID: UUID, now: Date = Date()) {
        var list = all()
        if let index = list.firstIndex(where: { $0.runID == runID }) {
            list[index].manualAttemptStarted = true
        } else {
            list.append(StravaPendingUpload(runID: runID, uploadID: nil, since: now, manualAttemptStarted: true))
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
    /// Runs whose title or notes changed after they were on Strava and still need sending.
    private let detailsLedger: StravaPendingLedger
    private let defaults: UserDefaults
    private let makeClient: () -> StravaClient
    private let now: () -> Date
    private var inFlight: Set<UUID> = []
    private var detailsInFlight: Set<UUID> = []
    /// Runs whose auto-upload waits for the runner to finish the summary, with the time the wait began.
    private var heldRuns: [UUID: Date] = [:]
    /// A held run is released anyway after this long, so a summary that is never closed cannot block the upload.
    static let maximumHold: TimeInterval = 15 * 60

    init(
        connection: StravaConnectionService = .shared,
        store: StravaRunStoring = RunSmartLocalStore.shared,
        ledger: StravaPendingLedger = StravaPendingLedger(),
        detailsLedger: StravaPendingLedger? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
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
        self.detailsLedger = detailsLedger ?? StravaPendingLedger(defaults: defaults, key: "runsmart.strava.pendingDetails")
        self.defaults = defaults
        self.now = now
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
        connection.reconcileOwnership()
        guard connection.isConnected, autoUploadEnabled else { return }
        await upload(run)
    }

    // MARK: Hold until the runner is done with the summary

    /// The post-run summary is open and the runner may still edit the title and notes: the auto-upload waits
    /// for `releaseHeldUpload`. The run is also written to the retry ledger, so if the app is killed before
    /// the runner taps Done, the next foreground sends it.
    func holdAutoUpload(for run: RecordedRun) {
        connection.reconcileOwnership()
        guard connection.isConnected, autoUploadEnabled else { return }
        switch StravaUploadDecision.decide(for: store.storedRun(id: run.id) ?? run) {
        case .uploadGPX, .createManual: break
        case .alreadyOnStrava, .notEligible: return
        }
        heldRuns[run.id] = now()
        statuses[run.id] = .ready
        ledger.upsert(runID: run.id, uploadID: nil, now: now())
    }

    func isHeld(_ runID: UUID) -> Bool { heldRuns[runID] != nil }

    /// The runner tapped Done or left the summary: send the run with the title and notes as saved now.
    func releaseHeldUpload(runID: UUID) async {
        guard heldRuns.removeValue(forKey: runID) != nil else { return }
        guard let run = store.storedRun(id: runID) else {
            ledger.remove(runID: runID)
            statuses[runID] = nil
            return
        }
        connection.reconcileOwnership()
        guard connection.isConnected, autoUploadEnabled else {
            ledger.remove(runID: runID)
            statuses[runID] = nil
            return
        }
        statuses[runID] = nil
        await upload(run)
    }

    /// The runner deleted the run: nothing to send.
    func dropHeldUpload(runID: UUID) {
        heldRuns[runID] = nil
        ledger.remove(runID: runID)
        detailsLedger.remove(runID: runID)
        statuses[runID] = nil
    }

    /// Never throws and never presents an alert. The result is in `statuses` and on the run.
    func upload(_ run: RecordedRun) async {
        connection.reconcileOwnership()
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
        // A manual upload from the menu while the summary is still open takes over from the hold.
        heldRuns[run.id] = nil
        inFlight.insert(run.id)
        statuses[run.id] = .sending
        defer { inFlight.remove(run.id) }

        do {
            let token = try await connection.validAccessToken()
            let draft = StravaActivityDraft(run: latest)
            let client = makeClient()
            let result: StravaUploadResult
            var sentTitle = draft.name
            var sentNotes = draft.notes ?? ""
            if let entry = ledger.entry(for: run.id), let uploadID = entry.uploadID {
                sentTitle = entry.sentTitle ?? sentTitle
                sentNotes = entry.sentNotes ?? sentNotes
                result = try await client.pollUpload(uploadID: uploadID, accessToken: token)
            } else if StravaUploadDecision.decide(for: latest) == .createManual {
                result = .onStrava(activityID: try await createManualOnce(draft: draft, client: client, token: token))
            } else {
                result = try await client.uploadGPX(draft: draft, accessToken: token)
            }
            switch result {
            case .onStrava(let activityID):
                store.setStravaActivityID(activityID, forRunID: run.id)
                ledger.remove(runID: run.id)
                statuses[run.id] = .onStrava(activityID)
                // The runner may have edited the title or notes while the file was on its way: send the current text.
                if detailsDiffer(title: sentTitle, notes: sentNotes, runID: run.id) {
                    detailsLedger.upsert(runID: run.id, uploadID: nil, now: now())
                    await pushDetails(runID: run.id)
                }
            case .processing(let uploadID):
                ledger.upsert(runID: run.id, uploadID: uploadID, sentTitle: draft.name, sentNotes: draft.notes ?? "")
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

    /// Creates a manual activity at most once per run. The ledger entry is written before the call; if an
    /// earlier call left one behind, Strava is searched first and the activity found there is used.
    private func createManualOnce(draft: StravaActivityDraft, client: StravaClient, token: String) async throws -> Int {
        let earlierAttempt = ledger.entry(for: draft.runID)?.manualAttemptStarted == true
        ledger.markManualAttempt(runID: draft.runID, now: now())
        if earlierAttempt, let existing = try await client.findManualActivity(draft: draft, accessToken: token) {
            return existing
        }
        return try await client.createManualActivity(draft: draft, accessToken: token)
    }

    // MARK: Title and notes after the run is on Strava

    /// Call after the runner saved a new title or notes. When the run is already on Strava, the change is sent
    /// there too (best effort, kept for a retry if it fails). Before the upload there is nothing to do: the
    /// upload carries the saved text.
    func syncDetailsIfOnStrava(_ run: RecordedRun) async {
        let latest = store.storedRun(id: run.id) ?? run
        guard latest.stravaActivityID != nil else { return }
        detailsLedger.upsert(runID: run.id, uploadID: nil, now: now())
        await pushDetails(runID: run.id)
    }

    private func detailsDiffer(title: String, notes: String, runID: UUID) -> Bool {
        guard let stored = store.storedRun(id: runID) else { return false }
        return RunTitle.displayTitle(for: stored) != title || (stored.notes ?? "") != notes
    }

    /// Sends the stored title and notes. If they change while the request is out, sends again (up to three times).
    private func pushDetails(runID: UUID) async {
        connection.reconcileOwnership()
        guard connection.isConnected, !detailsInFlight.contains(runID) else { return }
        detailsInFlight.insert(runID)
        defer { detailsInFlight.remove(runID) }

        for _ in 0..<3 {
            guard let run = store.storedRun(id: runID), let activityID = run.stravaActivityID else {
                detailsLedger.remove(runID: runID)
                return
            }
            let name = RunTitle.displayTitle(for: run)
            let description = run.notes ?? ""
            do {
                let token = try await connection.validAccessToken()
                try await makeClient().updateActivity(activityID: activityID, name: name, description: description, accessToken: token)
            } catch StravaError.activityNotFound {
                // Deleted on Strava: nothing left to edit.
                detailsLedger.remove(runID: runID)
                return
            } catch {
                return // stays in the ledger for the next foreground
            }
            if let after = store.storedRun(id: runID),
               RunTitle.displayTitle(for: after) == name, (after.notes ?? "") == description {
                detailsLedger.remove(runID: runID)
                return
            }
        }
    }

    /// On app foreground: finishes uploads that failed or were still processing, and title or notes edits
    /// that did not reach Strava.
    func retryPending() async {
        connection.reconcileOwnership()
        guard connection.isConnected else { return }
        let current = now()
        for entry in ledger.retryable().prefix(5) {
            if let heldSince = heldRuns[entry.runID] {
                guard current.timeIntervalSince(heldSince) > Self.maximumHold else { continue }
                heldRuns[entry.runID] = nil
            }
            guard let run = store.storedRun(id: entry.runID) else {
                ledger.remove(runID: entry.runID)
                continue
            }
            await upload(run)
        }
        for entry in detailsLedger.retryable().prefix(5) {
            guard store.storedRun(id: entry.runID) != nil else {
                detailsLedger.remove(runID: entry.runID)
                continue
            }
            await pushDetails(runID: entry.runID)
        }
    }

    /// Sign-out or Strava disconnect: nothing pending is left to retry for this runner.
    func clearPending() {
        ledger.removeAll()
        detailsLedger.removeAll()
        heldRuns = [:]
        statuses = [:]
    }
}
