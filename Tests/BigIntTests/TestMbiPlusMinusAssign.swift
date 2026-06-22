import Testing
@testable import BigInt

// Faithful transliteration of TestMbiPlusMinusAssign.kt.
// Kotlin `mbi += x` (operator-overload) → Swift `mbi += x` (MutableBigInt has the
// same compound-assignment operators). Kotlin `Long.toBigInt()` → `BigInt.from(_:)`.

@Suite struct TestMbiPlusMinusAssign {

    /* ---------- helpers ---------- */

    private func mbi(_ l: Int64) -> MutableBigInt {
        let m = MutableBigInt(); m += l; return m
    }

    // Integer literals bind to BigInt via ExpressibleByIntegerLiteral; BigInt
    // expecteds (the multi-limb cases) pass straight through.
    private func assertAccEquals(_ expected: BigInt, _ mbi: MutableBigInt) {
        #expect(mbi.toBigInt() == expected)
    }

    private func newLargeAcc(_ bits: Int) -> MutableBigInt {
        let mbi = MutableBigInt()
        mbi += BigInt.ONE
        mbi.mutShl(bits)   // explicit in-place shift
        return mbi
    }

    /* ---------- plusAssign primitives ---------- */

    @Test func plusAssign_Int() {
        let a = mbi(3); a += Int32(2);  assertAccEquals(5, a)
        let b = mbi(3); b += Int32(-2); assertAccEquals(1, b)
        let c = mbi(-3); c += Int32(2); assertAccEquals(-1, c)
        let d = mbi(-3); d += Int32(-2); assertAccEquals(-5, d)
    }

    @Test func plusAssign_UInt() {
        let a = mbi(3); a += UInt32(2);  assertAccEquals(5, a)
        let b = mbi(-3); b += UInt32(2); assertAccEquals(-1, b)
    }

    @Test func plusAssign_Long() {
        let a = mbi(3); a += Int64(2);  assertAccEquals(5, a)
        let b = mbi(3); b += Int64(-2); assertAccEquals(1, b)
        let c = mbi(-3); c += Int64(2); assertAccEquals(-1, c)
        let d = mbi(-3); d += Int64(-2); assertAccEquals(-5, d)
    }

    @Test func plusAssign_ULong() {
        let a = mbi(3); a += UInt64(2);  assertAccEquals(5, a)
        let b = mbi(-3); b += UInt64(2); assertAccEquals(-1, b)
    }

    /* ---------- plusAssign BigInt / Accumulator ---------- */

    @Test func plusAssign_BigInt() {
        let pos = BigInt.from(Int32(7))
        let neg = BigInt.from(Int32(-7))

        let a = mbi(3); a += pos; assertAccEquals(10, a)
        let b = mbi(3); b += neg; assertAccEquals(-4, b)
    }

    @Test func plusAssign_BigIntAccumulator() {
        let pos = mbi(7)
        let neg = mbi(-7)

        let a = mbi(3); a += pos; assertAccEquals(10, a)
        let b = mbi(3); b += neg; assertAccEquals(-4, b)
    }

    @Test func plusAssign_Long_multiLimb() {
        let mbi = newLargeAcc(192)
        let add: Int64 = 0x1_0000_0001

        let expected = mbi.toBigInt() + BigInt.from(add)

        mbi += add

        assertAccEquals(expected, mbi)
    }

    @Test func plusAssign_ULong_multiLimb() {
        let mbi = newLargeAcc(224)
        let add: UInt64 = 0x1_0000_0001

        let expected = mbi.toBigInt() + BigInt.from(add)

        mbi += add

        assertAccEquals(expected, mbi)
    }

    @Test func plusAssign_BigInt_multiLimb() {
        let mbi = newLargeAcc(256)
        let add = BigInt.from("18446744073709551617") // 2^64 + 1

        let expected = mbi.toBigInt() + add

        mbi += add

        assertAccEquals(expected, mbi)
    }

    @Test func plusAssign_BigIntAccumulator_multiLimb() {
        let mbi = newLargeAcc(288)
        let addAcc = newLargeAcc(160)

        let expected = mbi.toBigInt() + addAcc.toBigInt()

        mbi += addAcc

        assertAccEquals(expected, mbi)
    }

    @Test func plusAssign_negativeOperand_multiLimb() {
        let mbi = newLargeAcc(256)
        let add: Int64 = -0x1_0000_0001

        let expected = mbi.toBigInt() + BigInt.from(add)

        mbi += add

        assertAccEquals(expected, mbi)
    }

    /* ---------- minusAssign primitives ---------- */

    @Test func minusAssign_Int() {
        let a = mbi(3); a -= Int32(2);  assertAccEquals(1, a)
        let b = mbi(3); b -= Int32(-2); assertAccEquals(5, b)
        let c = mbi(-3); c -= Int32(2); assertAccEquals(-5, c)
        let d = mbi(-3); d -= Int32(-2); assertAccEquals(-1, d)
    }

    @Test func minusAssign_UInt() {
        let a = mbi(3); a -= UInt32(2);  assertAccEquals(1, a)
        let b = mbi(-3); b -= UInt32(2); assertAccEquals(-5, b)
    }

    @Test func minusAssign_Long() {
        let a = mbi(3); a -= Int64(2);  assertAccEquals(1, a)
        let b = mbi(3); b -= Int64(-2); assertAccEquals(5, b)
        let c = mbi(-3); c -= Int64(2); assertAccEquals(-5, c)
        let d = mbi(-3); d -= Int64(-2); assertAccEquals(-1, d)
    }

    @Test func minusAssign_ULong() {
        let a = mbi(3); a -= UInt64(2);  assertAccEquals(1, a)
        let b = mbi(-3); b -= UInt64(2); assertAccEquals(-5, b)
    }

    /* ---------- minusAssign BigInt / Accumulator ---------- */

    @Test func minusAssign_BigInt() {
        let pos = BigInt.from(Int32(7))
        let neg = BigInt.from(Int32(-7))

        let a = mbi(3); a -= pos; assertAccEquals(-4, a)
        let b = mbi(3); b -= neg; assertAccEquals(10, b)
    }

    @Test func minusAssign_BigIntAccumulator() {
        let pos = mbi(7)
        let neg = mbi(-7)

        let a = mbi(3); a -= pos; assertAccEquals(-4, a)
        let b = mbi(3); b -= neg; assertAccEquals(10, b)
    }

    /* ---------- zero / identity ---------- */

    @Test func addSubtractZero() {
        let a = mbi(3); a += Int32(0); assertAccEquals(3, a)
        let b = mbi(3); b -= Int32(0); assertAccEquals(3, b)
        let c = mbi(3); c += Int64(0); assertAccEquals(3, c)
        let d = mbi(3); d -= Int64(0); assertAccEquals(3, d)
    }

    @Test func minusAssign_Long_multiLimb() {
        let mbi = newLargeAcc(192)
        let sub: Int64 = 0x1_0000_0001

        let expected = mbi.toBigInt() - BigInt.from(sub)

        mbi -= sub

        assertAccEquals(expected, mbi)
    }

    @Test func minusAssign_ULong_multiLimb() {
        let mbi = newLargeAcc(224)
        let sub: UInt64 = 0x1_0000_0001

        let expected = mbi.toBigInt() - BigInt.from(sub)

        mbi -= sub

        assertAccEquals(expected, mbi)
    }

    @Test func minusAssign_BigInt_multiLimb() {
        let mbi = newLargeAcc(256)
        let sub = BigInt.from("340282366920938463463374607431768211457") // 2^128 + 1

        let expected = mbi.toBigInt() - sub

        mbi -= sub

        assertAccEquals(expected, mbi)
    }

    @Test func minusAssign_BigIntAccumulator_multiLimb() {
        let mbi = newLargeAcc(320)
        let subAcc = newLargeAcc(192)

        let expected = mbi.toBigInt() - subAcc.toBigInt()

        mbi -= subAcc

        assertAccEquals(expected, mbi)
    }

    @Test func minusAssign_negativeOperand_multiLimb() {
        let mbi = newLargeAcc(256)
        let sub: Int64 = -0x1_0000_0001

        let expected = mbi.toBigInt() - BigInt.from(sub)

        mbi -= sub

        assertAccEquals(expected, mbi)
    }
}
