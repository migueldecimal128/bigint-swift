import Testing
@testable import BigInt

@Suite struct ModContextTests {

    private final class Rng {
        var s: UInt64 = 0x0C0F_FEE0_BEEF_1234
        func next() -> UInt64 {
            s = s &+ 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        /// Random non-negative BigInt of up to `nLimbs` limbs (top limb may be 0).
        func bigMag(_ nLimbs: Int) -> BigInt {
            let m = Magia(nLimbs + 1)
            for i in 0..<nLimbs { m[i] = Limb(truncatingIfNeeded: next()) }
            return BigInt.fromNonNormalizedOrZero(false, m)
        }
    }

    // Independent oracle: left-to-right modular exponentiation with BigInt %.
    private func refModPow(_ base: BigInt, _ exp: BigInt, _ m: BigInt) -> BigInt {
        var result = BigInt.ONE % m
        let b = base % m
        let bitLen = exp.magnitudeBitLen()
        if bitLen == 0 { return result }
        var i = bitLen - 1
        while i >= 0 {
            result = (result * result) % m
            if exp.testBit(i) { result = (result * b) % m }
            i -= 1
        }
        return result
    }

    @Test func modMulSqrAddSub() {
        let rng = Rng()
        for _ in 0..<4000 {
            var m = rng.bigMag(3)
            if m.compareTo(Int32(2)) < 0 { m = BigInt.from(Int32(2)) }
            let a = rng.bigMag(3) % m
            let b = rng.bigMag(3) % m
            let ctx = ModContext(m)
            let out = MutableBigInt()
            ctx.modMul(a, b, out)
            #expect(out.toBigInt() == (a * b) % m, "modMul")
            ctx.modSqr(a, out)
            #expect(out.toBigInt() == (a * a) % m, "modSqr")
            ctx.modAdd(a, b, out)
            #expect(out.toBigInt() == (a + b) % m, "modAdd")
            ctx.modSub(a, b, out)
            // (a - b) mod m, normalized non-negative
            let sub = (a - b)
            #expect(out.toBigInt() == (sub.isNegative() ? sub + m : sub) % m, "modSub")
        }
    }

    @Test func modPowSmallExp() {
        let rng = Rng()
        for _ in 0..<3000 {
            var m = rng.bigMag(3)
            if m.compareTo(Int32(2)) < 0 { m = BigInt.from(Int32(2)) }
            let base = rng.bigMag(3) % m
            let exp = Int(rng.next() % 300)
            let ctx = ModContext(m)         // odd m -> Montgomery, even m -> Barrett
            let out = MutableBigInt()
            ctx.modPow(base, exp, out)
            #expect(out.toBigInt() == refModPow(base, BigInt.from(Int32(Int32(exp))), m), "modPow exp=\(exp)")
        }
    }

    @Test func modPowBigExp() {
        let rng = Rng()
        for _ in 0..<800 {
            // odd modulus (exercises Montgomery sliding window)
            var m = rng.bigMag(4)
            if m.isEven() { m = m + BigInt.ONE }
            if m.compareTo(Int32(3)) < 0 { m = BigInt.from(Int32(3)) }
            let base = rng.bigMag(4) % m
            let exp = rng.bigMag(4)         // up to ~128-bit exponent
            let ctx = ModContext(m)
            let out = MutableBigInt()
            ctx.modPow(base, exp, out)
            #expect(out.toBigInt() == refModPow(base, exp, m), "modPow big exp")
        }
    }

    @Test func modPowBarrettForcedEven() {
        let rng = Rng()
        for _ in 0..<800 {
            var m = rng.bigMag(4)
            if m.isOdd() { m = m + BigInt.ONE }       // even -> Barrett path
            if m.compareTo(Int32(2)) < 0 { m = BigInt.from(Int32(2)) }
            let base = rng.bigMag(4) % m
            let exp = rng.bigMag(3)
            let ctx = ModContext(m)
            let out = MutableBigInt()
            ctx.modPow(base, exp, out)
            #expect(out.toBigInt() == refModPow(base, exp, m), "Barrett modPow")
        }
    }

    @Test func modInv() {
        let rng = Rng()
        var tested = 0
        for _ in 0..<4000 {
            var m = rng.bigMag(3)
            if m.compareTo(Int32(2)) < 0 { m = BigInt.from(Int32(2)) }
            let a = rng.bigMag(3) % m
            if a.isZero() { continue }
            if BigInt.gcd(a, m) != BigInt.ONE { continue }   // must be coprime
            let ctx = ModContext(m)
            let out = MutableBigInt()
            ctx.modInv(a, out)
            #expect((a * out.toBigInt()) % m == BigInt.ONE % m, "a*inv % m == 1")
            tested += 1
        }
        #expect(tested > 100)
    }
}
