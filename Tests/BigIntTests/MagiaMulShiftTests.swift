import Testing
@testable import BigInt

// Proof for the multiply / shift / bit-query batch. Inputs are built with
// setULong and results read with toRawULong (for products < 2^64) or checked
// limb-by-limb (for the 2^64+ cases). Oracles are native Swift arithmetic.

@Suite struct MagiaMulShiftTests {

    private func u64(_ v: UInt64) -> Magia {
        let m = Magia(8); _ = magia_setULong(m, v); return m
    }

    @Test func setMul32MultiplyPath() {
        let x = u64(0xFFFF_FFFF)
        let z = Magia(8)
        let zn = magia_setMulLimb(z, x, 1, 0xFFFF_FFFF)        // (2^32-1)^2
        #expect(magia_toRawULong(z, zn) == 0xFFFF_FFFF * 0xFFFF_FFFF as UInt64)
    }

    @Test func setMul32PowerOfTwoTakesShiftPath() {
        let x = u64(5)
        let z = Magia(8)
        let zn = magia_setMulLimb(z, x, 1, 8)                  // 5 * 2^3
        #expect(magia_toRawULong(z, zn) == 40)
    }

    @Test func setMul64CorePath() {
        let dw: UInt64 = 0x2_0000_0005                 // high word set, >1 bit
        let x = u64(3)
        let z = Magia(8)
        let zn = magia_setMulLimb(z, x, 1, dw)
        #expect(magia_toRawULong(z, zn) == 3 &* dw)
    }

    @Test func setMul64RoutesToMul32WhenHighWordZero() {
        let x = u64(0xFFFF_FFFF)
        let z = Magia(8)
        let zn = magia_setMulLimb(z, x, 1, 0x10)               // 2^4, low word only
        #expect(magia_toRawULong(z, zn) == 0xFFFF_FFFF << 4)
    }

    @Test func schoolbookFitsIn64() {
        let x = u64(0xFFFF_FFFF)
        let y = u64(0xFFFF_FFFF)
        let z = Magia(8)
        let zn = magia_setMulSchoolbook(z, x, 1, y, 1)
        #expect(magia_toRawULong(z, zn) == 0xFFFF_FFFE_0000_0001) // (2^32-1)^2
    }

    @Test func schoolbook2to64() {
        let x = u64(0x1_0000_0000)                     // 2^32, one 64-bit limb
        let y = u64(0x1_0000_0000)
        let z = Magia(8)
        let zn = magia_setMulSchoolbook(z, x, 1, y, 1)        // -> 2^64 = [0, 1]
        #expect(zn == 2 && z[0] == 0 && z[1] == 1)
    }

    @Test func shiftLeftCrossLimb() {
        let x = u64(1)
        let z = Magia(8)
        let zn = magia_setShiftLeft(z, x, 1, 40)             // 2^40
        #expect(magia_toRawULong(z, zn) == 1 << 40)
        // in place (z === x)
        let x2 = u64(0xABCD)
        let zn2 = magia_setShiftLeft(x2, x2, 1, 33)
        #expect(magia_toRawULong(x2, zn2) == 0xABCD << 33)
    }

    @Test func shiftRightCrossLimb() {
        let x = u64(0xFFFF_FFFF_FFFF_FFFF)
        let z = Magia(8)
        let zn = magia_setShiftRight(z, x, 1, 40)
        #expect(magia_toRawULong(z, zn) == 0xFFFF_FFFF_FFFF_FFFF >> 40)
        // shifting all bits away yields zero-length
        #expect(magia_setShiftRight(Magia(8), x, 1, 64) == 0)
    }

    @Test func bitQueries() {
        #expect(magia_normBitLen(u64(0xFF), 1) == 8)
        #expect(magia_normBitLen(u64(0x1_0000_0000), 1) == 33)
        #expect(magia_bitLen(u64(0xFFFF_FFFF_FFFF_FFFF), 1) == 64)
        #expect(magia_ctz(u64(0x100), 1) == 8)
        #expect(magia_ctz(u64(0x1_0000_0000), 1) == 32)
        #expect(magia_isPowerOfTwo(u64(0x1_0000_0000), 1))
        #expect(!magia_isPowerOfTwo(u64(0x3), 1))
    }

    @Test func fmaPow10AccumulatesDigits() {
        let x = u64(0)
        magia_mutateFmaPow10(x, 1, 3, 5)        // 0*1000 + 5
        magia_mutateFmaPow10(x, 1, 3, 123)      // 5*1000 + 123
        #expect(magia_toRawULong(x, 1) == 5123)
    }
}
