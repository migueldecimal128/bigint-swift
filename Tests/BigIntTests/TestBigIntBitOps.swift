import Testing
@testable import BigInt

@Suite struct TestBigIntBitOps {

    private func bi(_ l: Int64) -> BigInt { BigInt.from(l) }

    @Test func testBit_basic() {
        let x = bi(0b101101)

        #expect(x.testBit(0))   // 1
        #expect(!x.testBit(1))  // 0
        #expect(x.testBit(2))   // 1
        #expect(x.testBit(3))   // 1
        #expect(!x.testBit(4))  // 0
        #expect(x.testBit(5))   // 1

        // out-of-range bits must be false
        #expect(!x.testBit(100))
    }

    @Test func withSetBit_basic() {
        let x = bi(0)

        let y = x.withSetBit(5)
        #expect(y == bi(32))              // 1<<5
        #expect(y.testBit(5))
        #expect(!y.testBit(4))

        // Setting an already-set bit returns same number
        let z = y.withSetBit(5)
        // PORT-NOTE: Kotlin assertSame (reference identity). BigInt is a Swift
        // value struct; assert value equality instead.
        #expect(z == y)
    }

    @Test func withClearBit_basic() {
        let x = bi(0b111100)

        let y = x.withClearBit(2)
        #expect(y == bi(0b111000))
        #expect(!y.testBit(2))

        // Clearing an already-clear bit returns same instance
        let z = y.withClearBit(2)
        // PORT-NOTE: Kotlin assertSame (reference identity) → value equality.
        #expect(z == y)
    }

    @Test func withSetBit_growsBitLength() {
        let x = bi(1)              // 0b1
        let y = x.withSetBit(100)  // should grow to bit 100

        #expect(y.testBit(100))
        #expect(y == bi(1).withSetBit(100))
        #expect(!y.testBit(99))
    }

    @Test func withClearBit_toZero() {
        let x = bi(1)
        let y = x.withClearBit(0)
        #expect(y == bi(0))
        #expect(y.isZero())
    }

    @Test func randomSetAndClear() {
        let rng = BigIntRandom.Default
        for _ in 0..<500 {
            let v = Int64(rng.nextInt(0, 1_000_001))
            let i = Int(rng.nextInt(0, 201))

            let x = bi(v)
            let set = x.withSetBit(i)
            let clear = x.withClearBit(i)

            // check correctness
            #expect(set.testBit(i))
            #expect(!clear.testBit(i))

            // clearing after setting → back to original (for in-range bits)
            let restored = set.withClearBit(i)
            if i < 63 {   // Long domain
                let expected = v & ~(Int64(1) << i)
                #expect(restored == bi(expected))
            }
        }
    }
}
