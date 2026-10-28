import AVFoundation
import CoreVideo
import UIKit

/// Errors never include route coordinates or the run's private notes.
enum RunShareMediaError: LocalizedError {
    case invalidRoute
    case mapUnavailable
    case cannotCreateVideo
    case videoEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidRoute: "The route cannot be used for this export. Try sharing without the map."
        case .mapUnavailable: "The map could not load. Check your connection and retry, or share without the map."
        case .cannotCreateVideo: "The video could not be prepared. Please try again."
        case .videoEncodingFailed: "The video could not be completed. Please try again."
        }
    }
}

@MainActor
enum RunShareMediaRenderer {
    static let videoDuration: Double = 10
    static let videoFramesPerSecond: Int32 = 24

    static func poster(snapshot: RunShareSnapshot, format: RunShareAssetFormat) async throws -> UIImage {
        try Task.checkCancellation()
        let map = try await RunSharePosterRenderer.prepareMap(snapshot: snapshot, format: format)
        try Task.checkCancellation()
        return RunSharePosterRenderer.image(snapshot: snapshot, format: format, map: map,
                                            logo: RunSharePosterRenderer.logoImage())
    }

    /// Fixed-frame offline rendering: network is used once to obtain the map plate, never per
    /// frame. Pixel buffers and images are released as frames are written, not retained in an array.
    static func video(snapshot: RunShareSnapshot, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        progress(0)
        let map = try await RunSharePosterRenderer.prepareMap(snapshot: snapshot, format: .video)
        let logo = RunSharePosterRenderer.logoImage()
        try Task.checkCancellation()
        let url = try RunShareExportFiles.newURL(extension: "mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1_080,
            AVVideoHeightKey: 1_920,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 48
            ]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1_080,
            kCVPixelBufferHeightKey as String: 1_920,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        guard writer.canAdd(input) else { throw RunShareMediaError.cannotCreateVideo }
        writer.add(input)
        var succeeded = false
        defer {
            if !succeeded {
                if writer.status == .writing || writer.status == .unknown { writer.cancelWriting() }
                try? FileManager.default.removeItem(at: url)
            }
        }
        guard writer.startWriting() else { throw RunShareMediaError.cannotCreateVideo }
        writer.startSession(atSourceTime: .zero)
        let frameCount = Int(videoDuration * Double(videoFramesPerSecond))
        for frame in 0..<frameCount {
            try Task.checkCancellation()
            // Backpressure is cooperative; cancellation/dismissal never blocks the main actor.
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw RunShareMediaError.videoEncodingFailed }
                try await Task.sleep(nanoseconds: 4_000_000)
            }
            try autoreleasepool {
                guard let pool = adaptor.pixelBufferPool else { throw RunShareMediaError.cannotCreateVideo }
                var optionalBuffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &optionalBuffer) == kCVReturnSuccess,
                      let buffer = optionalBuffer else { throw RunShareMediaError.cannotCreateVideo }
                CVPixelBufferLockBaseAddress(buffer, [])
                var isLocked = true
                defer { if isLocked { CVPixelBufferUnlockBaseAddress(buffer, []) } }
                guard let context = CGContext(
                    data: CVPixelBufferGetBaseAddress(buffer), width: 1_080, height: 1_920,
                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
                ) else { throw RunShareMediaError.cannotCreateVideo }
                // UIKit's y-down coordinate system, with no extra UIImage allocation per frame.
                context.translateBy(x: 0, y: 1_920)
                context.scaleBy(x: 1, y: -1)
                UIGraphicsPushContext(context)
                RunSharePosterRenderer.draw(snapshot: snapshot, format: .video, map: map, logo: logo,
                                             time: Double(frame) / Double(videoFramesPerSecond),
                                             context: context, size: CGSize(width: 1_080, height: 1_920))
                UIGraphicsPopContext()
                CVPixelBufferUnlockBaseAddress(buffer, [])
                isLocked = false
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: videoFramesPerSecond)) else {
                    throw RunShareMediaError.videoEncodingFailed
                }
            }
            progress(Double(frame + 1) / Double(frameCount))
            await Task.yield()
        }
        try Task.checkCancellation()
        input.markAsFinished()
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw RunShareMediaError.videoEncodingFailed }
        succeeded = true
        progress(1)
        return url
    }
}
