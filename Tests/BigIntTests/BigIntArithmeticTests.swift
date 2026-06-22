import Testing
@testable import BigInt

// BigInt signed arithmetic verified against native Int128 over a deterministic
// randomized sweep. Operand magnitudes are bounded so the true-math results fit
// in Int128 (no oracle overflow). Multi-limb operands are built directly from
// Int128 (independent of BigInt's own arithmetic).

@Suite struct BigIntArithmeticTests {

    // Int128 <-> BigInt (up to 4 limbs), sign-magnitude.
    private func big(_ v: Int128) -> BigInt {
        if v == 0 { return BigInt.ZERO }
        let neg = v < 0
        let mag = v.magnitude            // UInt128
        let m = Magia.make(5)
        for i in 0..<2 { m[i] = Limb(truncatingIfNeeded: mag >> (i * 64)) }
        return BigInt.fromNonNormalizedOrZero(neg, m)
    }

    private func i128(_ x: BigInt) -> Int128 {
        var mag: UInt128 = 0
        var i = Int(x.meta.normLen) - 1
        while i >= 0 { mag = (mag << 64) | UInt128(x.magia[i]); i -= 1 }
        let s = Int128(mag)              // magnitude fits (< 2^127) for our operands
        return x.isNegative() ? -s : s
    }

    private final class Rng {
        var s: UInt64 = 0x5DEE_CE66_D00D_F00D
        func next() -> UInt64 {
            s = s &+ 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        func u128(_ bits: Int) -> UInt128 {
            var v: UInt128 = 0
            for i in 0..<2 { v |= UInt128(next()) << (i * 64) }
            if bits < 128 { v &= (UInt128(1) << bits) - 1 }
            return v
        }
        func i128(_ bits: Int) -> Int128 {
            let mag = u128(bits)
            return (next() & 1 == 1) ? -Int128(mag) : Int128(mag)
        }
    }

    @Test func addSub() {
        let rng = Rng()
        for _ in 0..<8000 {
            let a = rng.i128(120), b = rng.i128(120)
            #expect(i128(big(a) + big(b)) == a + b)
            #expect(i128(big(a) - big(b)) == a - b)
        }
    }

    @Test func mul() {
        let rng = Rng()
        for _ in 0..<8000 {
            let a = rng.i128(60), b = rng.i128(60)
            #expect(i128(big(a) * big(b)) == a * b)
        }
    }

    @Test func divRem() {
        let rng = Rng()
        for _ in 0..<8000 {
            let a = rng.i128(126)
            var b = rng.i128(100)
            if b == 0 { b = 1 }
            #expect(i128(big(a) / big(b)) == a / b, "div \(a)/\(b)")
            #expect(i128(big(a) % big(b)) == a % b, "rem \(a)%\(b)")
        }
    }

    @Test func modNonNegative() {
        let rng = Rng()
        for _ in 0..<4000 {
            let a = rng.i128(126)
            var b = rng.u128(100)
            if b == 0 { b = 1 }
            let bi = Int128(b)
            let r = a % bi
            let expected = r < 0 ? r + bi : r        // non-negative remainder
            #expect(i128(big(a).mod(big(bi))) == expected, "mod \(a) mod \(bi)")
        }
    }

    @Test func primitiveOperands() {
        let rng = Rng()
        for _ in 0..<4000 {
            let a = rng.i128(60)   // bounded so a*l (l up to 64-bit) fits Int128
            let n = Int32(truncatingIfNeeded: rng.next())
            let l = Int64(truncatingIfNeeded: rng.next())
            #expect(i128(big(a) + n) == a + Int128(n))
            #expect(i128(big(a) - n) == a - Int128(n))
            #expect(i128(big(a) * n) == a * Int128(n))
            #expect(i128(big(a) + l) == a + Int128(l))
            #expect(i128(big(a) * l) == a * Int128(l))
            if n != 0 { #expect(i128(big(a) / n) == a / Int128(n)) }
            if l != 0 {
                #expect(i128(big(a) / l) == a / Int128(l))
                #expect(i128(big(a) % l) == a % Int128(l))
            }
        }
    }

    @Test func negateAbsSignEdges() {
        #expect(i128(-big(123)) == -123)
        #expect(i128(big(-77).abs()) == 77)
        #expect((big(0)).isZero())
        #expect(i128(big(5) - big(5)) == 0)
        #expect((big(5) - big(5)).isZero())
        #expect(i128(big(-10) / big(3)) == -3)   // truncation toward zero
        #expect(i128(big(-10) % big(3)) == -1)   // rem sign of dividend
        #expect(i128(big(-10).mod(big(3))) == 2) // mod non-negative
    }
}
