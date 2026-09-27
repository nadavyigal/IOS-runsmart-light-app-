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

    private static let userDefaultsKey = "voiceCoachEnabled"
    private static let cueInterval: TimeInterval = 300

    private override init() {
        isEnabled = UserDefaults.standard.object(forKey: VoiceCoachService.userDefaultsKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: VoiceCoachService.userDefaultsKey)
        super.init()
    }

    func startSession() {
        configureAudioSession()
        startTimer()
    }

    func stopSession() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func pauseSession() {
        timer?.invalidate()
        timer = nil
        player?.pause()
    }

    func resumeSession() {
        startTimer()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: VoiceCoachService.userDefaultsKey)
        if !enabled {
            stopSession()
        }
    }

    func deliverCue(context: VoiceCueContext) {
        guard isEnabled, !isFetching else { return }
        isFetching = true
        Task { [weak self] in
            await self?.fetchAndPlay(context: context)
            await MainActor.run { [weak self] in
                self?.isFetching = false
            }
        }
    }

    // MARK: AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {}

    // MARK: Private

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetoothHFP])
        try? session.setActive(true)
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

    private func fetchAndPlay(context: VoiceCueContext) async {
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
                self?.lastCueText = text
            }
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            self.player?.stop()
            if let p = try? AVAudioPlayer(data: data) {
                p.delegate = self
                p.prepareToPlay()
                p.play()
                self.player = p
            }
        }
    }
}
