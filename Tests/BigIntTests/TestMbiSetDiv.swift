import Testing
@testable import BigInt

@Suite struct TestMbiSetDiv {

    @Test func setDiv_basic() {
        let xBi = BigInt.from("16943852051772892430707956759219")
        let x = xBi.toMutableBigInt()
        let y = BigInt.from(16883797134507450982 as UInt64)

        let out = MutableBigInt()
        out.setDiv(x, y)

        #expect(out.toBigInt() == xBi / y)
    }

    @Test func setDiv_alias_out_is_x() {
        let biX = BigInt.from("16943852051772892430707956759219")
        let x = MutableBigInt()
        let biY = BigInt.from(16883797134507450982 as UInt64)
        let y = biY.toMutableBigInt()

        x.set(biX)
        x.setDiv(x, biY)
        #expect(x.toBigInt() == biX / biY)

        x.set(biX)
        x /= biY
        #expect(x.toBigInt() == biX / biY)

        x.set(biX)
        x.setDiv(x, y)
        #expect(x.toBigInt() == biX / biY)

        x.set(biX)
        x /= y
        #expect(x.toBigInt() == biX / biY)
    }

    @Test func setDiv_alias_out_is_divisor() {
        let xBi = BigInt.from("123456789012345678901234567890")
        let x = xBi.toMutableBigInt()

        let yBi = BigInt.from("9876543210987654321")
        let y = yBi.toMutableBigInt()

        y.setDiv(x, y)

        #expect(y.toBigInt() == xBi / yBi)
        #expect(x.toBigInt() == xBi)
    }

    @Test func setDiv_alias_small_divisor() {
        let xBi = BigInt.from("987654321098765432109876543210")
        let x = xBi.toMutableBigInt()
        let y = BigInt.from(Int32(97))

        x.setDiv(x, y)

        #expect(x.toBigInt() == xBi / y)
    }

    @Test func setDiv_invariant_reconstruction() {
        let xBi = BigInt.from("16943852051772892430707956759219")
        let x = xBi.toMutableBigInt()
        let y = BigInt.from("16883797134507450982")

        let q = MutableBigInt()
        q.setDiv(x, y)

        let r = MutableBigInt()
        r.setRem(x, y)

        #expect(q.toBigInt() * y + r.toBigInt() == xBi)
    }

    @Test func setDiv_random_aliasing() {
        let rnd = BigIntRandom(Int64(2))

        for _ in 0..<1_000 {
            let a =
                BigInt.from(rnd.nextLong()).abs() +
                BigInt.from(rnd.nextLong()).abs().shl(64)

            var bl = rnd.nextLong()
            if bl == 0 { bl = 1 }
            let b = BigInt.from(bl).abs()

            let x = a.toMutableBigInt()
            let ref = a / b

            // out === x
            x.setDiv(x, b)

            #expect(x.toBigInt() == ref)
        }
    }
}
