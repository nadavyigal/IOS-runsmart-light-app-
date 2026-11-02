import Foundation

/// Only app-owned completed temporary media is aged out. Fresh files remain available to share
/// extensions after the composer closes. No saved runs, photos or user-selected files are touched.
enum RunShareExportFiles {
    static let maximumAge: TimeInterval = 24 * 60 * 60

    static func newURL(extension suffix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RunSmartShares", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? removeExpired(in: folder, now: Date())
        return folder.appendingPathComponent("RunSmart-\(UUID().uuidString).\(suffix)")
    }

    static func removeExpired(in folder: URL, now: Date) throws {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys)) {
            guard file.lastPathComponent.hasPrefix("RunSmart-"), ["png", "mp4"].contains(file.pathExtension) else { continue }
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let date = values.contentModificationDate, now.timeIntervalSince(date) > maximumAge else { continue }
            try FileManager.default.removeItem(at: file)
        }
    }
}
