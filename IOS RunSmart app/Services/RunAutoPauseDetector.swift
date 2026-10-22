import Foundation

/// Requires fresh, accurate fixes from the recorder. Unknown speed and gaps reset
/// the debounce; absence of GPS must never be interpreted as standing still.
struct RunAutoPauseDetector {
    enum Action: Equatable {
        case pause(since: Date)
        case resume
    }
    private var stoppedSince: Date?
    private var lastTimestamp: Date?

    mutating func reset() { stoppedSince = nil; lastTimestamp = nil }

    mutating func update(speed: Double, at timestamp: Date, isAutoPaused: Bool) -> Action? {
        if let lastTimestamp {
            guard timestamp > lastTimestamp else { return nil }
            if timestamp.timeIntervalSince(lastTimestamp) > 15 { stoppedSince = nil }
        }
        lastTimestamp = timestamp
        guard speed.isFinite, speed >= 0, speed <= 12 else { stoppedSince = nil; return nil }
        if isAutoPaused {
            stoppedSince = nil
            return speed >= 0.8 ? .resume : nil
        }
        guard speed < 0.5 else { stoppedSince = nil; return nil }
        if stoppedSince == nil { stoppedSince = timestamp }
        if let stoppedSince, timestamp.timeIntervalSince(stoppedSince) >= 8 { return .pause(since: stoppedSince) }
        return nil
    }
}
