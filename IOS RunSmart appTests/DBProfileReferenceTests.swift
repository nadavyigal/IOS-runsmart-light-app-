import Foundation
import Testing
@testable import IOS_RunSmart_app

@Suite("DBProfileReference Encoding")
struct DBProfileReferenceTests {
    @Test("Encodes numeric as integer")
    func encodesNumeric() throws {
        let ref = DBProfileReference.numeric(42)
        let data = try JSONEncoder().encode(["profile_id": ref])
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"profile_id\":42"))
        #expect(ref.debugValue == "numeric:42")
    }

    @Test("Encodes uuid as string")
    func encodesUUID() throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let ref = DBProfileReference.uuid(id)
        let data = try JSONEncoder().encode(["profile_id": ref])
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"profile_id\":\"00000000-0000-0000-0000-000000000001\""))
        #expect(ref.debugValue.contains("uuid:"))
    }

    @Test("Encodes string as string")
    func encodesString() throws {
        let ref = DBProfileReference.string("abc")
        let data = try JSONEncoder().encode(["profile_id": ref])
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"profile_id\":\"abc\""))
        #expect(ref.debugValue == "string:abc")
    }
}
