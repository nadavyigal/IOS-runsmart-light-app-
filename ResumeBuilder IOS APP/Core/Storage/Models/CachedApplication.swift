import Foundation
import SwiftData

@Model
final class CachedApplication {
    @Attribute(.unique) var id: String
    var title: String
    var company: String
    var status: String
    var updatedAt: Date

    init(id: String, title: String, company: String, status: String, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.company = company
        self.status = status
        self.updatedAt = updatedAt
    }
}
