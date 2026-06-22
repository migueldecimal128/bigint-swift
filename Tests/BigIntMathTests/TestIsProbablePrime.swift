import Testing
@testable import BigInt
@testable import BigIntMath

@Suite struct TestIsProbablePrime {

    private func bi(_ i: Int32) -> BigInt { BigInt.from(i) }

    @Test func testSmallValues() {
        let tmp = MutableBigInt()

        #expect(!BigIntPrime.isProbablePrime(bi(0), tmp))
        #expect(!BigIntPrime.isProbablePrime(bi(1), tmp))

        #expect(BigIntPrime.isProbablePrime(bi(2), tmp))
        #expect(BigIntPrime.isProbablePrime(bi(3), tmp))

        #expect(!BigIntPrime.isProbablePrime(bi(4), tmp))
    }

    @Test func testSmallPrimesInTable() {
        let tmp = MutableBigInt()

        let primes: [Int32] = [
            3, 5, 7, 11, 13, 17, 19, 23,
            29, 31, 37, 41, 43, 47,
            53, 59, 61, 67, 71, 73,
            79, 83, 89, 97, 101, 103,
            107, 109, 113, 127, 131,
            137, 139, 149, 151, 157,
            163, 167, 173, 179, 181,
            191, 193, 197, 199, 211,
            223, 227, 229, 233, 239,
            241, 251, 257, 263, 269,
            271, 277, 281, 283, 293,
            307, 311, 313, 317
        ]

        for p in primes {
            #expect(BigIntPrime.isProbablePrime(bi(p), tmp), "Prime \(p) incorrectly rejected")
        }
    }

    @Test func testSmallCompositeFactors() {
        let tmp = MutableBigInt()

        let composites: [Int32] = [
            9, 15, 21, 25, 27, 33, 35, 39,
            49, 51, 55, 57, 63, 77, 91,
            121, 143, 169, 187, 221, 289
        ]

        for c in composites {
            #expect(!BigIntPrime.isProbablePrime(bi(c), tmp), "Composite \(c) incorrectly accepted")
        }
    }

    @Test func testLargePrimeAndComposite() {
        let tmp = MutableBigInt()

        // 61-bit prime
        let prime = BigInt.from("2305843009213693951") // 2^61 − 1
        #expect(BigIntPrime.isProbablePrime(prime, tmp))

        // Same prime * 3
        let composite = prime * BigInt.from(Int32(3))
        #expect(!BigIntPrime.isProbablePrime(composite, tmp))
    }

    // PORT-NOTE: testNegativeRejected — Kotlin assertFailsWith<IllegalArgumentException>;
    // Swift uses precondition (fatalError, traps) which swift-testing cannot catch. Dropped.

    // PORT-NOTE: testIsProbablePrime_negative_throws — same as above (precondition trap). Dropped.

    @Test func testIsProbablePrime_trivial() {
        #expect(!BigIntPrime.isProbablePrime(BigInt.from(Int32(0))))
        #expect(!BigIntPrime.isProbablePrime(BigInt.from(Int32(1))))

        #expect(BigIntPrime.isProbablePrime(BigInt.from(Int32(2))))
        #expect(BigIntPrime.isProbablePrime(BigInt.from(Int32(3))))

        #expect(!BigIntPrime.isProbablePrime(BigInt.from(Int32(4))))
        #expect(!BigIntPrime.isProbablePrime(BigInt.from(Int32(9))))
    }

    @Test func testIsProbablePrime_smallValues() {
        let primes: [Int32] = [
            3, 5, 7, 11, 13, 17, 19, 23, 29, 31,
            37, 41, 43, 47, 53, 59, 61
        ]

        let composites: [Int32] = [
            4, 6, 8, 9, 10, 12, 14, 15, 16,
            18, 20, 21, 22, 24, 25, 27, 28
        ]

        for p in primes {
            #expect(BigIntPrime.isProbablePrime(BigInt.from(p)), "prime \(p)")
        }

        for c in composites {
            #expect(!BigIntPrime.isProbablePrime(BigInt.from(c)), "composite \(c)")
        }
    }

    @Test func testIsProbablePrime_carmichaelNumbers() {
        let carmichaels = [
            "561",
            "1105",
            "1729",
            "2465",
            "2821",
            "6601",
            "8911",
            "10585",
            "15841",
            "29341",
            "41041",
            "46657",
            "52633",
            "62745",
            "63973"
        ]

        for s in carmichaels {
            let n = BigInt.from(s)
            #expect(!BigIntPrime.isProbablePrime(n), "Carmichael incorrectly accepted: \(n)")
        }
    }

    @Test func testIsProbablePrime_knownLargePrimes() {
        let primes = [
            // Mersenne primes
            "2305843009213693951",         // 2^61 − 1
            "618970019642690137449562111", // 2^89 − 1
            "170141183460469231731687303715884105727", // 2**127 - 1
            "6864797660130609714981900799081393217269435300" +
                "14330540939446345918554318339765605212" +
                "25596406614545549772963113914808580371" +
                "21987999716643812574028291115057151", // 2**251 - 1

            // Random large primes
            "32416190071"  // 11-digit known prime
        ]

        for s in primes {
            let p = BigInt.from(s)
            #expect(BigIntPrime.isProbablePrime(p), "prime rejected: \(p)")
        }
    }

    @Test func testIsProbablePrime_largeComposites() {
        let composites = [
            // prime * prime
            (BigInt.from("2305843009213693951") *
                BigInt.from("2305843009213693951")),

            // prime * small
            (BigInt.from("2305843009213693951") * BigInt.from(Int32(3))),

            // near-prime even
            (BigInt.from("2305843009213693951") + BigInt.from(Int32(1))),

            BigInt.from("3825123056546413051"),
            BigInt.from("318665857834031151167461"),
            BigInt.from("803837457453639491257079614341942108138837688287558" +
                "14583748891752229742737653336521865023361639" +
                "60045457915042023603208766569966760987284043" +
                "96540823292873879185086916685732826776177102" +
                "93896977394701670823042868710999743997654414" +
                "48453411558724506334092790222752962294149842" +
                "30688168540432645753401832978611129896064484" +
                "5216191652872597534901")
        ]

        for n in composites {
            #expect(!BigIntPrime.isProbablePrime(n), "composite accepted: \(n)")
        }
    }

    @Test func testIsProbablePrime_regression_mersenne61() {
        let p = BigInt.from("2305843009213693951")
        #expect(BigIntPrime.isProbablePrime(p))
    }
}
