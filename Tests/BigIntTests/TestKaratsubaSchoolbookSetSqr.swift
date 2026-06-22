import Testing
@testable import BigInt

@Suite struct TestKaratsubaSchoolbookSetSqr {

    // Builds a Magia from little-endian limb values (Kotlin's `intArrayOf`).
    private func mag(_ limbs: [Limb]) -> Magia {
        Magia.make(limbs: ContiguousArray(limbs))
    }

    // Extracts a little-endian limb slice (faithful to Kotlin's
    // fromLittleEndianIntArray(sign, arr, off, len) offset overload, which the
    // Swift façade lacks).
    private func le(_ sign: Bool, _ m: Magia, _ off: Int, _ len: Int) -> BigInt {
        var s = [Limb](repeating: 0, count: len)
        for i in 0..<len { s[i] = m[off + i] }
        return BigInt.fromLittleEndianIntArray(sign, s)
    }

    private func le(_ sign: Bool, _ m: Magia) -> BigInt {
        BigInt.fromLittleEndianIntArray(sign, m.prefixArray(m.size))
    }

    @Test func square_len1() {
        let a = mag([Limb(0xFFFF_FFFF)])
        let z = Magia.make(4)

        _ = magia_setSqrSchoolbook(z, 0, a, 0, 1)

        let ref = le(false, a).sqr()
        let got = le(false, z)

        #expect(got == ref)
    }

    @Test func square_len2() {
        let a = mag([
            Limb(0x0123_4567),
            Limb(0x89AB_CDEF)
        ])
        let z = Magia.make(8)

        _ = magia_setSqrSchoolbook(z, 1, a, 0, 2)

        let ref = le(false, a).sqr()
        let got = le(false, z, 1, 2 * 2)

        #expect(got == ref)
    }

    @Test func square_len3_offsets() {
        let a = Magia.make(10)
        a[3] = Limb(0xDEAD_BEEF)
        a[4] = Limb(0x1234_5678)
        a[5] = Limb(0xCAFE_BABE)

        let z = Magia.make(20)

        _ = magia_setSqrSchoolbook(z, 7, a, 3, 3)

        let ref = le(false, a, 3, 3).sqr()
        let got = le(false, z, 7, 6)

        #expect(got == ref)
    }

    @Test func square_allOnes_carryStress() {
        let n = 8
        let a = Magia.make(n)
        for i in 0..<n { a[i] = Limb(0xFFFF_FFFF) }
        let z = Magia.make(16)

        _ = magia_setSqrSchoolbook(z, 0, a, 0, n)

        let ref = le(false, a)
        let ref2 = ref * ref
        let got = le(false, z, 0, 2 * n)

        #expect(got == ref2)
    }

    @Test func square_len4_randomish() {
        let a = mag([
            Limb(0x1111_1111),
            Limb(0x2222_2222),
            Limb(0x3333_3333),
            Limb(0x4444_4444)
        ])
        let z = Magia.make(12)

        _ = magia_setSqrSchoolbook(z, 2, a, 0, 4)

        let ref = le(false, a, 0, 4).sqr()
        let got = le(false, z, 2, 8)

        #expect(got == ref)
    }

    @Test func testRandom() {
        for _ in 0..<100 {
            let bi = BigInt.randomWithBitLen(2048)
            let ax = bi.magnitudeToLittleEndianIntArray()
            if ax.count < 1 { continue }
            let a = Magia.make(ax.count + 10)
            for i in 0..<a.size { a[i] = Limb(0xDEAD) }
            let aOff = Int(BigIntRandom.Default.nextInt(Int32(10)))
            let aNormLen = ax.count
            for i in 0..<aNormLen { a[aOff + i] = ax[i] }

            let zLen = 2 * aNormLen
            let z = Magia.make(zLen + 10)
            for i in 0..<z.size { z[i] = Limb(0xFFFF) }
            let zOff = Int(BigIntRandom.Default.nextInt(Int32(10)))

            z.fill(0, zOff, zOff + zLen)
            _ = magia_setSqrSchoolbook(z, zOff, a, aOff, aNormLen)

            let observed = le(false, z, zOff, zLen)
            let expected = bi.sqr()

            #expect(observed == expected)
        }
    }

    @Test func square_FFFF() {
        let a = mag([Limb(0xFFFF_FFFF), Limb(0xFFFF_FFFF), Limb(0xFFFF_FFFF), Limb(0xFFFF_FFFF)])

        let z = Magia.make(2 * a.size)

        _ = magia_setSqrSchoolbook(z, 0, a, 0, a.size)

        let ref = le(false, a, 0, a.size)
        let ref2 = ref * ref
        let got = le(false, z)

        #expect(got == ref2)
    }
}
