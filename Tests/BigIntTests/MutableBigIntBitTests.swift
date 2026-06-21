import Testing
@testable import BigInt

// MutableBigInt bit ops vs UInt128. and/or/xor act on magnitudes (non-negative
// result); setBit/clearBit/applyBitMask act on the magnitude, keeping sign.

@Suite struct MutableBigIntBitTests {

    private func big(_ v: Int128) -> BigInt {
        if v == 0 { return BigInt.ZERO }
        let neg = v < 0
        let mag = v.magnitude
        let m = Magia(5)
        for i in 0..<4 { m[i] = Limb(truncatingIfNeeded: mag >> (i * 32)) }
        return BigInt.fromNonNormalizedOrZero(neg, m)
    }
    private func bigU(_ mag: UInt128) -> BigInt { big(Int128(mag)) }   // non-negative
    private func u128mag(_ x: BigIntNumber) -> UInt128 {
        var mag: UInt128 = 0
        var i = Int(x.meta.normLen) - 1
        while i >= 0 { mag = (mag << 32) | UInt128(x.magia[i]); i -= 1 }
        return mag
    }
    private func i128(_ x: BigIntNumber) -> Int128 {
        let s = Int128(u128mag(x))
        return x.isNegative() ? -s : s
    }

    private final class Rng {
        var s: UInt64 = 0xB17B_A5E0_F00D_1234
        func next() -> UInt64 {
            s = s &+ 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        func u128(_ bits: Int) -> UInt128 {
            var v: UInt128 = 0
            for i in 0..<4 { v |= UInt128(Limb(truncatingIfNeeded: next())) << (i * 32) }
            if bits < 128 { v &= (UInt128(1) << bits) - 1 }
            return v
        }
        func i128(_ bits: Int) -> Int128 {
            let mag = u128(bits)
            return (next() & 1 == 1) ? -Int128(mag) : Int128(mag)
        }
    }

    @Test func andOrXor() {
        let rng = Rng()
        for _ in 0..<6000 {
            let a = rng.i128(120), b = rng.i128(120)
            let am = a.magnitude, bm = b.magnitude
            #expect(u128mag(MutableBigInt().setAnd(big(a), big(b))) == (am & bm))
            #expect(u128mag(MutableBigInt().setOr(big(a), big(b))) == (am | bm))
            #expect(u128mag(MutableBigInt().setXor(big(a), big(b))) == (am ^ bm))
            // results are non-negative
            #expect(MutableBigInt().setAnd(big(a), big(b)).isPositive())
        }
    }

    @Test func mutAndOrXorAliasing() {
        let rng = Rng()
        for _ in 0..<2000 {
            let a = rng.u128(120), b = rng.u128(120)
            let m = MutableBigInt(); m.set(bigU(a) as BigIntNumber)
            m.mutAnd(bigU(b))
            #expect(u128mag(m) == (a & b))
            // self-xor -> zero
            let m2 = MutableBigInt(); m2.set(bigU(a) as BigIntNumber)
            m2.mutXor(m2)
            #expect(m2.isZero())
        }
    }

    @Test func setClearBit() {
        let rng = Rng()
        for _ in 0..<4000 {
            let a = rng.u128(110)
            let k = Int(rng.next() % 126)
            let m = MutableBigInt(); m.set(bigU(a) as BigIntNumber)
            m.setBit(k)
            #expect(u128mag(m) == (a | (UInt128(1) << k)))
            let m2 = MutableBigInt(); m2.set(bigU(a) as BigIntNumber)
            m2.clearBit(k)
            #expect(u128mag(m2) == (a & ~(UInt128(1) << k)))
        }
    }

    @Test func applyBitMask() {
        let rng = Rng()
        for _ in 0..<4000 {
            let a = rng.u128(120)
            let index = Int(rng.next() % 100)
            let width = Int(rng.next() % 40)
            let m = MutableBigInt(); m.set(bigU(a) as BigIntNumber)
            m.applyBitMask(width, index)
            let mask: UInt128 = width == 0 ? 0 : (((UInt128(1) << width) - 1) << index)
            #expect(u128mag(m) == (a & mask), "applyBitMask(w=\(width), i=\(index)) on \(a)")
        }
    }
}
