import Foundation
import AVFoundation
import Combine
import Supabase

extension Notification.Name {
    static let voiceCoachCueTimerFired = Notification.Name("com.runsmart.voiceCoachCueTimerFired")
}

struct VoiceCueContext: Encodable {
    var elapsedMinutes: Double
    var distanceKm: Double
    var currentPaceMinPerKm: Double
    var targetPaceMinPerKm: Double?
    var workoutGoal: String?
    var heartRateBPM: Int?
}

@MainActor
final class VoiceCoachService: NSObject, ObservableObject, AVAudioPlayerDelegate {

    static let shared = VoiceCoachService()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastCueText: String?

    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var isFetching = false
    /// Bumped every time the run session starts, pauses, stops or cues are switched off, so a
    /// cue whose network call returns later can tell it belongs to an earlier session.
    private(set) var sessionGeneration = 0
    /// True from start/resume until pause/stop. Stays true while cues are switched off, so
    /// switching them back on mid-run can restart the timer.
    private(set) var isRunSessionLive = false
    var isCueTimerRunning: Bool { timer != nil }

    private static let userDefaultsKey = "voiceCoachEnabled"
    private static let cueInterval: TimeInterval = 300

    private override init() {
        isEnabled = UserDefaults.standard.object(forKey: VoiceCoachService.userDefaultsKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: VoiceCoachService.userDefaultsKey)
        super.init()
    }

    func startSession() {
        isRunSessionLive = true
        silenceCues()
        configureAudioSession()
        startTimer()
    }

    func stopSession() {
        isRunSessionLive = false
        silenceCues()
    }

    func pauseSession() {
        isRunSessionLive = false
        silenceCues()
    }

    /// Also configures the audio category: a recovered run lands in `.paused` and resumes
    /// without ever calling `startSession()`. Setting the category twice is harmless.
    func resumeSession() {
        isRunSessionLive = true
        configureAudioSession()
        startTimer()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: VoiceCoachService.userDefaultsKey)
        if !enabled {
            silenceCues()
        } else if isRunSessionLive {
            configureAudioSession()
            startTimer()
        }
    }

    /// A cue may play only if its session is still the current one, the run is live and cues are on.
    static func shouldPlayCue(startedIn generation: Int, current: Int, isRunSessionLive: Bool, isEnabled: Bool) -> Bool {
        generation == current && isRunSessionLive && isEnabled
    }

    func deliverCue(context: VoiceCueContext) {
        guard isEnabled, !isFetching else { return }
        isFetching = true
        let generation = sessionGeneration
        Task { [weak self] in
            await self?.fetchAndPlay(context: context, generation: generation)
            await MainActor.run { [weak self] in
                self?.isFetching = false
            }
        }
    }

    // MARK: AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.deactivateAudioSession()
        }
    }

    // MARK: Private

    private func canPlayCue(startedIn generation: Int) -> Bool {
        Self.shouldPlayCue(
            startedIn: generation,
            current: sessionGeneration,
            isRunSessionLive: isRunSessionLive,
            isEnabled: isEnabled
        )
    }

    private func silenceCues() {
        sessionGeneration += 1
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        deactivateAudioSession()
    }

    /// Sets the category only. The session is activated around each cue (see `fetchAndPlay`),
    /// so other apps' music is ducked only while a cue plays, not for the whole run.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetoothHFP])
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: VoiceCoachService.cueInterval, repeats: true) { _ in
            NotificationCenter.default.post(name: .voiceCoachCueTimerFired, object: nil)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The voice-cue route requires a Supabase session. Returns nil without a token,
    /// so guests skip the network call instead of sending a request that will 401.
    static func voiceCueRequest(context: VoiceCueContext, baseURLString: String, accessToken: String?) -> URLRequest? {
        guard let accessToken, !accessToken.isEmpty,
              let url = URL(string: "\(baseURLString)/api/coach/voice-cue"),
              let bodyData = try? JSONEncoder().encode(context) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        return request
    }

    private func fetchAndPlay(context: VoiceCueContext, generation: Int) async {
        guard let baseURLString = Bundle.main.object(forInfoDictionaryKey: "RunSmartAPIBaseURL") as? String else { return }

        let accessToken = try? await SupabaseManager.client.auth.session.accessToken
        guard let request = Self.voiceCueRequest(
            context: context,
            baseURLString: baseURLString,
            accessToken: accessToken
        ) else { return }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              !data.isEmpty else { return }

        if let encodedText = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Coach-Text"),
           let text = encodedText.removingPercentEncoding {
            await MainActor.run { [weak self] in
                guard let self, self.canPlayCue(startedIn: generation) else { return }
                self.lastCueText = text
            }
        }

        await MainActor.run { [weak self] in
            // The network call can outlive the session that asked for it (pause, finish,
            // cues switched off). Check on the main actor, right before touching audio.
            guard let self, self.canPlayCue(startedIn: generation) else { return }
            self.player?.stop()
            try? AVAudioSession.sharedInstance().setActive(true)
            if let p = try? AVAudioPlayer(data: data) {
                p.delegate = self
                p.prepareToPlay()
                if p.play() {
                    self.player = p
                } else {
                    self.deactivateAudioSession()
                }
            } else {
                self.deactivateAudioSession()
            }
        }
    }
}
