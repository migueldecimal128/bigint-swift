import Testing
@testable import BigInt

// Faithful transliteration of TestMbiSetClearBit.kt.
// Kotlin `1.toBigInt() shl k` → `BigInt.from(Int32(1)).shl(k)`.

@Suite struct TestMbiSetClearBit {

    private func mbi() -> MutableBigInt { MutableBigInt() }

    private func one() -> BigInt { BigInt.from(Int32(1)) }

    @Test func setBit_zeroBecomesOne() {
        let a = mbi().setBit(0)
        #expect(a.toBigInt() == BigInt.from(Int32(1)))
    }

    @Test func setBit_oneLimbHighBit() {
        let a = mbi().setBit(31) // top bit of first limb
        #expect(a.toBigInt() == one().shl(31))
    }

    @Test func setBit_crossesIntoSecondLimb() {
        let a = mbi().setBit(32)
        #expect(a.toBigInt() == one().shl(32))
    }

    @Test func setBit_largeIndex() {
        let a = mbi().setBit(200)
        #expect(a.toBigInt() == one().shl(200))
        // Check that normLen reflects enough limbs
        #expect(a.magnitudeBitLen() > 190)
    }

    @Test func setBit_twiceSameBit_noChange() {
        let a = mbi().setBit(50)
        let before = a.toBigInt()
        a.setBit(50)
        #expect(a.toBigInt() == before)
    }

    @Test func clearBit_clearsSingleBit() {
        let a = mbi().setBit(5)
        a.clearBit(5)
        #expect(a.toBigInt() == BigInt.ZERO)
    }

    @Test func clearBit_highBitShrinksNormalization() {
        let a = mbi().setBit(100)
        #expect(a.magnitudeBitLen() > 90)
        a.clearBit(100)
        #expect(a.toBigInt() == BigInt.ZERO)
        #expect(a.magnitudeBitLen() == 0)
    }

    @Test func clearBit_onlyMiddleBit() {
        let a = mbi().setBit(0).setBit(100)
        a.clearBit(0)
        #expect(a.toBigInt() == one().shl(100))
    }

    @Test func clearBit_whenAlreadyZero_noThrow() {
        let a = mbi().setBit(60)
        a.clearBit(10) // was zero
        #expect(a.toBigInt() == one().shl(60))
    }

    @Test func setBit_thenClearBit_backAndForth() {
        let a = mbi()
        a.setBit(7);  #expect(a.toBigInt() == one().shl(7))
        a.setBit(70); #expect(a.toBigInt() == one().shl(7) + one().shl(70))
        a.clearBit(7); #expect(a.toBigInt() == one().shl(70))
        a.clearBit(70); #expect(a.toBigInt() == BigInt.ZERO)
    }

    @Test func clearBit_at32Boundary() {
        let a = mbi().setBit(32).setBit(2)
        a.clearBit(32)
        #expect(a.toBigInt() == one().shl(2))
    }
}
