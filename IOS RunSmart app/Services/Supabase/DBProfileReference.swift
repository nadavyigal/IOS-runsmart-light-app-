import Foundation

/// A polymorphic reference to profiles.id that can be either a bigint (Int) or a UUID/string,
/// depending on the backend schema. Encodes to Supabase as either an integer or a string.
public enum DBProfileReference: Codable, Hashable, Sendable {
    case numeric(Int)
    case uuid(UUID)
    case string(String)

    /// A readable representation for logs.
    public var debugValue: String {
        switch self {
        case .numeric(let value): return "numeric:\(value)"
        case .uuid(let value): return "uuid:\(value.uuidString)"
        case .string(let value): return "string:\(value)"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .numeric(value)
        } else if let value = try? container.decode(UUID.self) {
            self = .uuid(value)
        } else if let value = try? container.decode(String.self), let uuid = UUID(uuidString: value) {
            self = .uuid(uuid)
        } else if let value = try? container.decode(String.self), let int = Int(value) {
            self = .numeric(int)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .string("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .numeric(let value):
            try container.encode(value)
        case .uuid(let value):
            try container.encode(value.uuidString)
        case .string(let value):
            try container.encode(value)
        }
    }
}
