import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class RunShareExportFilesTests: XCTestCase {
    func testCleanupRemovesOnlyExpiredOwnedMediaAndKeepsFreshShareAttachments() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date()
        let expired = folder.appendingPathComponent("RunSmart-expired.mp4")
        let fresh = folder.appendingPathComponent("RunSmart-active.png")
        let unrelated = folder.appendingPathComponent("Other-old.mp4")
        let unknown = folder.appendingPathComponent("RunSmart-old.txt")
        for file in [expired, fresh, unrelated, unknown] { try Data([1, 2, 3]).write(to: file) }
        for file in [expired, unrelated, unknown] {
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-RunShareExportFiles.maximumAge - 60)], ofItemAtPath: file.path)
        }
        try RunShareExportFiles.removeExpired(in: folder, now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
    }
}
