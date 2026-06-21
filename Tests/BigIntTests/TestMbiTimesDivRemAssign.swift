import Testing
@testable import BigInt

@Suite struct TestMbiTimesDivRemAssign {

    /* ---------- helpers ---------- */

    private func newAcc(_ value: Int64) -> MutableBigInt {
        let mbi = MutableBigInt()
        mbi += value
        return mbi
    }

    private func assertAccEqualsLong(_ expected: Int64, _ mbi: MutableBigInt) {
        let actual = mbi.toBigInt()
        let expectedBig = BigInt.from(expected)
        #expect(actual == expectedBig)
    }

    private func assertAccEqualsBig(_ expected: BigInt, _ mbi: MutableBigInt) {
        let actual = mbi.toBigInt()
        #expect(actual == expected)
    }

    private func newLargeAccFromDecimal(_ s: String) -> MutableBigInt {
        let mbi = MutableBigInt()
        let bi = BigInt.from(s)
        mbi += bi
        return mbi
    }

    private func newLargeAccShift(_ bits: Int) -> MutableBigInt {
        let mbi = MutableBigInt()
        mbi += BigInt.ONE
        mbi.mutShl(bits)   // assume you have in-place shift
        return mbi
    }

    /* ====================================================================== */
    /* ============================ timesAssign ============================== */
    /* ====================================================================== */

    @Test func timesAssign_Int() {
        var mbi: MutableBigInt

        mbi = newAcc(3)
        mbi *= Int32(2)
        assertAccEqualsLong(6, mbi)

        mbi = newAcc(3)
        mbi *= Int32(-2)
        assertAccEqualsLong(-6, mbi)

        mbi = newAcc(-3)
        mbi *= Int32(2)
        assertAccEqualsLong(-6, mbi)

        mbi = newAcc(-3)
        mbi *= Int32(-2)
        assertAccEqualsLong(6, mbi)
    }

    @Test func timesAssign_UInt() {
        var mbi: MutableBigInt

        mbi = newAcc(3)
        mbi *= UInt32(2)
        assertAccEqualsLong(6, mbi)

        mbi = newAcc(-3)
        mbi *= UInt32(2)
        assertAccEqualsLong(-6, mbi)
    }

    @Test func timesAssign_Long() {
        var mbi: MutableBigInt

        mbi = newAcc(3)
        mbi *= Int64(2)
        assertAccEqualsLong(6, mbi)

        mbi = newAcc(3)
        mbi *= Int64(-2)
        assertAccEqualsLong(-6, mbi)
    }

    @Test func timesAssign_ULong() {
        var mbi: MutableBigInt

        mbi = newAcc(3)
        mbi *= UInt64(2)
        assertAccEqualsLong(6, mbi)

        mbi = newAcc(-3)
        mbi *= UInt64(2)
        assertAccEqualsLong(-6, mbi)
    }

    @Test func timesAssign_BigInt() {
        var mbi: MutableBigInt
        let pos = BigInt.from(Int32(7))
        let neg = BigInt.from(Int32(-7))

        mbi = newAcc(3)
        mbi *= pos
        assertAccEqualsLong(21, mbi)

        mbi = newAcc(3)
        mbi *= neg
        assertAccEqualsLong(-21, mbi)
    }

    @Test func timesAssign_BigIntAccumulator() {
        var mbi: MutableBigInt
        let pos = newAcc(7)
        let neg = newAcc(-7)

        mbi = newAcc(3)
        mbi *= pos
        assertAccEqualsLong(21, mbi)

        mbi = newAcc(3)
        mbi *= neg
        assertAccEqualsLong(-21, mbi)
    }

    @Test func timesAssign_Zero() {
        var mbi: MutableBigInt

        mbi = newAcc(3)
        mbi *= Int32(0)
        assertAccEqualsLong(0, mbi)

        mbi = newAcc(-3)
        mbi *= Int64(0)
        assertAccEqualsLong(0, mbi)
    }

    @Test func timesAssign_Long_multiLimb() {
        let mbi = newLargeAccShift(192)   // 192 bits = 6 limbs
        let mul: Int64 = 0x1_0000_0001     // >32 bits

        let expected = mbi.toBigInt() * BigInt.from(mul)

        mbi *= mul

        assertAccEqualsBig(expected, mbi)
    }

    @Test func timesAssign_ULong_multiLimb() {
        let mbi = newLargeAccShift(224)   // 7 limbs
        let mul: UInt64 = 0x1_0000_0001

        let expected = mbi.toBigInt() * BigInt.from(mul)

        mbi *= mul

        assertAccEqualsBig(expected, mbi)
    }

    @Test func timesAssign_BigInt_multiLimb() {
        let mbi = newLargeAccShift(256)
        let mul = BigInt.from("18446744073709551617") // 2^64 + 1

        let expected = mbi.toBigInt() * mul

        mbi *= mul

        assertAccEqualsBig(expected, mbi)
    }


    /* ====================================================================== */
    /* ============================= divAssign =============================== */
    /* ====================================================================== */

    @Test func divAssign_Int() {
        var mbi: MutableBigInt

        mbi = newAcc(6)
        mbi /= Int32(2)
        assertAccEqualsLong(3, mbi)

        mbi = newAcc(6)
        mbi /= Int32(-2)
        assertAccEqualsLong(-3, mbi)

        mbi = newAcc(-6)
        mbi /= Int32(2)
        assertAccEqualsLong(-3, mbi)

        mbi = newAcc(-6)
        mbi /= Int32(-2)
        assertAccEqualsLong(3, mbi)
    }

    @Test func divAssign_UInt() {
        var mbi: MutableBigInt

        mbi = newAcc(6)
        mbi /= UInt32(2)
        assertAccEqualsLong(3, mbi)

        mbi = newAcc(-6)
        mbi /= UInt32(2)
        assertAccEqualsLong(-3, mbi)
    }

    @Test func divAssign_Long() {
        var mbi: MutableBigInt

        mbi = newAcc(6)
        mbi /= Int64(2)
        assertAccEqualsLong(3, mbi)

        mbi = newAcc(6)
        mbi /= Int64(-2)
        assertAccEqualsLong(-3, mbi)
    }

    @Test func divAssign_ULong() {
        var mbi: MutableBigInt

        mbi = newAcc(6)
        mbi /= UInt64(2)
        assertAccEqualsLong(3, mbi)

        mbi = newAcc(-6)
        mbi /= UInt64(2)
        assertAccEqualsLong(-3, mbi)
    }

    @Test func divAssign_BigInt() {
        var mbi: MutableBigInt
        let pos = BigInt.from(Int32(7))
        let neg = BigInt.from(Int32(-7))

        mbi = newAcc(21)
        mbi /= pos
        assertAccEqualsLong(3, mbi)

        mbi = newAcc(21)
        mbi /= neg
        assertAccEqualsLong(-3, mbi)
    }

    @Test func divAssign_BigIntAccumulator() {
        var mbi: MutableBigInt
        let pos = newAcc(7)
        let neg = newAcc(-7)

        mbi = newAcc(21)
        mbi /= pos
        assertAccEqualsLong(3, mbi)

        mbi = newAcc(21)
        mbi /= neg
        assertAccEqualsLong(-3, mbi)
    }

    @Test func divAssign_Long_multiLimb() {
        let mbi = newLargeAccFromDecimal(
            "12345678901234567890123456789012345678901234567890"
        )
        let div: Int64 = 0x1_0000_0001

        let expected = mbi.toBigInt() / BigInt.from(div)

        mbi /= div

        assertAccEqualsBig(expected, mbi)
    }

    @Test func divAssign_ULong_multiLimb() {
        let mbi = newLargeAccShift(240)
        let div: UInt64 = 0x1_0000_0001

        let expected = mbi.toBigInt() / BigInt.from(div)

        mbi /= div

        assertAccEqualsBig(expected, mbi)
    }

    @Test func divAssign_BigInt_multiLimb() {
        let mbi = newLargeAccShift(320)
        let div = BigInt.from("340282366920938463463374607431768211457") // 2^128+1

        let expected = mbi.toBigInt() / div

        mbi /= div

        assertAccEqualsBig(expected, mbi)
    }

    /* ====================================================================== */
    /* ============================= remAssign =============================== */
    /* ====================================================================== */

    @Test func remAssign_Int() {
        var mbi: MutableBigInt

        mbi = newAcc(7)
        mbi %= Int32(3)
        assertAccEqualsLong(1, mbi)

        mbi = newAcc(7)
        mbi %= Int32(-3)
        assertAccEqualsLong(1, mbi)

        mbi = newAcc(-7)
        mbi %= Int32(3)
        assertAccEqualsLong(-1, mbi)

        mbi = newAcc(-7)
        mbi %= Int32(-3)
        assertAccEqualsLong(-1, mbi)
    }

    @Test func remAssign_UInt() {
        var mbi: MutableBigInt

        mbi = newAcc(7)
        mbi %= UInt32(3)
        assertAccEqualsLong(1, mbi)

        mbi = newAcc(-7)
        mbi %= UInt32(3)
        assertAccEqualsLong(-1, mbi)
    }

    @Test func remAssign_Long() {
        var mbi: MutableBigInt

        mbi = newAcc(7)
        mbi %= Int64(3)
        assertAccEqualsLong(1, mbi)

        mbi = newAcc(-7)
        mbi %= Int64(3)
        assertAccEqualsLong(-1, mbi)
    }

    @Test func remAssign_ULong() {
        var mbi: MutableBigInt

        mbi = newAcc(7)
        mbi %= UInt64(3)
        assertAccEqualsLong(1, mbi)

        mbi = newAcc(-7)
        mbi %= UInt64(3)
        assertAccEqualsLong(-1, mbi)
    }

    @Test func remAssign_BigInt() {
        var mbi: MutableBigInt
        let pos = BigInt.from(Int32(3))
        let neg = BigInt.from(Int32(-3))

        mbi = newAcc(7)
        mbi %= pos
        assertAccEqualsLong(1, mbi)

        mbi = newAcc(7)
        mbi %= neg
        assertAccEqualsLong(1, mbi)

        mbi = newAcc(-7)
        mbi %= pos
        assertAccEqualsLong(-1, mbi)
    }

    @Test func remAssign_BigIntAccumulator() {
        var mbi: MutableBigInt
        let pos = newAcc(3)
        let neg = newAcc(-3)

        mbi = newAcc(7)
        mbi %= pos
        assertAccEqualsLong(1, mbi)

        mbi = newAcc(7)
        mbi %= neg
        assertAccEqualsLong(1, mbi)

        mbi = newAcc(-7)
        mbi %= pos
        assertAccEqualsLong(-1, mbi)
    }

    @Test func remAssign_ZeroDividend() {
        var mbi: MutableBigInt

        mbi = newAcc(0)
        mbi %= Int32(3)
        assertAccEqualsLong(0, mbi)

        mbi = newAcc(0)
        mbi %= Int64(3)
        assertAccEqualsLong(0, mbi)
    }

    @Test func remAssign_Long_multiLimb() {
        let mbi = newLargeAccFromDecimal(
            "99999999999999999999999999999999999999999999999999"
        )
        let div: Int64 = 0x1_0000_0001

        let expected = mbi.toBigInt() % BigInt.from(div)

        mbi %= div

        assertAccEqualsBig(expected, mbi)
    }

    @Test func remAssign_ULong_multiLimb() {
        let mbi = newLargeAccShift(288)
        let div: UInt64 = 0x1_0000_0001

        let expected = mbi.toBigInt() % BigInt.from(div)

        mbi %= div

        assertAccEqualsBig(expected, mbi)
    }

    @Test func remAssign_BigInt_multiLimb() {
        let mbi = newLargeAccShift(384)
        let div = BigInt.from("18446744073709551617") // 2^64+1

        let expected = mbi.toBigInt() % div

        mbi %= div

        assertAccEqualsBig(expected, mbi)
    }
}
