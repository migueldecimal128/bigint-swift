import Testing
@testable import BigInt

@Suite struct MagiaBitwiseCompareTests {

    private func u64(_ v: UInt64) -> Magia {
        let m = Magia.make(8); _ = magia_setULong(m, v); return m
    }
    // genuine two-limb (128-bit) magnitude: lo + hi·2^64
    private func twoLimb(_ lo: UInt64, _ hi: UInt64) -> Magia {
        let m = Magia.make(8); m[0] = lo; m[1] = hi; return m
    }

    // The magnitude-only engine kernels (magia_setAnd/setOr/setXor) were removed
    // when the bitwise ops moved to two's-complement at the BigInt layer; their
    // tests now live in TestBigIntTwosComplementBitwise. The compare / bit-test
    // cases below exercise still-present engine functions.

    @Test func compareOrdering() {
        #expect(magia_compare(u64(5), 1, u64(7), 1) == -1)
        #expect(magia_compare(u64(7), 1, u64(5), 1) == 1)
        #expect(magia_compare(u64(7), 1, u64(7), 1) == 0)
        #expect(magia_compare(twoLimb(0, 1), 2, u64(0xFFFF_FFFF_FFFF_FFFF), 1) == 1)   // more limbs
        // unsigned limb compare (high bit set must read as large)
        #expect(magia_compare(u64(0x8000_0000_0000_0000), 1, u64(0x7FFF_FFFF_FFFF_FFFF), 1) == 1)
        #expect(magia_compare(twoLimb(0, 0xFFFF_FFFF_FFFF_FFFF), 2, twoLimb(0, 0xFFFF_FFFF_FFFF_FFFE), 2) == 1)
    }

    @Test func compareToDword() {
        #expect(magia_compare(u64(100), 1, UInt64(200)) == -1)
        #expect(magia_compare(twoLimb(1, 1), 2, UInt64(1)) == 1)   // 2^64+1 > 1
        #expect(magia_compare(u64(42), 1, UInt64(42)) == 0)
    }

    @Test func bitTestsAndExtract() {
        let x = u64(0x8000_0001_0000_0080)
        let xn = 1                                  // one 64-bit limb
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
