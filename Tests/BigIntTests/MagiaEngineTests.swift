import Testing
@testable import BigInt

// Engine-level proof that the add/sub family transliterated correctly:
// carry/borrow propagation, normalization trimming, and the setSub
// last-non-zero-index trick — all on known values.

@Suite struct MagiaEngineTests {

    @Test func setULongRoundTrip() {
        let x = Magia.make(8)
        #expect(magia_setULong(x, 0) == 0)
        #expect(magia_setULong(x, 0xFFFF_FFFF) == 1)
        #expect(magia_setULong(x, 0x1_0000_0000) == 1)      // any UInt64 is one 64-bit limb
        let n = magia_setULong(x, 0xDEAD_BEEF_CAFE_F00D)
        #expect(n == 1)
        #expect(magia_toRawULong(x, n) == 0xDEAD_BEEF_CAFE_F00D)
    }

    @Test func mutAddCarriesIntoSecondLimb() {
        let x = Magia.make(8)
        var n = magia_setULong(x, 0xFFFF_FFFF_FFFF_FFFF) // 2^64 - 1, one 64-bit limb
        #expect(n == 1)
        n = magia_mutAddLimb(x, n, 1)                       // -> 2^64, two limbs [0,1]
        #expect(n == 2)
        #expect(x[0] == 0 && x[1] == 1)
    }

    @Test func mutAddSimpleNoCarry() {
        let x = Magia.make(8)
        var n = magia_setULong(x, 0xFFFF_FFFF)
        n = magia_mutAddLimb(x, n, 1)                       // 2^32, still one 64-bit limb
        #expect(n == 1 && x[0] == 0x1_0000_0000)
    }

    @Test func mutSub64BorrowAndTrim() {
        let x = Magia.make(8)
        var n = magia_setULong(x, 0x1_0000_0000)         // 2^32
        n = magia_mutSubLimb(x, n, 1)                       // 2^32 - 1 -> single limb
        #expect(n == 1 && x[0] == 0xFFFF_FFFF)

        let y = Magia.make(8)
        var m = magia_setULong(y, 0)
        m = magia_setULong(y, 0xFFFF_FFFF_FFFF_FFFF)      // 2^64 - 1
        m = magia_mutSubLimb(y, m, 0xFFFF_FFFF_FFFF_FFFF)   // -> 0, trims both limbs
        #expect(m == 0)
    }

    @Test func mutAddArrayCarryPropagation() {
        let a = Magia.make(8); var an = magia_setULong(a, 0xFFFF_FFFF_FFFF_FFFF)  // 2^64 - 1
        let b = Magia.make(8); let bn = magia_setULong(b, 1)                       // 1
        an = magia_mutAdd(a, an, b, bn)                                       // -> 2^64 = [0, 1]
        #expect(an == 2 && a[0] == 0 && a[1] == 1)
    }

    @Test func setSubBorrowAndNormalize() {
        let z = Magia.make(8)
        let p = Magia.make(8); let pn = magia_setULong(p, 0x1_0000_0000_0000)  // 2^48
        let q = Magia.make(8); let qn = magia_setULong(q, 1)
        let zn = magia_setSub(z, p, pn, q, qn)                            // 2^48 - 1
        #expect(magia_toRawULong(z, zn) == 0xFFFF_FFFF_FFFF)

        // exact cancellation normalizes to length 0
        let z2 = Magia.make(8)
        let zn2 = magia_setSub(z2, p, pn, p, pn)
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
