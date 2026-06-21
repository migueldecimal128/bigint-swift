import Testing
@testable import BigInt

@Suite struct TestMbiMontgomeryRedc {

    /// Round-trip property: REDC(x·R mod n) == x mod n, with R = 2^(64·k),
    /// k = n.meta.normLen and np = -n⁻¹ mod 2⁶⁴. Works for any odd n > 0.
    private func checkRoundTrip(_ n: BigInt, _ x: BigInt) {
        let np = ModContext.Montgomery.computeNp(n.toULong())
        let k  = Int(n.meta.normLen)
        let R  = BigInt.ONE.shl(64 * k)
        let t  = ((x * R) % n).toMutableBigInt()
        t.montgomeryRedc(n, np)
        #expect(t.toBigInt() == x % n)
        #expect(t.isNormalized())
    }

    @Test func testMontgomeryRedc_smallModulus() {
        // n = 3 (one 64-bit limb); 2·R⁻¹·R ≡ 2 (mod 3)
        checkRoundTrip(BigInt.from(Int32(3)), BigInt.from(Int32(2)))
    }

    @Test func testMontgomeryRedc_zeroResidue() {
        // a value ≡ 0 mod n stays 0 through REDC
        checkRoundTrip(BigInt.from(Int32(3)), BigInt.from(Int32(0)))
    }

    @Test func montgomeryRedc_roundTrip_smallX() {
        // single 64-bit limb odd modulus
        checkRoundTrip(BigInt.from((0xFFFF_FFFF_FFFF_FFC5 as UInt64)), BigInt.from(Int32(12345)))
    }

    @Test func testMontgomeryRedc_twoLimbModulus() {
        // a genuine 128-bit (two 64-bit limb) odd modulus: hi·2⁶⁴ + 3
        let hi = BigInt.from((0xFFFF_FFFF_FFFF_FFC5 as UInt64))
        let n  = hi.shl(64) + BigInt.from(Int32(3))   // low limb 3 ⇒ odd, normLen == 2
        #expect(n.meta.normLen == 2)
        checkRoundTrip(n, BigInt.from(Int32(12345)))
    }
}
