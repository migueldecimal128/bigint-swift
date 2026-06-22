import Testing
@testable import BigInt
@testable import BigIntMath

@Suite struct TestModPow {

    @Test func modPow_smallValues() {
        let m = BigInt.from(Int32(11))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modPow(BigInt.from(Int32(2)), BigInt.from(Int32(10)), out)
        // 2^10 = 1024 ≡ 1 (mod 11)
        #expect(out.toBigInt() == BigInt.from(Int32(1)))
    }

    @Test func modPow_expZero() {
        let m = BigInt.from(Int32(97))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modPow(BigInt.from(Int32(42)), BigInt.ZERO, out)
        #expect(out.toBigInt() == BigInt.ONE)
    }

    @Test func modPow_expOne() {
        let m = BigInt.from(Int32(101))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modPow(BigInt.from(Int32(77)), BigInt.ONE, out)
        #expect(out.toBigInt() == BigInt.from(Int32(77)))
    }

    @Test func modPow_baseZero() {
        let m = BigInt.from(Int32(13))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modPow(BigInt.ZERO, BigInt.from(Int32(5)), out)
        #expect(out.toBigInt() == BigInt.ZERO)
    }

    @Test func modPow_baseOne() {
        let m = BigInt.from(Int32(13))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modPow(BigInt.ONE, BigInt.from(Int32(12345)), out)
        #expect(out.toBigInt() == BigInt.ONE)
    }

    // PORT-NOTE: modPow_negativeExponent_throws — Kotlin assertFailsWith<IllegalArgumentException>;
    // Swift rejects negative exponents via precondition (fatalError, traps), which
    // swift-testing cannot catch. Dropped.

    @Test func modPow_resultIsReduced() {
        let m = BigInt.from(Int32(97))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modPow(BigInt.from(Int32(123456)), BigInt.from(Int32(789)), out)

        let r = out.toBigInt()
        #expect(r.compareTo(BigInt.ZERO) >= 0)
        #expect(r < m)
    }
}
