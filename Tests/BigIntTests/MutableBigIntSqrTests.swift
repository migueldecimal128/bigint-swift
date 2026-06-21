import Testing
@testable import BigInt

// setSqr cross-checked against the verified magia_setMul(x, x) at every size (unrolled,
// schoolbook, and Karatsuba >= 84 limbs), plus primitive squares vs Int128.

@Suite struct MutableBigIntSqrTests {

    private final class Rng {
        var s: UInt64 = 0x5A5A_F00D_1234_9999
        func next() -> UInt64 {
            s = s &+ 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func randomBig(_ n: Int, _ rng: Rng) -> BigInt {
        let m = Magia(n + 1)
        for i in 0..<n { m[i] = Limb(truncatingIfNeeded: rng.next()) }
        if n > 0 && m[n - 1] == 0 { m[n - 1] = 1 }
        let neg = rng.next() & 1 == 1
        return BigInt.fromNonNormalizedOrZero(neg, m)
    }

    private func i128(_ x: BigIntNumber) -> Int128 {
        var mag: UInt128 = 0
        var i = Int(x.meta.normLen) - 1
        while i >= 0 { mag = (mag << 32) | UInt128(x.magia[i]); i -= 1 }
        let s = Int128(mag)
        return x.isNegative() ? -s : s
    }

    @Test func setSqrVsSetMul() {
        let rng = Rng()
        for n in 0...130 {           // 0..130 covers unrolled, schoolbook, Karatsuba
            let x = n == 0 ? BigInt.ZERO : randomBig(n, rng)
            let sq = MutableBigInt().setSqr(x).toBigInt()
            let mul = MutableBigInt().setMul(x, x).toBigInt()
            #expect(sq == mul, "setSqr != setMul at n=\(n)")
        }
    }

    @Test func karatsubaSetSqrDirect() {
        let rng = Rng()
        for n in [84, 85, 100, 127, 200] {
            let x = randomBig(n, rng)
            let kara = MutableBigInt().karatsubaSetSqr(x).toBigInt()
            let mul = MutableBigInt().setMul(x, x).toBigInt()
            #expect(kara == mul, "karatsubaSetSqr != setMul at n=\(n)")
        }
    }

    @Test func primitiveSquares() {
        let rng = Rng()
        for _ in 0..<4000 {
            let n = Int32(truncatingIfNeeded: rng.next())
            let w = UInt32(truncatingIfNeeded: rng.next())
            let l = Int64(bitPattern: rng.next() >> 4)        // <= 60-bit magnitude-ish
            let dw = rng.next() >> 1                          // 63-bit
            #expect(i128(MutableBigInt().setSqr(n)) == Int128(n) * Int128(n))
            #expect(i128(MutableBigInt().setSqr(w)) == Int128(w) * Int128(w))
            #expect(i128(MutableBigInt().setSqr(l)) == Int128(l) * Int128(l))
            #expect(i128(MutableBigInt().setSqr(dw)) == Int128(dw) * Int128(dw))
        }
    }
}
