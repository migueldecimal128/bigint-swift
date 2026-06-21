import Testing
@testable import BigInt

@Suite struct MagiaBitwiseCompareTests {

    private func u64(_ v: UInt64) -> Magia {
        let m = Magia(8); _ = magia_setULong(m, v); return m
    }

    @Test func andOrXor() {
        let a = u64(0xFF00_FF00_FF00_FF00)
        let b = u64(0x0FF0_0FF0_0FF0_0FF0)
        let an = 2, bn = 2

        let zAnd = Magia(8)
        let nAnd = magia_setAnd(zAnd, a, an, b, bn)
        #expect(magia_toRawULong(zAnd, nAnd) == ((0xFF00_FF00_FF00_FF00 as UInt64) & 0x0FF0_0FF0_0FF0_0FF0))

        let zOr = Magia(8)
        let nOr = magia_setOr(zOr, a, an, b, bn)
        #expect(magia_toRawULong(zOr, nOr) == ((0xFF00_FF00_FF00_FF00 as UInt64) | 0x0FF0_0FF0_0FF0_0FF0))

        let zXor = Magia(8)
        let nXor = magia_setXor(zXor, a, an, b, bn)
        #expect(magia_toRawULong(zXor, nXor) == ((0xFF00_FF00_FF00_FF00 as UInt64) ^ 0x0FF0_0FF0_0FF0_0FF0))
    }

    @Test func andDifferentLengthsAndCancellation() {
        let a = u64(0xFFFF_FFFF_FFFF_FFFF)  // 2 limbs
        let b = u64(0xF0)                    // 1 limb
        let z = Magia(8)
        let n = magia_setAnd(z, a, 2, b, 1)
        #expect(magia_toRawULong(z, n) == 0xF0)
        // AND to zero -> length 0
        let c = u64(0x0F)
        #expect(magia_setAnd(Magia(8), b, 1, c, 1) == 0)
    }

    @Test func compareOrdering() {
        #expect(magia_compare(u64(5), 1, u64(7), 1) == -1)
        #expect(magia_compare(u64(7), 1, u64(5), 1) == 1)
        #expect(magia_compare(u64(7), 1, u64(7), 1) == 0)
        #expect(magia_compare(u64(0x1_0000_0000), 2, u64(0xFFFF_FFFF), 1) == 1)   // more limbs
        // unsigned limb compare (high bit set must read as large)
        #expect(magia_compare(u64(0x8000_0000), 1, u64(0x7FFF_FFFF), 1) == 1)
        #expect(magia_compare(u64(0xFFFF_FFFF_FFFF_FFFF), 2, u64(0xFFFF_FFFF_FFFF_FFFE), 2) == 1)
    }

    @Test func compareToDword() {
        #expect(magia_compare(u64(100), 1, UInt64(200)) == -1)
        #expect(magia_compare(u64(0xFFFF_FFFF_FFFF_FFFF), 2, UInt64(1)) == 1)
        let big = Magia(8); let bn = magia_setULong(big, 0x1_0000_0000_0000)
        _ = magia_setMul32(big, big, bn, 7)   // > 2^48, still 2 limbs? ensure >2 limbs path tested elsewhere
        #expect(magia_compare(u64(42), 1, UInt64(42)) == 0)
    }

    @Test func bitTestsAndExtract() {
        let x = u64(0x8000_0001_0000_0080)
        let xn = 2
        #expect(magia_testBit(x, xn, 7))
        #expect(!magia_testBit(x, xn, 6))
        #expect(magia_testBit(x, xn, 32))
        #expect(magia_testBit(x, xn, 63))
        #expect(!magia_testBit(x, xn, 100))
        #expect(magia_extractULongAtBitIndex(x, xn, 0) == 0x8000_0001_0000_0080)
        #expect(magia_extractULongAtBitIndex(x, xn, 8) == (0x8000_0001_0000_0080 as UInt64) >> 8)
        #expect(magia_extractULongAtBitIndex(x, xn, 36) == (0x8000_0001_0000_0080 as UInt64) >> 36)
        #expect(magia_testAnyBitInLowerN(x, xn, 8))      // bit 7 set
        #expect(!magia_testAnyBitInLowerN(x, xn, 7))     // bits 0..6 clear
    }
}
