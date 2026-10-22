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
    private var sessionGeneration = 0
    private var sessionActive = false

    private static let userDefaultsKey = "voiceCoachEnabled"
    private static let cueInterval: TimeInterval = 300

    private override init() {
        isEnabled = UserDefaults.standard.object(forKey: VoiceCoachService.userDefaultsKey) == nil
            ? false
            : UserDefaults.standard.bool(forKey: VoiceCoachService.userDefaultsKey)
        super.init()
    }

    func startSession() {
        sessionActive = true
        configureAudioSession()
        startTimer()
    }

    func stopSession() {
        sessionActive = false
        sessionGeneration += 1
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        deactivateAudioSession()
    }

    func pauseSession() {
        sessionActive = false
        sessionGeneration += 1
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        deactivateAudioSession()
    }

    func resumeSession() {
        sessionActive = true
        startTimer()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: VoiceCoachService.userDefaultsKey)
        if !enabled {
            sessionGeneration += 1
            player?.stop()
            player = nil
            deactivateAudioSession()
        }
    }

    func cancelPlaybackForLocalCue() {
        sessionGeneration += 1
        player?.stop()
        player = nil
        deactivateAudioSession()
    }

    func deliverCue(context: VoiceCueContext) {
        guard isEnabled, sessionActive, !isFetching, !LocalRunCueService.shared.isSpeaking else { return }
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
            guard let self, self.player === player else { return }
            self.player = nil
            self.deactivateAudioSession()
        }
    }

    // MARK: Private

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

        guard isEnabled, sessionActive, generation == sessionGeneration, !LocalRunCueService.shared.isSpeaking else { return }

        if let encodedText = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Coach-Text"),
           let text = encodedText.removingPercentEncoding {
            lastCueText = text
        }

        player?.stop()
        configureAudioSession()
        try? AVAudioSession.sharedInstance().setActive(true)
        if let p = try? AVAudioPlayer(data: data) {
            p.delegate = self
            p.prepareToPlay()
            if p.play() {
                player = p
            } else {
                deactivateAudioSession()
            }
        } else {
            deactivateAudioSession()
        }
    }
}
