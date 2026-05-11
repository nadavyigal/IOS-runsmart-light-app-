import Foundation

/// A polymorphic reference to profiles.id that can be either a bigint (Int) or a UUID/string,
/// depending on the backend schema. Encodes to Supabase as either an integer or a string.
public enum DBProfileReference: Encodable, Sendable {
    case numeric(Int)
    case uuid(UUID)
    case string(String)

    /// A readable representation for logs.
    public var debugValue: String {
        switch self {
        case .numeric(let n): return "numeric:\(n)"
        case .uuid(let u): return "uuid:\(u.uuidString)"
        case .string(let s): return "string:\(s)"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .numeric(let n):
            try single.encode(n)
        case .uuid(let u):
            try single.encode(u.uuidString)
        case .string(let s):
            try single.encode(s)
        }
    }
}
