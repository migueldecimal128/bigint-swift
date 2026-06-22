import Testing
@testable import BigInt

// MutableBigInt add/sub/mul/shift verified against native Int128 (operands
// bounded so results fit), including self-aliased operations.

@Suite struct MutableBigIntArithTests {

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
        var s: UInt64 = 0xAB1A_CADA_1234_9876
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

    @Test func addSubMul() {
        let rng = Rng()
        for _ in 0..<6000 {
            let a = rng.i128(120), b = rng.i128(120)
            #expect(i128(MutableBigInt().setAdd(big(a), big(b))) == a + b)
            #expect(i128(MutableBigInt().setSub(big(a), big(b))) == a - b)
            let a2 = rng.i128(60), b2 = rng.i128(60)
            #expect(i128(MutableBigInt().setMul(big(a2), big(b2))) == a2 * b2)
        }
    }

    @Test func primitiveOperands() {
        let rng = Rng()
        for _ in 0..<4000 {
            let a = rng.i128(60)
            let x = big(a)
            let n = Int32(truncatingIfNeeded: rng.next())
            let dw = rng.next()
            #expect(i128(MutableBigInt().setAdd(x, n)) == a + Int128(n))
            #expect(i128(MutableBigInt().setSub(x, n)) == a - Int128(n))
            #expect(i128(MutableBigInt().setMul(x, dw)) == a * Int128(dw))
        }
    }

    @Test func shifts() {
        let rng = Rng()
        for _ in 0..<4000 {
            let a = rng.i128(60)
            let x = big(a)
            let k = Int(rng.next() % 60)          // 0..59 — incl. ushr(_, 0) -> |x| (fixed)
            #expect(i128(MutableBigInt().setShl(x, k)) == a << k)            // a*2^k, sign kept
            #expect(i128(MutableBigInt().setUshr(x, k)) == Int128(a.magnitude >> UInt128(k)))
            #expect(i128(MutableBigInt().setShr(x, k)) == a >> k)            // arithmetic (toward -inf)
        }
    }

    @Test func selfAliasing() {
        let rng = Rng()
        for _ in 0..<2000 {
            let a = rng.i128(100)
            let m = MutableBigInt(); m.set(big(a) as BigIntNumber)
            m.setAdd(m, m)                       // self-add -> 2a
            #expect(i128(m) == a + a)

            let a2 = rng.i128(50)
            let m2 = MutableBigInt(); m2.set(big(a2) as BigIntNumber)
            m2.setMul(m2, m2)                    // self-mul -> a^2
            #expect(i128(m2) == a2 * a2)

            let a3 = rng.i128(60)
            let m3 = MutableBigInt(); m3.set(big(a3) as BigIntNumber)
            m3.mutShl(10)                        // in-place shift
            #expect(i128(m3) == a3 << 10)
        }
    }
}
