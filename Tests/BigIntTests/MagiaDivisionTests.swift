import Testing
@testable import BigInt

// Division is the correctness-critical kernel. We exercise every path
// (setDiv32, knuthDivide64, multi-limb knuthDivide, with/without normalization
// shift) against Swift's native UInt128 division over a deterministic sweep.

@Suite struct MagiaDivisionTests {

    // up-to-4-limb magia <-> UInt128
    private func magiaU128(_ v: UInt128) -> (Magia, Int) {
        let m = Magia(8)
        var n = 0
        for i in 0..<4 {
            let limb = Limb(truncatingIfNeeded: v >> (i * 32))
            m[i] = limb
            if limb != 0 { n = i + 1 }
        }
        return (m, n)
    }

    private func magiaToU128(_ m: Magia, _ n: Int) -> UInt128 {
        var v: UInt128 = 0
        var i = n - 1
        while i >= 0 { v = (v << 32) | UInt128(m[i]); i -= 1 }
        return v
    }

    // Mirror the dispatch the BigInt layer will use.
    private func engDiv(_ a: UInt128, _ b: UInt128) -> UInt128 {
        let (x, xn) = magiaU128(a)
        let (y, yn) = magiaU128(b)
        let z = Magia(8)
        let fast = magia_trySetDivFastPath(z, x, xn, y, yn)
        let qn = fast >= 0 ? fast : magia_setDivKnuth(z, x, xn, nil, y, yn, nil)
        return magiaToU128(z, qn)
    }

    private func engRem(_ a: UInt128, _ b: UInt128) -> UInt128 {
        let (x, xn) = magiaU128(a)
        let (y, yn) = magiaU128(b)
        let z = Magia(8)
        let rn = magia_setRem(z, x, xn, y, yn)
        return magiaToU128(z, rn)
    }

    private func check(_ a: UInt128, _ b: UInt128, _ sl: SourceLocation = #_sourceLocation) {
        guard b != 0 else { return }
        #expect(engDiv(a, b) == a / b, "div \(a)/\(b)", sourceLocation: sl)
        #expect(engRem(a, b) == a % b, "rem \(a)%\(b)", sourceLocation: sl)
    }

    @Test func handPickedPaths() {
        let U = UInt128.self
        let max128 = U.max
        // yn == 1 (setDiv32)
        check(0xFFFF_FFFF_FFFF_FFFF_0000_0001, 7)
        check(0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF)   // divisor 2^32-1
        // yn == 2 (knuthDivide64), 4-limb dividend
        check(max128, 0xFFFF_FFFF_FFFF_FFFF)
        check(max128, 0x8000_0000_0000_0000)        // power of two-ish, hi bit set (no shift)
        check(max128, 0x0000_0001_0000_0003)        // small hi limb -> normalization shift > 0
        // yn == 3 (multi-limb knuthDivide), divisor = 2^64 + 1 (limbs [1,0,1])
        check(max128, (UInt128(1) << 64) + 1)
        // yn == 3 with normalization shift (top limb hi bit clear)
        check(max128, (UInt128(1) << 96) + (UInt128(1) << 33) + 1)
        // edge relations
        check(100, 100)                 // a == b -> q=1, r=0
        check(50, 100)                  // a < b  -> q=0, r=a
        check(0, 12345)                 // zero dividend
        check(max128, 1)                // divide by one
        check(max128, max128)
        check((UInt128(1) << 96), (UInt128(1) << 64))   // power-of-two divisor (shift path)
    }

    @Test func randomizedSweep() {
        // splitmix64 for determinism (Math.random is fine in tests, but keep it
        // reproducible).
        var s: UInt64 = 0x1234_5678_9ABC_DEF0
        func next() -> UInt64 {
            s = s &+ 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        func rand128(_ maxLimbs: Int) -> UInt128 {
            var v: UInt128 = 0
            let limbs = Int(next() % UInt64(maxLimbs)) + 1
            for i in 0..<limbs {
                v |= UInt128(Limb(truncatingIfNeeded: next())) << (i * 32)
            }
            return v
        }
        for _ in 0..<5000 {
            let a = rand128(4)
            let b = rand128(4)
            check(a, b)
            // also bias toward similar magnitudes (a == b limb-length) and small divisors
            check(a, rand128(1))
            check(a, rand128(2))
        }
    }
}
