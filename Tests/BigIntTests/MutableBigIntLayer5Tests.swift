import Testing
@testable import BigInt

// MutableBigInt compound operators (+=,-=,*=,/=,%=), addSquareOf, addAbsValueOf
// verified against native Int128.

@Suite struct MutableBigIntLayer5Tests {

    private func big(_ v: Int128) -> BigInt {
        if v == 0 { return BigInt.ZERO }
        let neg = v < 0
        let mag = v.magnitude
        let m = Magia(5)
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
    private func mbi(_ a: Int128) -> MutableBigInt {
        let m = MutableBigInt(); m.set(big(a) as BigIntNumber); return m
    }
    private final class Rng {
        var s: UInt64 = 0x1357_9BDF_2468_ACE0
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

    @Test func plusMinusAssign() {
        let rng = Rng()
        for _ in 0..<6000 {
            let a = rng.i128(120), b = rng.i128(120)
            let mp = mbi(a); mp += big(b); #expect(i128(mp) == a + b)
            let ms = mbi(a); ms -= big(b); #expect(i128(ms) == a - b)
            let n = Int32(truncatingIfNeeded: rng.next())
            let l = Int64(truncatingIfNeeded: rng.next())
            let m1 = mbi(a); m1 += n; #expect(i128(m1) == a + Int128(n))
            let m2 = mbi(a); m2 -= n; #expect(i128(m2) == a - Int128(n))
            let m3 = mbi(a); m3 += l; #expect(i128(m3) == a + Int128(l))
            let m4 = mbi(a); m4 -= l; #expect(i128(m4) == a - Int128(l))
        }
    }

    @Test func timesDivRemAssign() {
        let rng = Rng()
        for _ in 0..<6000 {
            let a = rng.i128(60), b = rng.i128(60)
            let mt = mbi(a); mt *= big(b); #expect(i128(mt) == a * b)
            let aa = rng.i128(126); var bb = rng.i128(100); if bb == 0 { bb = 1 }
            let md = mbi(aa); md /= big(bb); #expect(i128(md) == aa / bb)
            let mr = mbi(aa); mr %= big(bb); #expect(i128(mr) == aa % bb)
            let l = Int64(truncatingIfNeeded: rng.next())
            let mtl = mbi(a); mtl *= l; #expect(i128(mtl) == a * Int128(l))
        }
    }

    @Test func addSquareOfAndAbs() {
        let rng = Rng()
        for _ in 0..<4000 {
            let a = rng.i128(60)
            let n = Int32(truncatingIfNeeded: rng.next())
            let dw = rng.next() >> 1            // 63-bit
            let bsq = rng.i128(55)
            let m1 = mbi(a); m1.addSquareOf(n); #expect(i128(m1) == a + Int128(n) * Int128(n))
            let m2 = mbi(a); m2.addSquareOf(dw); #expect(i128(m2) == a + Int128(dw) * Int128(dw))
            let m3 = mbi(a); m3.addSquareOf(big(bsq)); #expect(i128(m3) == a + bsq * bsq)
            // addAbsValueOf
            let b = rng.i128(110)
            let m4 = mbi(a); m4.addAbsValueOf(big(b) as BigIntNumber); #expect(i128(m4) == a + Int128(b.magnitude))
        }
    }

    @Test func chainedAccumulation() {
        // classic MutableBigInt usage: sum/sumSqr/sumAbs accumulation loop
        let data: [Int64] = [3, -7, 11, -2, 100, -50, 8]
        let sum = MutableBigInt(), sumSqr = MutableBigInt(), sumAbs = MutableBigInt()
        var oSum: Int128 = 0, oSqr: Int128 = 0, oAbs: Int128 = 0
        for v in data {
            sum += v;            oSum += Int128(v)
            sumSqr.addSquareOf(v); oSqr += Int128(v) * Int128(v)
            sumAbs.addAbsValueOf(v); oAbs += Int128(v.magnitude)
        }
        #expect(i128(sum) == oSum)
        #expect(i128(sumSqr) == oSqr)
        #expect(i128(sumAbs) == oAbs)
    }
}
