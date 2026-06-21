import Testing
@testable import BigInt

@Suite struct TestDoubleToBigInt {

    let casesZero: [Double] = [
        0.0, -0.0,
        0.1, -0.1,
        0.99999999999,
        Double.leastNonzeroMagnitude,   // Kotlin Double.MIN_VALUE = smallest positive subnormal

        Double.nan,
        -Double.infinity,
        Double.infinity
    ]

    @Test func testZeros() {
        for tc in casesZero {
            #expect(BigInt.from(tc).isZero())
        }
    }

    let casesLong: [Double] = [
        1.0, 2.0, Double(Int64(1) << 53), 123456789012345.0
    ]

    @Test func testLongs() {
        for tc in casesLong {
            let l = Int64(tc)
            let bi = BigInt.from(tc)
            #expect(bi.EQ(l))
        }
    }

    @Test func testPow2() {
        var d = 1.0
        for i in 1..<1023 {
            d *= 2.0
            let hi = BigInt.from(d)
            #expect(hi.isMagnitudePowerOfTwo())
            #expect(hi.testBit(i))
        }
    }

    @Test func finiteSimpleIntegers() {
        let values: [Double] = [
            0.0,
            -0.0,
            1.0,
            -1.0,
            2.0,
            -2.0,
            123.0,
            -123.0,
            9_007_199_254_740_992.0,      // 2^53, largest integer exactly representable
            -9_007_199_254_740_992.0
        ]
        for d in values {
            #expect(BigInt.from(d).toLong() == Int64(d))
        }
    }

    @Test func fractionalTruncation() {
        let cases: [(Double, Int32)] = [
            (1.5, 1),
            (-1.5, -1),
            (123.9999, 123),
            (-123.9999, -123)
        ]
        for (dbl, expected) in cases {
            #expect(BigInt.from(dbl).toString() == BigInt.from(expected).toString())
        }
    }

    @Test func nonFiniteAreZero() {
        #expect(BigInt.from(Double.nan) == BigInt.ZERO)
        #expect(BigInt.from(Double.infinity) == BigInt.ZERO)
        #expect(BigInt.from(-Double.infinity) == BigInt.ZERO)
    }

    @Test func randomValues() {
        let rng = BigIntRandom.Default
        for _ in 0..<10_000 {
            let d = rng.nextDouble(-1e300, 1e300)

            if !d.isFinite {
                #expect(BigInt.from(d) == BigInt.ZERO)
                continue
            }

            let truncated = d >= 0 ? d.rounded(.down) : d.rounded(.up)
            let bi = BigInt.from(d).toString()

            // Compare string forms because the truncated value may exceed Long range
            #expect(bi == BigInt.from(truncated).toString())
        }
    }

    @Test func largeMagnitudeBoundary() {
        // Uses all 52 mantissa bits + exponent expansion
        let d = Double(bitPattern: 0x7FEF_FFFF_FFFF_FFFF) // largest finite double
        let bi = BigInt.from(d)

        let truncated = d >= 0 ? d.rounded(.down) : d.rounded(.up)
        #expect(bi.toString() == BigInt.from(truncated).toString())
    }
}
