import Testing
@testable import BigInt

@Suite struct TestBigIntSqr {

    private func assertSqrEqualsMul(_ a: BigInt) {
        let sq = a.sqr()
        let mul = a * a
        #expect(sq == mul, "sqr() != a * a for a=\(a)")
    }

    @Test func zero() {
        assertSqrEqualsMul(BigInt.ZERO)
    }

    @Test func one() {
        assertSqrEqualsMul(BigInt.ONE)
    }

    @Test func minusOne() {
        assertSqrEqualsMul(BigInt.NEG_ONE)
    }

    @Test func smallIntegers() {
        for i in -20...20 {
            assertSqrEqualsMul(BigInt.from(Int32(i)))
        }
    }

    @Test func powersOfTwo() {
        let values: [Int64] = [
            Int64(1) << 1,
            Int64(1) << 5,
            Int64(1) << 16,
            Int64(1) << 31
        ]

        for v in values {
            assertSqrEqualsMul(BigInt.from(v))
            assertSqrEqualsMul(BigInt.from(-v))
        }
    }

    @Test func limbBoundaryValues() {
        // 32-bit limb boundaries
        let values: [Int64] = [
            Int64(0x7FFF_FFFF),
            Int64(0x8000_0000),
            Int64(0xFFFF_FFFF)
        ]

        for v in values {
            assertSqrEqualsMul(BigInt.from(v))
            assertSqrEqualsMul(BigInt.from(-v))
        }
    }

    @Test func multiLimbExactBoundary() {
        // exactly 2 limbs
        let a = BigInt.from("4294967296")
        assertSqrEqualsMul(a)
        assertSqrEqualsMul(-a)
    }

    @Test func multiLimbCarryPropagation() {
        let a = BigInt.from("0xFFFFFFFFFFFFFFFF")
        assertSqrEqualsMul(a)
    }

    @Test func denseBitPattern() {
        let a = BigInt.from("0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        assertSqrEqualsMul(a)
    }

    @Test func sparseBitPattern() {
        let a = BigInt.from("0x8000000000000001")
        assertSqrEqualsMul(a)
    }

    @Test func decimalStressValues() {
        let values = [
            "10",
            "99",
            "100000000000000000000",
            "999999999999999999999999999999"
        ]

        for s in values {
            assertSqrEqualsMul(BigInt.from(s))
        }
    }

    @Test func signInvariant() {
        let a = BigInt.from("-123456789012345678901234567890")
        let sq = a.sqr()
        #expect(!sq.isNegative(), "square must be non-negative")
    }

    @Test func zeroIsCanonical() {
        let z = BigInt.ZERO.sqr()
        // PORT-NOTE: Kotlin assertSame(BigInt.ZERO, z) checks reference identity;
        // BigInt is a Swift struct, so we assert canonical-magnitude identity.
        #expect(z.magia === BigInt.ZERO.magia)
    }
}
