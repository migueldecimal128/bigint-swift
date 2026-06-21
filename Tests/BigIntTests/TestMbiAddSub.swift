import Testing
@testable import BigInt

// Faithful transliteration of TestMbiAddSub.kt.

@Suite struct TestMbiAddSub {

    @Test func testAdd() {

    }

    private func bi(_ v: Int32) -> BigInt { BigInt.from(v) }
    private func mbi(_ v: Int32) -> MutableBigInt {
        MutableBigInt().set(bi(v) as BigIntNumber)
    }

    // all-ones mask of `n` bits, anchored at bit 0 (Kotlin `BigInt.withBitMask(n)`)
    private func bitMask(_ n: Int) -> BigInt { BigInt.withBitMask(n) }

    @Test func testAddAndSubAllCombinations() {
        let values: [Int32] = [-20, -5, -1, 0, 1, 5, 20]

        for x in values {
            for y in values {
                // --- Test Addition ---
                let accAdd = mbi(x).setAdd(bi(x), bi(y))
                let expectedAdd = x + y
                #expect(accAdd.toBigInt() == bi(expectedAdd), "FAILED: \(x) + \(y)")

                // --- Test Subtraction ---
                let accSub = mbi(x).setSub(bi(x), bi(y))
                let expectedSub = x - y
                #expect(accSub.toBigInt() == bi(expectedSub), "FAILED: \(x) - \(y)")
            }
        }
    }

    @Test func testAlias_this_is_x_add() {
        let mbi = MutableBigInt().set(bi(10) as BigIntNumber)     // mbi = 10
        mbi.setAdd(mbi.toBigInt(), bi(7))                         // mbi = mbi + 7
        #expect(mbi.toBigInt() == bi(17), "alias: this === x (addition) failed")
    }

    @Test func testAlias_this_is_y_add() {
        let mbi = MutableBigInt().set(bi(7) as BigIntNumber)      // mbi = 7
        mbi.setAdd(bi(10), mbi.toBigInt())                        // mbi = 10 + mbi
        #expect(mbi.toBigInt() == bi(17), "alias: this === y (addition) failed")
    }

    // ------------------------------------------------------------
    // 1. Test multi-limb carry propagation
    // ------------------------------------------------------------
    @Test func testLargeCarry() {
        // (2^1024 - 1) + 1 = 2^1024
        let x = bitMask(1024) - bi(1)   // all 1 bits
        let y = bi(1)

        let mbi = MutableBigInt().set(x as BigIntNumber)
        mbi.setAdd(x, y)

        let expected = bitMask(1024)
        #expect(mbi.toBigInt() == expected, "large carry propagation failed")
    }

    // ------------------------------------------------------------
    // 2. Test multi-limb borrow propagation
    // ------------------------------------------------------------
    @Test func testLargeBorrow() {
        // (2^1024) - 1
        let x = bitMask(1024)
        let y = bi(1)

        let mbi = MutableBigInt().set(x as BigIntNumber)
        mbi.setSub(x, y)

        let expected = bitMask(1024) - bi(1)
        #expect(mbi.toBigInt() == expected, "large borrow propagation failed")
    }

    // ------------------------------------------------------------
    // 3. Test large random add (no alias)
    // ------------------------------------------------------------
    @Test func testRandomLargeAdd() {
        let x = BigInt.randomWithBitLen(2000)
        let y = BigInt.randomWithBitLen(2000)

        let mbi = MutableBigInt().set(x as BigIntNumber)
        mbi.setAdd(x, y)

        let expected = x + y
        #expect(mbi.toBigInt() == expected, "random 2000-bit addition failed")
    }

    // ------------------------------------------------------------
    // 4. Test large random sub (no alias)
    // ------------------------------------------------------------
    @Test func testRandomLargeSub() {
        let x = BigInt.randomWithBitLen(2000)
        let y = BigInt.randomWithBitLen(2000)

        let mbi = MutableBigInt().set(x as BigIntNumber)
        mbi.setSub(x, y)

        let expected = x - y
        #expect(mbi.toBigInt() == expected, "random 2000-bit subtraction failed")
    }

    // ------------------------------------------------------------
    // 5. Test alias: this === x for large values
    // ------------------------------------------------------------
    @Test func testLargeAlias_this_is_x_add() {
        let x = BigInt.randomWithBitLen(1500)
        let y = BigInt.randomWithBitLen(1500)

        let mbi = MutableBigInt().set(x as BigIntNumber)
        mbi.setAdd(mbi.toBigInt(), y)

        let expected = x + y
        #expect(mbi.toBigInt() == expected, "alias (this === x) add failed")
    }

    // ------------------------------------------------------------
    // 6. Test alias: this === y for large values
    // ------------------------------------------------------------
    @Test func testLargeAlias_this_is_y_add() {
        let x = BigInt.randomWithBitLen(1500)
        let y = BigInt.randomWithBitLen(1500)

        let mbi = MutableBigInt().set(y as BigIntNumber)
        mbi.setAdd(x, mbi.toBigInt())

        let expected = x + y
        #expect(mbi.toBigInt() == expected, "alias (this === y) add failed")
    }

    // ------------------------------------------------------------
    // 7. Alias: doubling a large number (x == y == this)
    // ------------------------------------------------------------
    @Test func testLargeAlias_double() {
        let x = BigInt.randomWithBitLen(1800)

        let mbi = MutableBigInt().set(x as BigIntNumber)
        mbi.setAdd(mbi.toBigInt(), mbi.toBigInt())  // mbi = x + x

        let expected = x + x
        #expect(mbi.toBigInt() == expected, "alias (x == y == this) doubling failed")
    }

    // ------------------------------------------------------------
    // 8. Large subtract of identical values (alias)
    // ------------------------------------------------------------
    @Test func testLargeAlias_cancelToZero() {
        let x = BigInt.randomWithBitLen(1600)

        let mbi = MutableBigInt().set(x as BigIntNumber)
        mbi.setSub(mbi.toBigInt(), x)  // mbi = x - x

        let expected = BigInt.ZERO
        #expect(mbi.toBigInt() == expected, "alias subtract to zero failed")
    }
}
