import Testing
@testable import BigInt

// Proof for the multiply / shift / bit-query batch. Inputs are built with
// setULong and results read with toRawULong (for products < 2^64) or checked
// limb-by-limb (for the 2^64+ cases). Oracles are native Swift arithmetic.

@Suite struct MagiaMulShiftTests {

    private func u64(_ v: UInt64) -> Magia {
        let m = Magia(8); _ = setULong(m, v); return m
    }

    @Test func setMul32MultiplyPath() {
        let x = u64(0xFFFF_FFFF)
        let z = Magia(8)
        let zn = setMul32(z, x, 1, 0xFFFF_FFFF)        // (2^32-1)^2
        #expect(toRawULong(z, zn) == 0xFFFF_FFFF * 0xFFFF_FFFF as UInt64)
    }

    @Test func setMul32PowerOfTwoTakesShiftPath() {
        let x = u64(5)
        let z = Magia(8)
        let zn = setMul32(z, x, 1, 8)                  // 5 * 2^3
        #expect(toRawULong(z, zn) == 40)
    }

    @Test func setMul64CorePath() {
        let dw: UInt64 = 0x2_0000_0005                 // high word set, >1 bit
        let x = u64(3)
        let z = Magia(8)
        let zn = setMul64(z, x, 1, dw)
        #expect(toRawULong(z, zn) == 3 &* dw)
    }

    @Test func setMul64RoutesToMul32WhenHighWordZero() {
        let x = u64(0xFFFF_FFFF)
        let z = Magia(8)
        let zn = setMul64(z, x, 1, 0x10)               // 2^4, low word only
        #expect(toRawULong(z, zn) == 0xFFFF_FFFF << 4)
    }

    @Test func schoolbookFitsIn64() {
        let x = u64(0xFFFF_FFFF)
        let y = u64(0xFFFF_FFFF)
        let z = Magia(8)
        let zn = setMulSchoolbook(z, x, 1, y, 1)
        #expect(toRawULong(z, zn) == 0xFFFF_FFFE_0000_0001) // (2^32-1)^2
    }

    @Test func schoolbook2to64() {
        let x = u64(0x1_0000_0000)                     // 2^32, two limbs
        let y = u64(0x1_0000_0000)
        let z = Magia(8)
        let zn = setMulSchoolbook(z, x, 2, y, 2)        // -> 2^64
        #expect(zn == 3 && z[0] == 0 && z[1] == 0 && z[2] == 1)
    }

    @Test func shiftLeftCrossLimb() {
        let x = u64(1)
        let z = Magia(8)
        let zn = setShiftLeft(z, x, 1, 40)             // 2^40
        #expect(toRawULong(z, zn) == 1 << 40)
        // in place (z === x)
        let x2 = u64(0xABCD)
        let zn2 = setShiftLeft(x2, x2, 1, 33)
        #expect(toRawULong(x2, zn2) == 0xABCD << 33)
    }

    @Test func shiftRightCrossLimb() {
        let x = u64(0xFFFF_FFFF_FFFF_FFFF)
        let z = Magia(8)
        let zn = setShiftRight(z, x, 2, 40)
        #expect(toRawULong(z, zn) == 0xFFFF_FFFF_FFFF_FFFF >> 40)
        // shifting all bits away yields zero-length
        #expect(setShiftRight(Magia(8), x, 2, 64) == 0)
    }

    @Test func bitQueries() {
        #expect(normBitLen(u64(0xFF), 1) == 8)
        #expect(normBitLen(u64(0x1_0000_0000), 2) == 33)
        #expect(bitLen(u64(0xFFFF_FFFF_FFFF_FFFF), 2) == 64)
        #expect(ctz(u64(0x100), 1) == 8)
        #expect(ctz(u64(0x1_0000_0000), 2) == 32)
        #expect(isPowerOfTwo(u64(0x1_0000_0000), 2))
        #expect(!isPowerOfTwo(u64(0x3), 1))
    }

    @Test func fmaPow10AccumulatesDigits() {
        let x = u64(0)
        mutateFmaPow10(x, 1, 3, 5)        // 0*1000 + 5
        mutateFmaPow10(x, 1, 3, 123)      // 5*1000 + 123
        #expect(toRawULong(x, 1) == 5123)
    }
}
