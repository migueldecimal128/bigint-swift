import Testing
@testable import BigInt

// Parse/print: the human-readable oracle. Cross-checks toString against native
// Int128's decimal string, decimal/hex roundtrips, and large (>128-bit) values.

@Suite struct ParsePrintTests {

    private func big(_ v: Int128) -> BigInt {
        if v == 0 { return BigInt.ZERO }
        let neg = v < 0
        let mag = v.magnitude
        let m = Magia.make(5)
        for i in 0..<2 { m[i] = Limb(truncatingIfNeeded: mag >> (i * 64)) }
        return BigInt.fromNonNormalizedOrZero(neg, m)
    }
    private final class Rng {
        var s: UInt64 = 0xFEED_FACE_CAFE_BEEF
        func next() -> UInt64 {
            s = s &+ 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        func i128(_ bits: Int) -> Int128 {
            var v: UInt128 = 0
            for i in 0..<2 { v |= UInt128(next()) << (i * 64) }
            if bits < 128 { v &= (UInt128(1) << bits) - 1 }
            return (next() & 1 == 1) ? -Int128(v) : Int128(v)
        }
    }

    @Test func knownDecimals() {
        #expect(BigInt.from("0").toString() == "0")
        #expect(BigInt.from("12345").toString() == "12345")
        #expect(BigInt.from("-678").toString() == "-678")
        #expect(BigInt.from("+99").toString() == "99")
        #expect(BigInt.from("007").toString() == "7")
        #expect(BigInt.from("000").toString() == "0")
        #expect(BigInt.from("1_000_000").toString() == "1000000")
        #expect(BigInt.ZERO.toString() == "0")
        #expect(BigInt.ONE.toString() == "1")
        #expect(BigInt.NEG_ONE.toString() == "-1")
        #expect(BigInt.TEN.toString() == "10")
    }

    @Test func knownHex() {
        #expect(BigInt.fromHex("0xFF").toString() == "255")
        #expect(BigInt.from("0xFF").toString() == "255")          // from() auto-detects 0x
        #expect(BigInt.from("0X1_0000_0000").toString() == "4294967296")
        #expect(BigInt.from("-0xA").toString() == "-10")
        #expect(BigInt.from("255").toHexString() == "0xFF")
        #expect(BigInt.from("-255").toHexString() == "-0xFF")
        #expect(BigInt.ZERO.toHexString() == "0x0")
        #expect(BigInt.from("0xDEADBEEFCAFE").toHexString() == "0xDEADBEEFCAFE")
    }

    @Test func int128RoundTrip() {
        let rng = Rng()
        for _ in 0..<10000 {
            let a = rng.i128(127)
            let s = String(a)                          // native decimal
            #expect(big(a).toString() == s)            // print matches native
            #expect(BigInt.from(s).toString() == s)    // parse -> print identity
        }
    }

    @Test func largeDecimalRoundTrip() {
        let rng = Rng()
        for _ in 0..<3000 {
            // canonical decimal string (no leading zeros), up to 100 digits
            let nd = Int(rng.next() % 100) + 1
            var s = String(1 + rng.next() % 9)
            for _ in 1..<nd { s.append(Character(String(rng.next() % 10))) }
            if rng.next() & 1 == 1 { s = "-" + s }
            #expect(BigInt.from(s).toString() == s)
        }
    }

    @Test func mulPrintVsInt128() {
        let rng = Rng()
        for _ in 0..<6000 {
            let a = rng.i128(60), b = rng.i128(60)
            #expect((big(a) * big(b)).toString() == String(a * b))
            #expect((big(a) - big(b)).toString() == String(a - b))
        }
    }

    @Test func powersOfTenAndBeyond128() {
        var p = BigInt.ONE
        for k in 1...80 {
            p = p * BigInt.TEN
            #expect(p.toString() == "1" + String(repeating: "0", count: k))
        }
        // 2^256 via repeated squaring of from-string, roundtrip
        var q = BigInt.from("2")
        for _ in 0..<8 { q = q * q }   // 2^256
        let s = q.toString()
        #expect(BigInt.from(s).toString() == s)   // roundtrip a 78-digit value
        #expect(q.toHexString() == "0x1" + String(repeating: "0", count: 64))  // 2^256 = 1 followed by 64 hex 0s
    }
}
