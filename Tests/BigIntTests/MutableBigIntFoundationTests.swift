import Testing
@testable import BigInt

// MutableBigInt foundation: constructors, setters, sign mutations, capacity
// hint, and toBigInt roundtrips — checked against the verified immutable BigInt.

@Suite struct MutableBigIntFoundationTests {

    @Test func constructorsAndToBigInt() {
        #expect(MutableBigInt().toBigInt() == BigInt.ZERO)
        for n: Int32 in [0, 1, -1, 42, -42, Int32.max, Int32.min] {
            #expect(MutableBigInt(n).toBigInt() == BigInt.from(n))
        }
        for l: Int64 in [0, 1, -1, Int64.max, Int64.min, 0x1234_5678_9ABC] {
            #expect(MutableBigInt(l).toBigInt() == BigInt.from(l))
        }
        #expect(MutableBigInt(UInt64.max).toBigInt() == BigInt.from(UInt64.max))
        #expect(MutableBigInt(UInt32(0xFFFF_FFFF)).toBigInt() == BigInt.from(UInt32(0xFFFF_FFFF)))
    }

    @Test func setters() {
        let m = MutableBigInt()
        #expect(m.set(Int64(-12345)).toBigInt() == BigInt.from(Int64(-12345)))
        #expect(m.set(UInt64(0xDEAD_BEEF_CAFE)).toBigInt().toLong() == 0xDEAD_BEEF_CAFE)
        m.setZero()
        #expect(m.isZero())
        m.setOne()
        #expect(m.toBigInt() == BigInt.ONE)
        // 128-bit setter: hi=1, lo=2 -> -(2^64 + 2)
        m.set(true, UInt64(1), UInt64(2))
        #expect(m.isNegative())
        #expect(m.meta.normLen == 2)               // bitLen 65 -> 2 64-bit limbs
        #expect(m.toULongMagnitude() == 2)         // low 64 bits
        // cross-check against BigInt arithmetic: 2^64 == (2^32)*(2^32)
        let twoTo64 = BigInt.from(UInt64(1) << 32) * BigInt.from(UInt64(1) << 32)
        #expect(m.toBigInt() == (twoTo64 + BigInt.from(Int32(2))).negate())
    }

    @Test func signMutations() {
        let m = MutableBigInt(Int64(77))
        m.mutNegate()
        #expect(m.toBigInt() == BigInt.from(Int64(-77)))
        m.mutAbs()
        #expect(m.toBigInt() == BigInt.from(Int64(77)))
        m.mutWithSign(true)
        #expect(m.toBigInt() == BigInt.from(Int64(-77)))
        m.setZero().mutNegate()
        #expect(m.isZero())   // no negative zero
    }

    @Test func setFromBigInt() {
        let big = BigInt.from(Int64(-999_999_999_999))
        let m = MutableBigInt()
        m.set(big as BigIntNumber)
        #expect(m.toBigInt() == big)
        #expect(m.compareTo(big) == 0)
    }

    @Test func capacityHint() {
        let m = MutableBigInt.withBitCapacityHint(4096)
        #expect(m.isZero())
        #expect(m.getHintBitCapacity() >= 4096)
        #expect(m.didExceedHint() == false)
        _ = m.hintBitCapacity(8192)
        #expect(m.getHintBitCapacity() >= 8192)
    }
}
