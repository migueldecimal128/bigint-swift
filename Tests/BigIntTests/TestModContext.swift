import Testing
@testable import BigInt

@Suite struct TestModContext {

    private func refMod(_ a: Int64, _ m: Int64) -> Int64 {
        ((a % m) + m) % m
    }

    // PORT-NOTE: testConstruction's `assertFailsWith<IllegalArgumentException>`
    // cases — ModContext(0) / ModContext(-5) trigger `fatalError()` in Swift,
    // which swift-testing cannot catch; only the success assertion is ported.
    @Test func testConstruction() {
        let ctx = ModContext(BigInt.from(Int32(17)))
        #expect(ctx.m == BigInt.from(Int32(17)))
    }

    @Test func testModSetBigInt() {
        let ctx = ModContext(BigInt.from(Int32(17)))
        let out = MutableBigInt()

        ctx.modSet(BigInt.from(Int32(5)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(5)))

        ctx.modSet(BigInt.from(Int32(25)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(8)))

        ctx.modSet(BigInt.from(Int32(-3)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(14)))
    }

    @Test func testModSetIntAndLong() {
        let ctx = ModContext(BigInt.from(Int32(17)))
        let out = MutableBigInt()

        ctx.modSet(Int32(3), out)
        #expect(out.toBigInt() == BigInt.from(Int32(3)))

        ctx.modSet(Int32(20), out)  // Int path
        #expect(out.toBigInt() == BigInt.from(Int32(3)))

        ctx.modSet(Int64(20), out)
        #expect(out.toBigInt() == BigInt.from(Int32(3)))

        ctx.modSet(Int64(-5), out)
        #expect(out.toBigInt() == BigInt.from(Int32(12)))
    }

    @Test func testModAdd() {
        let ctx = ModContext(BigInt.from(Int32(17)))
        let out = MutableBigInt()

        ctx.modAdd(BigInt.from(Int32(5)), BigInt.from(Int32(7)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(12)))

        ctx.modAdd(BigInt.from(Int32(15)), Int32(5), out)
        #expect(out.toBigInt() == BigInt.from(Int32(3))) // 20 mod 17 = 3

        ctx.modAdd(BigInt.from(Int32(15)), Int64(12), out)
        #expect(out.toBigInt() == BigInt.from(Int32(10))) // 27 mod 17 = 10
    }

    @Test func testModSub() {
        let ctx = ModContext(BigInt.from(Int32(17)))
        let out = MutableBigInt()

        ctx.modSub(BigInt.from(Int32(5)), BigInt.from(Int32(7)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(15))) // -2 -> 15

        ctx.modSub(BigInt.from(Int32(4)), Int32(8), out)
        #expect(out.toBigInt() == BigInt.from(Int32(13)))

        ctx.modSub(BigInt.from(Int32(4)), Int64(21), out)
        #expect(out.toBigInt() == BigInt.from(Int32(Int32(refMod(4 - 21, 17)))))
    }

    @Test func testModMul() {
        let ctx = ModContext(BigInt.from(Int32(17)))
        let out = MutableBigInt()

        ctx.modMul(BigInt.from(Int32(3)), BigInt.from(Int32(5)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(15)))

        ctx.modMul(BigInt.from(Int32(3)), Int32(20), out)  // Int overload
        #expect(out.toBigInt() == BigInt.from(Int32(9))) // 60 mod 17 = 9

        ctx.modMul(BigInt.from(Int32(6)), Int64(30), out)
        #expect(out.toBigInt() == BigInt.from(Int32(Int32(refMod(6 * 30, 17)))))
    }

    @Test func testModSqr() {
        let ctx = ModContext(BigInt.from(Int32(17)))
        let out = MutableBigInt()

        ctx.modSqr(BigInt.from(Int32(6)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(2))) // 36 mod 17 = 2
    }

    @Test func testModPowOddUsesMontgomery() {
        let m = BigInt.from(Int32(97)) // odd modulus
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modPow(BigInt.from(Int32(5)), BigInt.from(Int32(117)), out)
        let expected = (BigInt.from(Int32(5)).pow(117) % m)
        #expect(out.toBigInt() == expected)
    }

    @Test func testModPowEvenUsesBarrettFallback() {
        let m = BigInt.from(Int32(100)) // even modulus
        let ctx = ModContext(m)
        let out = MutableBigInt()

        ctx.modPow(BigInt.from(Int32(7)), BigInt.from(Int32(45)), out)
        let expected = (BigInt.from(Int32(7)).pow(45) % m)
        #expect(out.toBigInt() == expected)
    }

    @Test func testModInv() {
        let ctx = ModContext(BigInt.from(Int32(17)))
        let out = MutableBigInt()

        ctx.modInv(BigInt.from(Int32(5)), out)
        #expect(out.toBigInt() == BigInt.from(Int32(7))) // 5*7=35 mod 17 = 1
    }

    // PORT-NOTE: testModInvNotInvertible — modInv on a non-invertible argument
    // triggers `fatalError("not invertible")` in Swift, which swift-testing
    // cannot catch; the assertFailsWith case is dropped.

    @Test func testModHalfLucas() {
        let ctx = ModContext(BigInt.from(Int32(17)))
        let out = MutableBigInt()

        let a = MutableBigInt().set(Int32(5)) // odd
        ctx.modHalfLucas(a, out)
        #expect(out.toBigInt() == BigInt.from(Int32(11))) // (5+17)/2 = 11

        a.set(Int32(8)) // even
        ctx.modHalfLucas(a, out)
        #expect(out.toBigInt() == BigInt.from(Int32(4)))
    }
}
