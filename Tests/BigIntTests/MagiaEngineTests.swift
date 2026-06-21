import Testing
@testable import BigInt

// Engine-level proof that the add/sub family transliterated correctly:
// carry/borrow propagation, normalization trimming, and the setSub
// last-non-zero-index trick — all on known values.

@Suite struct MagiaEngineTests {

    @Test func setULongRoundTrip() {
        let x = Magia(8)
        #expect(setULong(x, 0) == 0)
        #expect(setULong(x, 0xFFFF_FFFF) == 1)
        #expect(setULong(x, 0x1_0000_0000) == 2)
        let n = setULong(x, 0xDEAD_BEEF_CAFE_F00D)
        #expect(n == 2)
        #expect(toRawULong(x, n) == 0xDEAD_BEEF_CAFE_F00D)
    }

    @Test func mutAdd64CarriesIntoThirdLimb() {
        let x = Magia(8)
        var n = setULong(x, 0xFFFF_FFFF_FFFF_FFFF) // 2^64 - 1, two limbs
        #expect(n == 2)
        n = mutAdd64(x, n, 1)                       // -> 2^64, three limbs [0,0,1]
        #expect(n == 3)
        #expect(x[0] == 0 && x[1] == 0 && x[2] == 1)
    }

    @Test func mutAdd32SimpleCarry() {
        let x = Magia(8)
        var n = setULong(x, 0xFFFF_FFFF)
        n = mutAdd32(x, n, 1)                       // 2^32 -> [0,1]
        #expect(n == 2 && x[0] == 0 && x[1] == 1)
    }

    @Test func mutSub64BorrowAndTrim() {
        let x = Magia(8)
        var n = setULong(x, 0x1_0000_0000)         // 2^32
        n = mutSub64(x, n, 1)                       // 2^32 - 1 -> single limb
        #expect(n == 1 && x[0] == 0xFFFF_FFFF)

        let y = Magia(8)
        var m = setULong(y, 0)
        m = setULong(y, 0xFFFF_FFFF_FFFF_FFFF)      // 2^64 - 1
        m = mutSub64(y, m, 0xFFFF_FFFF_FFFF_FFFF)   // -> 0, trims both limbs
        #expect(m == 0)
    }

    @Test func mutAddArrayCarryPropagation() {
        let a = Magia(8); var an = setULong(a, 0x1_0000_0000)   // 2^32
        let b = Magia(8); let bn = setULong(b, 0xFFFF_FFFF)     // 2^32 - 1
        an = mutAdd(a, an, b, bn)                                // -> 2^33 - 1
        #expect(an == 2 && a[0] == 0xFFFF_FFFF && a[1] == 1)
        #expect(toRawULong(a, an) == 0x1_FFFF_FFFF)
    }

    @Test func setSubBorrowAndNormalize() {
        let z = Magia(8)
        let p = Magia(8); let pn = setULong(p, 0x1_0000_0000_0000)  // 2^48
        let q = Magia(8); let qn = setULong(q, 1)
        let zn = setSub(z, p, pn, q, qn)                            // 2^48 - 1
        #expect(toRawULong(z, zn) == 0xFFFF_FFFF_FFFF)

        // exact cancellation normalizes to length 0
        let z2 = Magia(8)
        let zn2 = setSub(z2, p, pn, p, pn)
        #expect(zn2 == 0)
    }

    @Test func metaPacking() {
        #expect(Meta(signFlag: false, normLen: 0).isZero)
        #expect(Meta(signFlag: true, normLen: 0).isZero)        // no negative zero
        let m = Meta(signFlag: true, normLen: 5)
        #expect(m.isNegative && m.normLen == 5)
        #expect(m.negate().isPositive && m.negate().normLen == 5)
        #expect(m.abs().isPositive && m.abs().normLen == 5)
        #expect(Meta(signFlag: false, normLen: 7).signum == 1)
        #expect(Meta(signFlag: true, normLen: 7).signum == -1)
        #expect(Meta(signFlag: false, normLen: 0).signum == 0)
    }
}
