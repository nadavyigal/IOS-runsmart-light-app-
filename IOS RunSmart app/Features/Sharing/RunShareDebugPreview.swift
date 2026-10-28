#if DEBUG
import AVFoundation
import SwiftUI

/// Explicit simulator review entry. No demo track or fixed metrics are compiled into release builds.
struct RunShareDebugPreview: View {
    @State private var status = "Example data · share preview"

    var body: some View {
        NavigationStack {
            ShareRunView(run: Self.exampleRun, insight: "A run worth remembering.")
                .safeAreaInset(edge: .top) {
                    Text(status).font(.caption).padding(8).frame(maxWidth: .infinity)
                        .background(Color.surfaceCard).foregroundStyle(Color.accentPrimary)
                }
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--run-share-smoke-exports") else { return }
            do {
                let snapshot = RunShareSnapshot.make(run: Self.exampleRun, includeMap: true, insight: "A run worth remembering.")
                let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("RunShareQA", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                status = "Checking real map image export…"
                for format in [RunShareAssetFormat.story, .feed] {
                    let image = try await RunShareMediaRenderer.poster(snapshot: snapshot, format: format)
                    try image.pngData()?.write(to: folder.appendingPathComponent("\(format.rawValue).png"), options: .atomic)
                }
                let url = try await RunShareMediaRenderer.video(snapshot: snapshot) { progress in
                    status = "Checking video export · \(Int(progress * 100))%"
                }
                let copy = folder.appendingPathComponent("Video.mp4")
                if FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.removeItem(at: copy) }
                try FileManager.default.copyItem(at: url, to: copy)
                status = "Example exports ready · image + video"
            } catch {
                status = "Export check failed: \(error.localizedDescription)"
            }
        }
    }

    static var exampleRun: RecordedRun {
        let start = Date(timeIntervalSince1970: 1_792_734_000)
        let vertices: [(Double, Double)] = [
            (32.0529, 34.7504), (32.0552, 34.7518), (32.0580, 34.7540),
            (32.0605, 34.7567), (32.0640, 34.7594), (32.0670, 34.7611),
            (32.0704, 34.7637), (32.0735, 34.7652), (32.0764, 34.7665),
            (32.0797, 34.7681)
        ]
        var locations: [(Double, Double)] = []
        for index in 1..<vertices.count {
            let a = vertices[index - 1], b = vertices[index]
            for step in 0..<12 {
                let t = Double(step) / 12
                locations.append((a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t))
            }
        }
        locations.append(vertices.last!)
        locations.append(contentsOf: locations.dropLast().reversed())
        let points = locations.enumerated().map { index, coordinate in
            RunRoutePoint(latitude: coordinate.0, longitude: coordinate.1,
                          timestamp: start.addingTimeInterval(Double(index) * 2439 / Double(locations.count - 1)),
                          horizontalAccuracy: 5, altitude: nil)
        }
        return RecordedRun(id: UUID(uuidString: "00000000-0000-0000-0000-000000000027")!,
                           providerActivityID: nil, source: .runSmart, startedAt: start,
                           endedAt: start.addingTimeInterval(2439), distanceMeters: 6800,
                           movingTimeSeconds: 2439, averagePaceSecondsPerKm: 2439 / 6.8,
                           averageHeartRateBPM: nil, routePoints: points, syncedAt: nil,
                           title: "Example coastal run")
    }
}
#endif
