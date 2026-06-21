import Testing
@testable import BigInt

// Faithful transliteration of TestBigIntWithBitMask.kt.

@Suite struct TestBigIntWithBitMask {

    @Test func testWithBitMaskInstanceVsFactory() {
        // Try a range of random values and mask shapes
        let rnd = BigIntRandom(Int64(12345))

        for _ in 0..<10_000 {
            // Create a random BigInt, sometimes negative
            let bitLen = Int(rnd.nextInt(Int32(1), Int32(300)))
            let x = BigInt.randomWithBitLen(bitLen, withRandomSign: true)

            let bitWidth = Int(rnd.nextInt(Int32(0), Int32(80)))      // covers 0, 1, multi-bit masks
            let bitIndex = Int(rnd.nextInt(Int32(0), Int32(200)))

            let instanceMasked = x.withBitMask(bitWidth, bitIndex)
            let factoryMask = BigInt.withBitMask(bitWidth, bitIndex)

            let expected = x.abs().and(factoryMask)

            #expect(instanceMasked == expected,
                    "Failed for x=\(x) width=\(bitWidth) index=\(bitIndex)")
        }
    }
}
