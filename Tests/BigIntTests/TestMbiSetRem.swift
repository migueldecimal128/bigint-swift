import Testing
@testable import BigInt

@Suite struct TestMbiSetRem {

    @Test func setRem_basic() {
        let x = BigInt.from("16943852051772892430707956759219").toMutableBigInt()
        let y = BigInt.from(16883797134507450982 as UInt64)

        let out = MutableBigInt()
        out.setRem(x, y)

        #expect(out.toBigInt() == x.toBigInt() % y)
    }

    @Test func setRem_alias_out_is_x() {
        let biX = BigInt.from("16943852051772892430707956759219")
        let x = MutableBigInt()
        let biY = BigInt.from(16883797134507450982 as UInt64)
        let y = biY.toMutableBigInt()

        x.set(biX)
        x.setRem(x, biY)
        #expect(x.toBigInt() == biX % biY)

        x.set(biX)
        x %= biY
        #expect(x.toBigInt() == biX % biY)

        x.set(biX)
        x.setRem(x, y)
        #expect(x.toBigInt() == biX % biY)

        x.set(biX)
        x %= y
        #expect(x.toBigInt() == biX % biY)
    }

    @Test func setRem_alias_out_is_y() {
        let xBi = BigInt.from("123456789012345678901234567890")
        let x = xBi.toMutableBigInt()
        let yBi = BigInt.from("9876543210987654321")
        let y = BigInt.from("9876543210987654321").toMutableBigInt()

        y.setRem(x, y)

        #expect(y.toBigInt() == xBi % yBi)
        #expect(x.toBigInt() == xBi)
    }

    @Test func setRem_alias_x_mod_x_is_zero() {
        let x = BigInt.from("123456789012345678901234567890").toMutableBigInt()

        x.setRem(x, x.toBigInt())

        #expect(x.toBigInt().isZero())
    }

    @Test func setRem_alias_small_divisor() {
        let x = BigInt.from("987654321098765432109876543210").toMutableBigInt()
        let y = BigInt.from(Int32(97))

        x.setRem(x, y)

        #expect(x.toBigInt() == BigInt.from("987654321098765432109876543210") % y)
    }

    @Test func setRem_invariants() {
        let x = BigInt.from("16943852051772892430707956759219").toMutableBigInt()
        let y = BigInt.from("16883797134507450982")

        let out = MutableBigInt()
        out.setRem(x, y)

        let r = out.toBigInt()
        #expect(r >= BigInt.ZERO)
        #expect(r < y.abs())
    }

    @Test func setRem_random_aliasing() {
        let rnd = BigIntRandom(Int64(1))

        for _ in 0..<1_000 {
            let a =
                BigInt.from(rnd.nextLong()).abs() +
                BigInt.from(rnd.nextLong()).abs().shl(64)

            var bl = rnd.nextLong()
            if bl == 0 { bl = 1 }
            let b = BigInt.from(bl).abs()

            let x = a.toMutableBigInt()
            let ref = a % b

            // out === x
            x.setRem(x, b)

            #expect(x.toBigInt() == ref)
        }
    }
}
