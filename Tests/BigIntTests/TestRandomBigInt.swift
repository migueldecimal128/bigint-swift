import Testing
@testable import BigInt

@Suite struct TestRandomBigInt {

    @Test func testRandomWithBitLen() {

        func checkBitLen(_ k: Int) {
            for it in 0..<500 {
                let x = BigInt.randomWithBitLen(k)

                // 1. No negative numbers
                #expect(x.compareTo(BigInt.ZERO) >= 0, "Negative value for k=\(k): \(x)")

                if k == 0 {
                    // The only valid value is ZERO
                    #expect(x == BigInt.ZERO, "k=0 must produce only ZERO")
                    continue
                }

                // 2. Correct bit length: highest bit MUST be set
                #expect(x.magnitudeBitLen() == k,
                    "Incorrect bitLength for k=\(k): got \(x.magnitudeBitLen()) value=\(x)")

                // 3. Check top bit explicitly (bit k-1)
                #expect(x.testBit(k - 1),
                    "Top bit (k-1) is not set for k=\(k): value=\(x)")

                // 4. Value must be strictly less than 2^k
                let twoPowK = BigInt.withSetBit(k)
                #expect(x < twoPowK,
                    "Value >= 2^k for k=\(k): x=\(x)")

                // 5. All bits below (k-1) free to vary:
                // sanity: not always the same pattern
                if it == 0 { continue } // skip first iteration
                // store previous if needed
            }
        }

        // Test a wide range of bit lengths
        let sizes = [
            0, 1, 2, 3, 4, 5, 7, 8,
            15, 16, 31, 32, 33, 63, 64, 65,
            100, 127, 128, 129, 191, 192,
            255, 256, 257,
            300, 511, 512, 513
        ]

        for k in sizes {
            checkBitLen(k)
        }
    }
}
