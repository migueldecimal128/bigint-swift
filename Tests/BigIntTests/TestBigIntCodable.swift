import Testing
import Foundation
@testable import BigInt

@Suite struct TestBigIntCodable {
    struct Box: Codable, Equatable { let v: BigInt }

    @Test func roundTrip() throws {
        let vals: [BigInt] = [0, 1, -1, 12345, -12345,
                              BigInt.from(Int64.min), BigInt.from(UInt64.max),
                              BigInt.from("340282366920938463463374607431768211457"),
                              BigInt.from("-99999999999999999999999999999999999999")]
        let enc = JSONEncoder(); let dec = JSONDecoder()
        for v in vals {
            let data = try enc.encode(Box(v: v))
            #expect(try dec.decode(Box.self, from: data).v == v)
        }
        // top-level array round-trips too
        let arr = try enc.encode(vals)
        #expect(try dec.decode([BigInt].self, from: arr) == vals)
    }

    @Test func encodesAsDecimalString() throws {
        let data = try JSONEncoder().encode(Box(v: -42))
        #expect(String(data: data, encoding: .utf8) == "{\"v\":\"-42\"}")   // string, not number
    }

    @Test func malformedThrows() {
        let dec = JSONDecoder()
        for bad in ["12x3", "", "-", "0x1F", "1.0", " 5", "+5"] {
            let data = "{\"v\":\"\(bad)\"}".data(using: .utf8)!
            #expect(throws: DecodingError.self) { try dec.decode(Box.self, from: data) }
        }
    }

    @Test func separateFailableDecoder() {
        #expect(BigInt.fromDecimalStringOrNil("12345") == (12345 as BigInt))
        #expect(BigInt.fromDecimalStringOrNil("-12345") == (-12345 as BigInt))
        #expect(BigInt.fromDecimalStringOrNil("007") == (7 as BigInt))   // leading zeros ok
        #expect(BigInt.fromDecimalStringOrNil("-0") == BigInt.ZERO)
        // malformed → nil (caller chooses behavior, no trap)
        for bad in ["12x3", "", "-", "0x1F", "1.0", "+5", " 5", "5 "] {
            #expect(BigInt.fromDecimalStringOrNil(bad) == nil, "should reject \(bad)")
        }
    }
}
