import Foundation
import SwiftData

@Model
final class CachedResume {
    @Attribute(.unique) var id: String
    var filename: String
    var localPath: String
    var updatedAt: Date

    init(id: String, filename: String, localPath: String, updatedAt: Date = .now) {
        self.id = id
        self.filename = filename
        self.localPath = localPath
        self.updatedAt = updatedAt
    }
}
