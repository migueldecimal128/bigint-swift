import Testing
@testable import BigInt

// MutableBigInt div/rem/mod verified against native Int128. Includes a focused
// probe of setDiv's 2-limb divisor path (which uses y.toULong()) on NEGATIVE
// divisors, to check the suspected sign asymmetry vs setRem.

@Suite struct MutableBigIntDivTests {

    private func big(_ v: Int128) -> BigInt {
        if v == 0 { return BigInt.ZERO }
        let neg = v < 0
        let mag = v.magnitude
        let m = Magia.make(5)
        for i in 0..<2 { m[i] = Limb(truncatingIfNeeded: mag >> (i * 64)) }
        return BigInt.fromNonNormalizedOrZero(neg, m)
    }
    private func i128(_ x: BigIntNumber) -> Int128 {
        var mag: UInt128 = 0
        var i = Int(x.meta.normLen) - 1
        while i >= 0 { mag = (mag << 64) | UInt128(x.magia[i]); i -= 1 }
        let s = Int128(mag)
        return x.isNegative() ? -s : s
    }
    private final class Rng {
        var s: UInt64 = 0x0DDB_A11D_EADC_0DE5
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

    @Test func divRem() {
        let rng = Rng()
        for _ in 0..<8000 {
            let a = rng.i128(126)
            var b = rng.i128(100); if b == 0 { b = 1 }
            #expect(i128(MutableBigInt().setDiv(big(a), big(b))) == a / b, "div \(a)/\(b)")
            #expect(i128(MutableBigInt().setRem(big(a), big(b))) == a % b, "rem \(a)%\(b)")
        }
    }

    @Test func divNegative2LimbDivisor() {
        // |a| > 2^64 (>=3 limbs), b is a NEGATIVE 2-limb divisor (|b| in [2^40, 2^63))
        let rng = Rng()
        for _ in 0..<8000 {
            let aMag = rng.u128(120) | (UInt128(1) << 70)
            let a: Int128 = (rng.next() & 1 == 1) ? -Int128(aMag) : Int128(aMag)
            var bMag = rng.u128(63) | (UInt128(1) << 40)
            if bMag == 0 { bMag = 1 }
            let b = -Int128(bMag)
            #expect(i128(MutableBigInt().setDiv(big(a), big(b))) == a / b, "div \(a)/\(b)")
            #expect(i128(MutableBigInt().setRem(big(a), big(b))) == a % b, "rem \(a)%\(b)")
        }
    }

    @Test func mod() {
        let rng = Rng()
        for _ in 0..<4000 {
            let a = rng.i128(126)
            var bm = rng.u128(100); if bm == 0 { bm = 1 }
            let b = Int128(bm)
            let r = a % b
            let expected = r < 0 ? r + b : r
            #expect(i128(MutableBigInt().setMod(big(a), big(b))) == expected, "mod \(a) mod \(b)")
        }
    }

    @Test func primitiveOperands() {
        let rng = Rng()
        for _ in 0..<4000 {
            let a = rng.i128(120)
            let n = Int32(truncatingIfNeeded: rng.next())
            let l = Int64(truncatingIfNeeded: rng.next())
            if n != 0 {
                #expect(i128(MutableBigInt().setDiv(MutableBigInt(big(a)), n)) == a / Int128(n))
                #expect(i128(MutableBigInt().setRem(big(a), n)) == a % Int128(n))
            }
            if l != 0 {
                #expect(i128(MutableBigInt().setDiv(MutableBigInt(big(a)), l)) == a / Int128(l))
                #expect(i128(MutableBigInt().setRem(big(a), l)) == a % Int128(l))
            }
        }
    }
}
