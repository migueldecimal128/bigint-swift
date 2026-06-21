// SPDX-License-Identifier: MIT

import Testing
@testable import BigInt

@Suite struct TestHashCode {

    // PORT-NOTE: Kotlin uses BigInt.hashCode() = the JVM Int32
    //   31 * isNegative.hashCode() + magnitudeHashCode()
    // (Boolean.hashCode = 1231 / 1237). Swift's `hashValue` is a per-run salted
    // Int and is NOT this value, so the bit-exact arithmetic these tests perform
    // (subtracting 31 * boolean hash) is reproduced via this helper against the
    // bit-identical magnitudeHashCode() the port exposes.
    private func biHashCode(_ x: BigInt) -> Int32 {
        31 &* (x.isNegative() ? 1231 : 1237) &+ x.magnitudeHashCode()
    }
    // Kotlin Boolean.hashCode(): true -> 1231, false -> 1237.
    private func boolHashCode(_ b: Bool) -> Int32 { b ? 1231 : 1237 }

    let verbose = false

    @Test func testSignHashCode() {
        let trueHashCode = boolHashCode(true)
        let falseHashCode = boolHashCode(false)
        #expect(trueHashCode == 1231)
        #expect(falseHashCode == 1237)
    }

    let rng = BigIntRandom.Default

    @Test func testPosNegHash() {
        for _ in 0..<1000 {
            let hiPos = BigInt.randomWithMaxBitLen(Int(rng.nextInt(10)))
            // hiNeg will not be negative in the case of zero
            let hiNeg = hiPos.negate()
            #expect((hiNeg + hiPos).EQ(Int32(0)))

            let hashPos = biHashCode(hiPos)
            let hashNeg = biHashCode(hiNeg)

            let hashPosMag = hashPos &- (31 &* boolHashCode(false))
            // hiNeg will not be negative in the case of zero
            let hashNegMag = hashNeg &- (31 &* boolHashCode(hiNeg.isNegative()))

            #expect(hashPosMag == hashNegMag)
        }
    }

    @Test func testNonNormalized() {
        for _ in 0..<1000 {
            let biPos = BigInt.randomWithMaxBitLen(Int(rng.nextInt(500)))
            if biPos.isZero() {
                continue
            }
            let biggerBitLen = biPos.magnitudeBitLen() + Int(rng.nextInt(1000)) + 32
            // subtraction will generate non-normalized BigInt magia
            // arrays ... which are not SuperNormal
            let bigger = BigInt.withSetBit(biggerBitLen)
            let biPos2 = (bigger + biPos) - bigger

            #expect(biPos2 == biPos)
            #expect(biHashCode(biPos2) == biHashCode(biPos))
        }
    }

    @Test func testProblem1() {
        let biPos = BigInt.from(Int64(1785))
        let bigger = BigInt.from(Int64(281474976710656))
        let biPos2 = (bigger + biPos) - bigger
        #expect(biPos2 == biPos)
    }
}
