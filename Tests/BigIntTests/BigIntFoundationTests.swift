import Testing
@testable import BigInt

// Phase 2 foundation: BigInt construction, conversion, comparison — the
// engine-only API (no arithmetic / parsing yet).

@Suite struct BigIntFoundationTests {

    @Test func constants() {
        #expect(BigInt.ZERO.isZero())
        #expect(BigInt.ONE.toInt() == 1)
        #expect(BigInt.TWO.toInt() == 2)
        #expect(BigInt.NEG_ONE.toInt() == -1)
        #expect(BigInt.NEG_ONE.isNegative())
        #expect(BigInt.TEN.toInt() == 10)
        // TEN is now a valid 1-limb constant: magnitude ops must not crash.
        #expect(BigInt.TEN.magnitudeBitLen() == 4)        // 10 = 0b1010
        #expect(BigInt.TEN.compareTo(Int32(10)) == 0)
        #expect(BigInt.TEN == BigInt.from(Int32(10)))
    }

    @Test func fromIntRoundTrip() {
        let vals: [Int32] = [0, 1, -1, 42, -42, Int32.max, Int32.min, 123456, -999999]
        for n in vals {
            #expect(BigInt.from(n).toInt() == n)
        }
        #expect(BigInt.from(Int32(0)).isZero())
        #expect(BigInt.from(Int32(-5)).signumInt() == -1)
        #expect(BigInt.from(Int32(5)).signumInt() == 1)
        #expect(BigInt.from(Int32(0)).signumInt() == 0)
    }

    @Test func fromLongRoundTrip() {
        let vals: [Int64] = [0, 1, -1, Int64.max, Int64.min, 0x1_0000_0000, -0x1_0000_0000, 9_999_999_999]
        for l in vals {
            #expect(BigInt.from(l).toLong() == l)
        }
    }

    @Test func fromUnsigned() {
        #expect(BigInt.from(UInt32(0)).isZero())
        #expect(BigInt.from(UInt32.max).toUInt() == UInt32.max)
        #expect(BigInt.from(UInt64.max).toULong() == UInt64.max)
        #expect(BigInt.from(UInt64(0x1234_5678_9ABC_DEF0)).toULong() == 0x1234_5678_9ABC_DEF0)
    }

    @Test func comparisons() {
        let a = BigInt.from(Int64(100))
        let b = BigInt.from(Int64(200))
        let nb = BigInt.from(Int64(-200))
        #expect(a < b)
        #expect(nb < a)
        #expect(a == BigInt.from(Int32(100)))
        #expect(a.compareTo(Int32(100)) == 0)
        #expect(a.compareTo(Int64(200)) == -1)
        #expect(b.compareTo(Int32(100)) == 1)
        #expect(nb < BigInt.ZERO)
        #expect(BigInt.ZERO < a)
        #expect(nb.magnitudeCompareTo(b) == 0)   // |−200| == |200|
    }

    @Test func fitsAndParity() {
        #expect(BigInt.from(Int32.max).fitsInt())
        #expect(BigInt.from(Int64(Int64(Int32.max) + 1)).fitsInt() == false)
        #expect(BigInt.from(Int64.max).fitsLong())
        #expect(BigInt.from(UInt64.max).fitsLong() == false)
        #expect(BigInt.from(UInt64.max).fitsULong())
        #expect(BigInt.from(Int32(4)).isEven())
        #expect(BigInt.from(Int32(7)).isOdd())
        #expect(BigInt.ZERO.isEven())
    }

    @Test func copyConstructor() {
        let a = BigInt.from(Int64(0xDEAD_BEEF_CAFE))
        let b = BigInt.from(a as BigIntNumber)
        #expect(a == b)
        #expect(b.toLong() == 0xDEAD_BEEF_CAFE)
    }
}
