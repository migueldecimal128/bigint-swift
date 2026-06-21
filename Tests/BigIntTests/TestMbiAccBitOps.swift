import Testing
@testable import BigInt

@Suite struct TestMbiAccBitOps {

    private func accOf(_ i: Int64) -> MutableBigInt { MutableBigInt().set(i) }
    private func bi(_ i: Int64) -> BigInt { BigInt.from(i) }

    // ----------------------------------------
    // Basic: setBit, clearBit, testBit
    // ----------------------------------------

    @Test func testSetBitOnZero() {
        var i = 0
        while i <= 200 {
            let mbi = MutableBigInt().setZero().setBit(i)
            let expected = BigInt.withSetBit(i)
            #expect(mbi.toBigInt() == expected, "setBit(\(i)) on zero")
            #expect(mbi.testBit(i))
            i += 17
        }
    }

    @Test func testClearBitOnZero() {
        var i = 0
        while i <= 200 {
            let mbi = MutableBigInt().setZero().clearBit(i)
            #expect(mbi.toBigInt() == BigInt.ZERO, "clearBit(\(i)) on zero")
            #expect(!mbi.testBit(i))
            i += 17
        }
    }

    @Test func testSetThenClearSameBit() {
        for i in 0...150 {
            let mbi = MutableBigInt().setZero()
            mbi.setBit(i)
            mbi.clearBit(i)

            #expect(mbi.toBigInt() == BigInt.ZERO, "setBit(\(i)) then clearBit(\(i))")
            #expect(!mbi.testBit(i))
        }
    }

    @Test func testClearThenSetSameBit() {
        for _ in 0...150 {
            let mbi = MutableBigInt().setOne().clearBit(0).setBit(0)
            #expect(mbi.toBigInt() == BigInt.ONE, "clearBit(0) then setBit(0)")
        }
    }

    // ----------------------------------------
    // Setting bits at & beyond current normLen
    // ----------------------------------------

    @Test func testSetBitExpandsMagnitude() {
        var mbi = MutableBigInt().set(Int32(5))  // 0b101
        mbi = mbi.setBit(10)                      // should grow into limb 0..10 bits

        let expected = bi(5).withSetBit(10)
        #expect(mbi.toBigInt() == expected, "setBit expanded magnitude")
        #expect(mbi.toBigInt().magnitudeBitLen() == 11)
    }

    @Test func testSetBitInsideExistingRange() {
        let mbi = accOf(0b1010).setBit(2) // already set? No -> becomes 1110
        let expected = bi(0b1110)
        #expect(mbi.toBigInt() == expected, "setBit inside range")
    }

    // ----------------------------------------
    // Clearing bits reduces magnitude
    // ----------------------------------------

    @Test func testClearHighestBitReducesNormLen() {
        let mbi = accOf(Int64(1) << 40).clearBit(40)
        #expect(mbi.toBigInt() == BigInt.ZERO, "clearing highest bit should normalize to zero")
    }

    @Test func testClearBitInsideMiddleDoesNotReduceNormLen() {
        let x = (Int64(1) << 40) | (Int64(1) << 20) | 1
        let mbi = accOf(x).clearBit(20)

        let expected = bi(x & ~(Int64(1) << 20))
        #expect(mbi.toBigInt() == expected)
    }

    // ----------------------------------------
    // Randomized tests for many bits
    // ----------------------------------------

    @Test func testRandomSetClearBits() {
        let rng = BigIntRandom.Default
        for _ in 0..<200 {
            let mbi = MutableBigInt().setZero()
            var ref = BigInt.ZERO

            for _ in 0..<50 {
                let b = Int(rng.nextInt(0, 301))

                if rng.nextInt(0, 2) == 0 {
                    mbi.setBit(b)
                    ref = ref.withSetBit(b)
                } else {
                    mbi.clearBit(b)
                    ref = ref.withClearBit(b)
                }

                #expect(mbi.toBigInt() == ref, "random bit op at \(b)")
            }
        }
    }

    // ----------------------------------------
    // testBit behavior
    // ----------------------------------------

    @Test func testTestBitMatchesReference() {
        let rng = BigIntRandom.Default
        for _ in 0..<200 {
            let mbi = MutableBigInt().setZero()
            var ref = BigInt.ZERO

            for _ in 0..<50 {
                let b = Int(rng.nextInt(0, 251))
                mbi.setBit(b)
                ref = ref.withSetBit(b)

                #expect(mbi.testBit(b))
                #expect(mbi.testBit(b) == ref.testBit(b))
            }

            for _ in 0..<50 {
                let b = Int(rng.nextInt(0, 251))
                mbi.clearBit(b)
                ref = ref.withClearBit(b)

                #expect(mbi.testBit(b) == ref.testBit(b))
            }
        }
    }
}
