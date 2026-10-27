import AVKit
import SwiftUI
import UIKit

struct ShareRunView: View {
    @Environment(\.dismiss) private var dismiss
    var run: RecordedRun?
    var insight: String
    @State private var format: RunShareAssetFormat
    @State private var includeMap = false
    @State private var includeInsight = true
    @State private var preview: UIImage?
    @State private var readyAsset: RunSharePreparedAsset?
    @State private var previewKeyRendered: RunShareRenderKey?
    private let canIncludeMap: Bool
    @State private var player: AVPlayer?
    @State private var isPreparing = false
    @State private var isCreatingVideo = false
    @State private var progress = 0.0
    @State private var failure: String?
    @State private var requestID = UUID()
    @State private var videoTask: Task<Void, Never>?
    @State private var videoRequestID: UUID?
    @State private var activity: RunShareActivityItem?

    init(run: RecordedRun?, insight: String = "", initialFormat: RunShareAssetFormat = .story) {
        self.run = run
        self.insight = insight
        self.canIncludeMap = run.map { !RunShareSnapshot.make(run: $0, includeMap: true).routePoints.isEmpty } ?? false
        _format = State(initialValue: initialFormat)
    }

    private var renderKey: RunShareRenderKey {
        RunShareRenderKey(format: format, run: run, includeMap: includeMap, insight: includeInsight ? insight : nil)
    }

    private var exportURL: URL? { readyAsset?.url(matching: renderKey) }
    private var hasCurrentPreview: Bool { preview != nil && previewKeyRendered == renderKey }

    private var snapshot: RunShareSnapshot? {
        guard let run else { return nil }
        return .make(run: run, includeMap: includeMap, insight: includeInsight ? insight : "")
    }

    var body: some View {
        ScrollView {
            if run == nil {
                ContentUnavailableView("Choose a completed run", systemImage: "figure.run", description: Text("Open a saved run to create a share image or video."))
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    previewView
                    Picker("Share format", selection: $format) {
                        ForEach(RunShareAssetFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isCreatingVideo)
                    Text(format.detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    if canIncludeMap {
                        Toggle("Include route map", isOn: $includeMap)
                            .tint(Color.accentPrimary)
                            .disabled(isCreatingVideo)
                            .accessibilityHint("Off by default. The first and last 200 meters and nearby start and finish locations are hidden.")
                        Text(includeMap ? RouteSharePrivacy.privacyNote : "No location data is included.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        Text("No shareable GPS route is available. Your image and video can still show your run stats.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    if !insight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Toggle("Include coach insight", isOn: $includeInsight)
                            .tint(Color.accentPrimary)
                            .disabled(isCreatingVideo)
                    }
                    if isCreatingVideo {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: progress).tint(Color.accentPrimary)
                            HStack {
                                Text(progress == 0 ? "Preparing map…" : "Creating video · \(Int(progress * 100))%")
                                    .font(.caption)
                                Spacer()
                                Button("Cancel") { videoTask?.cancel() }
                            }
                        }
                    }
                    if let failure {
                        Text(failure).font(.callout).foregroundStyle(Color.accentHeart)
                            .accessibilityLabel("Export failed. \(failure)")
                        Button("Retry") {
                            if format == .video, hasCurrentPreview { createVideo() } else { Task { await preparePreview() } }
                        }
                        .disabled(isPreparing || isCreatingVideo)
                    }
                    if format == .video && exportURL == nil {
                        Button(action: createVideo) {
                            Label("Create 10-second video", systemImage: "video.badge.plus")
                        }
                        .buttonStyle(NeonButtonStyle())
                        .disabled(isPreparing || isCreatingVideo || !hasCurrentPreview)
                    } else {
                        Button(action: share) {
                            Label(format == .video ? "Share video" : "Share image", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(NeonButtonStyle())
                        .disabled(exportURL == nil || isPreparing || isCreatingVideo)
                    }
                    Link(destination: ExternalURLs.appStore) {
                        Label("RunSmart on the App Store", systemImage: "arrow.up.forward.app")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentPrimary)
                    }
                    Text("The App Store link is included when you share.")
                        .font(.caption).foregroundStyle(Color.textSecondary)
                }
                .padding(18)
            }
        }
        .background(Color.surfaceBase)
        .preferredColorScheme(.dark)
        .tint(Color.accentPrimary)
        .toolbarBackground(Color.surfaceBase, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .foregroundStyle(Color.textPrimary)
        .navigationTitle("Share Run")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task(id: renderKey) {
            await preparePreview()
        }
        .sheet(item: $activity) { RunShareActivitySheet(item: $0) }
        .onDisappear { videoTask?.cancel(); player?.pause() }
    }

    @ViewBuilder private var previewView: some View {
        ZStack {
            if let player, format == .video, exportURL != nil {
                VideoPlayer(player: player)
            } else if let preview, hasCurrentPreview {
                Image(uiImage: preview).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 16).fill(Color.surfaceCard)
            }
            if isPreparing { ProgressView("Preparing preview…").tint(Color.accentPrimary) }
        }
        .aspectRatio(format.pixelSize.width / format.pixelSize.height, contentMode: .fit)
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("\(format.rawValue) preview for this run")
    }

    @MainActor private func preparePreview() async {
        guard let snapshot else { return }
        let id = UUID()
        let key = renderKey
        requestID = id
        videoTask?.cancel()
        videoTask = nil
        videoRequestID = nil
        isCreatingVideo = false
        progress = 0
        isPreparing = true
        failure = nil
        readyAsset = nil
        previewKeyRendered = nil
        player?.pause()
        player = nil
        preview = nil
        defer { if requestID == id { isPreparing = false } }
        do {
            let image = try await RunShareMediaRenderer.poster(snapshot: snapshot, format: format == .feed ? .feed : .story)
            try Task.checkCancellation()
            guard requestID == id, key == renderKey else { return }
            preview = image
            previewKeyRendered = key
            if key.format != .video {
                readyAsset = RunSharePreparedAsset(key: key, snapshot: snapshot, fileURL: try writePNG(image))
            }
        } catch is CancellationError {
            // Replaced options or dismissal cancel the obsolete render.
        } catch {
            guard requestID == id else { return }
            failure = error.localizedDescription
        }
    }

    @MainActor private func createVideo() {
        guard let snapshot, !isCreatingVideo, !isPreparing, format == .video, hasCurrentPreview else { return }
        let id = requestID
        let key = renderKey
        let jobID = UUID()
        videoRequestID = jobID
        isCreatingVideo = true
        progress = 0
        failure = nil
        videoTask = Task { @MainActor in
            var unclaimedURL: URL?
            defer {
                if let unclaimedURL { try? FileManager.default.removeItem(at: unclaimedURL) }
                if videoRequestID == jobID {
                    isCreatingVideo = false
                    videoTask = nil
                    videoRequestID = nil
                }
            }
            do {
                let url = try await RunShareMediaRenderer.video(snapshot: snapshot) { value in
                    guard requestID == id, key == renderKey, videoRequestID == jobID else { return }
                    progress = value
                }
                unclaimedURL = url
                try Task.checkCancellation()
                guard requestID == id, key == renderKey, videoRequestID == jobID else { return }
                readyAsset = RunSharePreparedAsset(key: key, snapshot: snapshot, fileURL: url)
                player = AVPlayer(url: url)
                unclaimedURL = nil
            } catch is CancellationError {
                if videoRequestID == jobID { progress = 0 }
            } catch {
                guard requestID == id, key == renderKey, videoRequestID == jobID else { return }
                failure = error.localizedDescription
            }
        }
    }

    private func writePNG(_ image: UIImage) throws -> URL {
        guard let data = image.pngData() else { throw RunShareMediaError.cannotCreateVideo }
        let url = try RunShareExportFiles.newURL(extension: "png")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Keep the file alive for the receiving share extension after the composer closes.
        return url
    }

    private func share() {
        guard let item = readyAsset?.activityItem(matching: renderKey) else { return }
        Analytics.trackShareProgressTapped(payloadKind: ProgressShareKind.runReport.rawValue)
        activity = item
    }
}
