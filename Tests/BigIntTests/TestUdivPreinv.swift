import Testing
@testable import BigInt

/// Differential test: the Granlund-Montgomery 2-by-1 reciprocal divide
/// (`udiv1e19_recipMul`, used by the base-1e19 print path) must match the stdlib's
/// `UInt64.dividingFullWidth` for every `(high < d, low)` dividend.
@Suite struct TestUdivPreinv {

    private func recip(_ d: UInt64) -> UInt64 {
        UInt64(truncatingIfNeeded: (UInt128.max / UInt128(d)) - (UInt128(1) << 64))
    }

    private func check(_ d: UInt64, _ u1: UInt64, _ u0: UInt64, _ v: UInt64) {
        let got = BigIntParsePrint.udiv1e19_recipMul(u1, u0, d, v)
        let ref = d.dividingFullWidth((high: u1, low: u0))   // requires u1 < d
        #expect(got.q == ref.quotient && got.r == ref.remainder,
                "d=\(d) u1=\(u1) u0=\(u0): got (\(got.q),\(got.r)) want (\(ref.quotient),\(ref.remainder))")
    }

    @Test func matchesDividingFullWidth_1e19() {
        let d: UInt64 = 10_000_000_000_000_000_000          // 1e19 (normalized; bit 63 set)
        let v = recip(d)
        // edge cases (all require u1 < d)
        for (u1, u0) in [(UInt64(0), UInt64(0)), (0, 1), (0, d - 1), (0, d), (0, UInt64.max),
                         (1, 0), (d - 1, 0), (d - 1, UInt64.max), (d / 2, 0xDEAD_BEEF),
                         (d - 1, d - 1)] {
            check(d, u1, u0, v)
        }
        // fuzz
        var s: UInt64 = 0x1234_5678_9ABC_DEF1
        func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; var z = s; z ^= z >> 31; return z }
        for _ in 0..<300_000 { check(d, next() % d, next(), v) }
    }

    /// Sanity: also exercise other normalized divisors to confirm the routine is
    /// general (not accidentally 1e19-specific).
    @Test func matchesDividingFullWidth_otherDivisors() {
        var s: UInt64 = 0xABCD_1234_5678_9999
        func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; var z = s; z ^= z >> 31; return z }
        for d in [UInt64.max, UInt64(1) << 63, (UInt64(1) << 63) | 1, 0xFFFF_0000_0000_0000, 0x8000_0000_0000_0001] {
            let v = recip(d)
            check(d, 0, 0, v); check(d, d - 1, UInt64.max, v)
            for _ in 0..<50_000 { check(d, next() % d, next(), v) }
        }
    }
}
