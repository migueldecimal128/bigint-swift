import Testing
@testable import BigInt

@Suite struct TestPrintParse {

    let verbose = false

    private struct ParseCase {
        let raw: String
        let expected: String
        init(_ raw: String, _ expected: String? = nil) {
            self.raw = raw
            self.expected = expected ?? raw
        }
    }

    private let parseCases: [ParseCase] = [
        ParseCase("0x10", "16"),
        ParseCase("-0x20", "-32"),
        ParseCase("123_456", "123456"),
    ]

    @Test func testParseCases() {
        for tc in parseCases {
            let observed = BigInt.from(tc.raw).toString()
            #expect(observed == tc.expected)
        }
    }

    private let hexCases: [ParseCase] = [
        ParseCase("0x10"),
        ParseCase("10", "0x10"),
        ParseCase("-10", "-0x10"),
        ParseCase("face", "0xFACE"),
        ParseCase("DEAD_beef_CAFE_babe", "0xDEADBEEFCAFEBABE"),
    ]

    @Test func testHexCases() {
        for tc in hexCases {
            let observed = BigInt.fromHex(tc.raw).toHexString()
            #expect(observed == tc.expected)
        }
    }

    // PORT-NOTE: `HexFormat` — Kotlin's `testHexFormatCases` relies on the Kotlin
    // stdlib `kotlin.HexFormat` type and a `toHexString(HexFormat)` overload.
    // Neither `HexFormat` nor a format-taking `toHexString` exists in the Swift
    // port (only the no-arg `toHexString()` -> "0x"-prefixed uppercase). No
    // Swift counterpart, so this case is not portable; omitted.
}
