import Testing
@testable import BigInt

@Suite struct TestMbiDivRem64 {

    private func newLargeAcc(_ bits: Int) -> MutableBigInt {
        MutableBigInt().setBit(bits)
    }

    private func newAccFromDecimal(_ s: String) -> MutableBigInt {
        MutableBigInt().set(BigInt.from(s))
    }

    private func assertAccEquals(_ expected: BigInt, _ mbi: MutableBigInt) {
        #expect(mbi.toBigInt() == expected)
    }

    @Test func setDiv_singleBitLarge() {
        let dividend = newLargeAcc(256)
        let divisor: UInt64 = 0x1_0000_0001

        let out = MutableBigInt()
        out.setDiv(dividend, divisor)

        let expected = dividend.toBigInt() / BigInt.from(divisor)
        assertAccEquals(expected, out)
    }

    @Test func setDiv_denseMultiLimb() {
        let dividend = newAccFromDecimal(
            "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
        )
        let divisor: UInt64 = 0xFEDC_BA98_7654_3211

        let out = MutableBigInt()
        out.setDiv(dividend, divisor)

        let expected = dividend.toBigInt() / BigInt.from(divisor)
        assertAccEquals(expected, out)
    }

    @Test func setDiv_divisorNear64Bits() {
        let dividend = newLargeAcc(320)
        let divisor: UInt64 = 0xFFFF_FFFF_FFFF_FFFD

        let out = MutableBigInt()
        out.setDiv(dividend, divisor)

        let expected = dividend.toBigInt() / BigInt.from(divisor)
        assertAccEquals(expected, out)
    }

    @Test func setDiv_quotientZero() {
        let dividend = newLargeAcc(32)
        let divisor: UInt64 = 0x1_0000_0001

        let out = MutableBigInt()
        out.setDiv(dividend, divisor)

        let expected = BigInt.ZERO
        assertAccEquals(expected, out)
    }
}
