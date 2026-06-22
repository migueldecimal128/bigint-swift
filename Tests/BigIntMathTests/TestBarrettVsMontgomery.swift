import Testing
@testable import BigInt
@testable import BigIntMath

// PORT-NOTE: This Kotlin file is mostly a benchmark. Per the work order, only
// the correctness assertions are ported; all timing (`measureNano`), warmup
// loops, `println`, ratio/median computation, and the `isJsPlatform()` guards
// are dropped. The `compareBarrettVsMontgomery_modPow_2kBits_2k` test is
// commented out (`//@Test`) in Kotlin and is omitted here too.

@Suite struct TestBarrettVsMontgomery {

    private func modPowRef(_ a: BigInt, _ e: BigInt, _ m: BigInt) -> BigInt {
        precondition(e.compareTo(BigInt.ZERO) >= 0)
        if m == BigInt.ONE { return BigInt.ZERO }
        var base = a % m           // ensure 0 <= base < m
        var exp = e
        var res = BigInt.ONE

        while exp.compareTo(BigInt.ZERO) > 0 {
            if exp.testBit(0) {
                res = (res * base) % m
            }
            base = (base * base) % m
            exp = exp.ushr(1)
        }
        return res
    }

    @Test func compareBarrettVsMontgomery_modMul_2kBits() {
        let bitLen = 2048

        let m = BigInt.randomWithBitLen(bitLen, ensureOdd: true)
        let ctxMont = ModContext(m, useBarrettOnly: false)
        let ctxBarr = ModContext(m, useBarrettOnly: true)

        let a = BigInt.randomBelow(m)
        let b = BigInt.randomBelow(m)
        let expected = (a * b) % m

        let outMont = MutableBigInt()
        let outBarr = MutableBigInt()

        ctxMont.modMul(a, b, outMont)
        ctxBarr.modMul(a, b, outBarr)

        #expect(outMont.toBigInt() == expected)
        #expect(outBarr.toBigInt() == expected)
    }

    @Test func compareBarrettVsMontgomery_modPow_2kBits_Long() {
        let bitLen = 2048

        // 2048-bit odd modulus (Montgomery eligible)
        let m = BigInt.randomWithBitLen(bitLen, ensureOdd: true)

        // Engines
        let ctxMont = ModContext(m, useBarrettOnly: false)
        let ctxBarr = ModContext(m, useBarrettOnly: true)

        // Base < m
        let a = BigInt.randomBelow(m)

        // Use RSA-style exponent 65537, so we drive many modular multiplies
        let e = 65_537

        let outMont = MutableBigInt()
        let outBarr = MutableBigInt()

        ctxMont.modPow(a, e, outMont)
        ctxBarr.modPow(a, e, outBarr)
        #expect(outMont.toBigInt() == outBarr.toBigInt())

        // Compute reference using the existing int-exponent operator(s)
        // i.e., (a^e) % m computed naïvely through BigInt mul
        let refM = MutableBigInt().set(Int32(1))
        for _ in 0..<e {
            refM *= a
            refM %= m
        }
        let ref = refM.toBigInt()

        // Correctness check
        ctxMont.modPow(a, e, outMont)
        ctxBarr.modPow(a, e, outBarr)
        #expect(outBarr.toBigInt() == ref, "Barrett correctness")
        #expect(outMont.toBigInt() == ref, "Montgomery correctness")
    }

    /// Regression: Montgomery REDC dropped a carry in its Phase-1 tail for moduli
    /// just above a power of two (sparse high limb, zero middle limbs), e.g.
    /// 2^128+51. Random moduli almost never hit the 0xFFFFFFFF-carry alignment, so
    /// this guards the now-fully-chained carry propagation explicitly.
    @Test func montgomeryMatchesBarrett_sparseModuli() {
        let sparse = [
            "340282366920938463463374607431768211507",        // 2^128 + 51 (prime)
            "1461501637330902918203684832716283019655932542983", // 2^160 + 7 (prime)
            "6277101735386680763835789423207666416102355444464034512947", // 2^192 + 51
            "115792089237316195423570985008687907853269984665640564039457584007913129639943" // 2^256 + 7
        ]
        for s in sparse {
            let m = BigInt.from(s)
            let ctxMont = ModContext(m, useBarrettOnly: false)
            let ctxBarr = ModContext(m, useBarrettOnly: true)
            let base = BigInt.from(Int32(2))
            let exp = (m - BigInt.ONE).ushr(1)
            let outMont = MutableBigInt(); ctxMont.modPow(base, exp, outMont)
            let outBarr = MutableBigInt(); ctxBarr.modPow(base, exp, outBarr)
            #expect(outMont.toBigInt() == outBarr.toBigInt(), "mont != barrett for \(s)")
        }
    }

    @Test func compareBarrettVsMontgomery_modPow_X() {
        let bitLen = 64

        // 2048-bit odd modulus (Montgomery eligible)
        let m = BigInt.randomWithBitLen(bitLen, ensureOdd: true)

        // Engines
        let ctxMont = ModContext(m, useBarrettOnly: false)
        let ctxBarr = ModContext(m, useBarrettOnly: true)

        // Base < m
        let a = BigInt.randomBelow(m)

        let e = BigInt.randomWithMaxBitLen(bitLen - 1)

        let outMont = MutableBigInt()
        let outBarr = MutableBigInt()

        ctxMont.modPow(a, e, outMont)
        ctxBarr.modPow(a, e, outBarr)
        #expect(outMont.toBigInt() == outBarr.toBigInt())

        // Compute reference using the existing int-exponent operator(s)
        // i.e., (a^e) % m computed naïvely through BigInt mul
        let ref = modPowRef(a, e, m)

        // Correctness check
        ctxMont.modPow(a, e, outMont)
        ctxBarr.modPow(a, e, outBarr)
        #expect(outBarr.toBigInt() == ref, "Barrett correctness")
        #expect(outMont.toBigInt() == ref, "Montgomery correctness")
    }
}
