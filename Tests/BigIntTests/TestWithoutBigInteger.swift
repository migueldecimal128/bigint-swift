// SPDX-License-Identifier: MIT

import Testing
@testable import BigInt

@Suite struct TestWithoutBigInteger {

    @Test func test() {
        for _ in 0..<100 {
            test1()
        }
    }

    let rng = BigIntRandom.Default

    // PORT-NOTE: Kotlin's Random.nextUInt()/nextULong() have no BigIntRandom
    // shims; derive unsigned draws from the raw SplitMix64 bit source (next()),
    // truncating to width. This is a property test against an oracle, so only
    // the value ranges matter, not stream parity.
    private func nextUInt() -> UInt32 { UInt32(truncatingIfNeeded: rng.next()) }
    private func nextULong() -> UInt64 { rng.next() }

    func test1() {
        var hi1 = BigInt.ZERO
        var hi2 = BigInt.ZERO

        let n = rng.nextInt()
        hi1 = hi1 + n
        hi2 = hi2 - n + Int64(n) * 2
        #expect(hi2 == hi1)

        let w = nextUInt()
        let count = rng.nextInt(10)
        for _ in 0..<count {
            hi1 = hi1 + w
        }
        hi2 = hi2 + UInt64(w) * UInt64(count)
        #expect(hi2 == hi1)

        let l = rng.nextLong()
        hi1 = hi1 * l
        hi2 = hi2 * (l & ~Int64(1)) + ((l & 1) != 0 ? hi2 : BigInt.ZERO)
        #expect(hi2 == hi1)

        let dw = nextULong()
        hi1 = (hi1 * (dw >> 32)).shl(32) + hi1 * UInt32(truncatingIfNeeded: dw)
        hi2 = hi2 * dw
        #expect(hi2 == hi1)

        let exp = rng.nextInt(20)
        let t1 = hi1
        hi1 = BigInt.from(Int32(1))
        for _ in 0..<exp { hi1 = hi1 * t1 }
        hi2 = hi2.pow(Int(exp))
        #expect(hi2 == hi1)

        let dw2 = nextULong()
        if dw2 != 0 {
            let div = hi1 / dw2
            let mod = hi1 % dw2
            hi1 = div * dw2 + mod
            #expect(hi2 == hi1)
        }

        hi1 = hi1.sqr()
        hi2 = hi2 * hi2
        #expect(hi2 == hi1)

        #expect((-hi2).magnitudeBitLen() == hi1.magnitudeBitLen())

        var bitCount = 0
        for i in 0..<hi1.magnitudeBitLen() {
            if hi1.testBit(i) {
                bitCount += 1
            }
        }
        #expect(hi2.magnitudeCountOneBits() == bitCount)

        hi1 = hi1.abs()
        hi2 = hi2 - hi2
        for i in 0..<hi1.magnitudeBitLen() {
            if hi1.testBit(i) {
                switch rng.nextInt(3) {
                case 0: hi2 = hi2 + BigInt.withSetBit(i)
                case 1: hi2 = hi2.or(BigInt.withSetBit(i))
                case 2: hi2 = hi2.xor(BigInt.withSetBit(i))
                case 3: hi2 = hi2 + BigInt.ONE.shl(i)
                default: break
                }
            }
        }
        #expect(hi2 == hi1)

        #expect((hi1 + -hi2).compareTo(BigInt.ZERO) == 0)
        #expect((hi1 - hi2).compareTo(BigInt.ZERO) == 0)
        #expect((+hi1 - hi2).compareTo(BigInt.ZERO) == 0)
    }
}
