import Testing
@testable import BigInt
@testable import BigIntMath

@Suite struct TestModMulSqr {

    @Test func modMul_basicSmall() {
        let m = BigInt.from(Int32(97))
        let ctx = ModContext(m)

        let out = MutableBigInt()

        ctx.modMul(BigInt.from(Int32(3)), BigInt.from(Int32(5)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(15)))

        ctx.modMul(BigInt.from(Int32(20)), BigInt.from(Int32(5)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(20 * 5 % 97)))
    }

    @Test func modMul_withReduction() {
        let m = BigInt.from(Int32(11))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modMul(BigInt.from(Int32(7)), BigInt.from(Int32(8)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(7 * 8 % 11)))
    }

    @Test func modMul_zeroAndOne() {
        let m = BigInt.from(Int32(101))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modMul(BigInt.from(Int32(0)), BigInt.from(Int32(42)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(0)))

        ctx.modMul(BigInt.from(Int32(1)), BigInt.from(Int32(42)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(42)))
    }

    @Test func modSqr_basic() {
        let m = BigInt.from(Int32(97))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modSqr(BigInt.from(Int32(5)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(25)))
    }

    @Test func modSqr_withReduction() {
        let m = BigInt.from(Int32(13))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modSqr(BigInt.from(Int32(7)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(7 * 7 % 13)))
    }

    @Test func modSqr_zeroAndOne() {
        let m = BigInt.from(Int32(101))
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modSqr(BigInt.from(Int32(0)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(0)))

        ctx.modSqr(BigInt.from(Int32(1)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(1)))
    }
}
