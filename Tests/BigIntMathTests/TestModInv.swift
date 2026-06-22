import Testing
@testable import BigInt
@testable import BigIntMath

@Suite struct TestModInv {

    @Test func modInv_basicSmall() {
        let m = BigInt.from(Int32(11))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modInv(BigInt.from(Int32(7)), out)
        // 7 * 8 ≡ 1 (mod 11)
        #expect(out.toBigInt() == BigInt.from(Int32(8)))
    }

    @Test func modInv_ofOne() {
        let m = BigInt.from(Int32(97))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modInv(BigInt.ONE, out)
        #expect(out.toBigInt() == BigInt.ONE)
    }

    @Test func modInv_negativeResultNormalized() {
        let m = BigInt.from(Int32(13))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        // inverse of 10 mod 13 is 4
        ctx.modInv(BigInt.from(Int32(10)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(4)))
    }

    // PORT-NOTE: modInv_notInvertible_throws — modInv(14) mod 21 triggers
    // `fatalError("not invertible")` in Swift, which swift-testing cannot catch;
    // the assertFailsWith<ArithmeticException> case (and its message check) is
    // dropped.

    // PORT-NOTE: modInv_zero_throws — modInv(0) violates the `!a.isNegative()
    // && a < m`... actually 0 is in range, but modInv on 0 reaches the
    // `not invertible` fatalError; swift-testing cannot catch fatalError, so
    // the assertFailsWith<ArithmeticException> case is dropped.
}
