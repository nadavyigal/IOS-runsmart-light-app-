import Foundation
import SwiftData

enum LocalModelContainer {
    static func make() throws -> ModelContainer {
        let schema = Schema([
            CachedResume.self,
            CachedApplication.self,
        ])
        return try ModelContainer(for: schema)
    }
}
