import Testing
@testable import BigInt

@Suite struct TestMbiApplyBitMask {

    @Test func testApplyBitMaskMatchesBigInt() {
        let rnd = BigIntRandom(Int64(12345))

        for _ in 0..<5000 {

            // --- Generate random BigInt value (positive or negative) ---
            let bitLen = Int(rnd.nextInt(Int32(1), Int32(400)))
            let x = BigInt.randomWithBitLen(bitLen, withRandomSign: true)

            // Create accumulator version
            let mbi = MutableBigInt().set(x)

            // --- Random mask parameters ---
            let bitWidth = Int(rnd.nextInt(Int32(0), Int32(150)))   // includes zero-width, 1-bit, wide masks
            let bitIndex = Int(rnd.nextInt(Int32(0), Int32(300)))

            // --- Expected result (immutable BigInt) ---
            let expected = x.withBitMask(bitWidth, bitIndex)

            // --- Actual result (mutable accumulator) ---
            mbi.applyBitMask(bitWidth, bitIndex)
            let actual = mbi.toBigInt()

            #expect(
                actual == expected,
                """
            Mismatch:
              x         = \(x)
              width     = \(bitWidth)
              index     = \(bitIndex)
              expected  = \(expected)
              actual    = \(actual)
            """
            )
        }
    }
}
