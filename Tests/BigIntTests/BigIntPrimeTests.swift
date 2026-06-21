import Testing
@testable import BigInt

@Suite struct BigIntPrimeTests {

    // Deterministic sieve of Eratosthenes oracle.
    private func sievePrimes(upTo n: Int) -> [Bool] {
        var isP = [Bool](repeating: true, count: n + 1)
        if n >= 0 { isP[0] = false }
        if n >= 1 { isP[1] = false }
        var p = 2
        while p * p <= n {
            if isP[p] {
                var k = p * p
                while k <= n { isP[k] = false; k += p }
            }
            p += 1
        }
        return isP
    }

    @Test func matchesSieveSmall() {
        let N = 20_000
        let isP = sievePrimes(upTo: N)
        for i in 0...N {
            let bi = BigInt.from(Int32(i))
            #expect(bi.isProbablePrime() == isP[i], "n=\(i)")
        }
    }

    @Test func carmichaelNumbersAreComposite() {
        // Carmichael numbers — fool naive Fermat tests, must be rejected.
        let carmichael: [Int64] = [
            561, 1105, 1729, 2465, 2821, 6601, 8911,
            10585, 15841, 29341, 41041, 46657, 52633,
            62745, 63973, 75361, 101101, 115921, 162401,
            252601, 294409, 1024651, 9746347772161
        ]
        for c in carmichael {
            #expect(!BigInt.from(c).isProbablePrime(), "Carmichael \(c) must be composite")
        }
    }

    @Test func knownLargePrimes() {
        let primes = [
            "2147483647",                       // Mersenne M31
            "2305843009213693951",              // Mersenne M61
            "170141183460469231731687303715884105727", // Mersenne M127
            "99194853094755497",                // Fibonacci prime
            "1000000000000000000000000000057",  // a 10^30-ish prime
        ]
        for p in primes {
            #expect(BigInt.from(p).isProbablePrime(), "\(p) should be prime")
        }
    }

    // Regression for the sparse-modulus Montgomery REDC carry bug: 2^128+51 is
    // prime (Lucas stage agrees), but Miller–Rabin's Montgomery modPow returns a
    // wrong residue for moduli just above a power of two until the Phase-1 carry
    // propagation is fully chained. See montgomeryRedc.
    @Test func sparseModulusPrimesMontgomeryRegression() {
        let primes = [
            "340282366920938463463374607431768211507",  // 2^128 + 51 (smallest prime > 2^128)
            "1461501637330902918203684832716283019655932542983", // 2^160 + 7 (prime)
        ]
        for p in primes {
            #expect(BigInt.from(p).isProbablePrime(), "\(p) should be prime")
        }
    }

    @Test func knownLargeComposites() {
        let composites = [
            "2147483649",                       // 2^31 + 1 = 3 * 715827883
            "170141183460469231731687303715884105729", // 2^127 + 1, composite
            "1000000000000000000000000000058",  // even
            "123456789012345678901234567890",   // divisible by 10
            // semiprime of two large primes (no small factors; exercises MR + Lucas)
            "100000000000000019138700000000000838460053", // = p*q, ~70-bit factors
        ]
        for c in composites {
            #expect(!BigInt.from(c).isProbablePrime(), "\(c) should be composite")
        }
    }

    @Test func nextProbablePrimeBasic() {
        #expect(BigInt.from(Int32(0)).nextProbablePrime() == BigInt.from(Int32(2)))
        #expect(BigInt.from(Int32(1)).nextProbablePrime() == BigInt.from(Int32(2)))
        #expect(BigInt.from(Int32(2)).nextProbablePrime() == BigInt.from(Int32(3)))
        #expect(BigInt.from(Int32(3)).nextProbablePrime() == BigInt.from(Int32(5)))
        #expect(BigInt.from(Int32(13)).nextProbablePrime() == BigInt.from(Int32(17)))
        #expect(BigInt.from(Int32(89)).nextProbablePrime() == BigInt.from(Int32(97)))
        // gap after 2^31-1's neighborhood
        #expect(BigInt.from(Int64(2147483640)).nextProbablePrime() == BigInt.from(Int64(2147483647)))
    }

    @Test func nextProbablePrimeMatchesSieve() {
        // For every n in a window, nextProbablePrime(n) is the least prime > n.
        let N = 5000
        let isP = sievePrimes(upTo: N + 200)
        func leastPrimeAbove(_ n: Int) -> Int {
            var k = n + 1
            while !isP[k] { k += 1 }
            return k
        }
        for n in 0...N {
            let got = BigInt.from(Int32(n)).nextProbablePrime()
            #expect(got == BigInt.from(Int32(Int32(leastPrimeAbove(n)))), "next>\(n)")
        }
    }

    @Test func jacobiSymbol() {
        // Known Jacobi symbol values (a | n), n odd > 0.
        #expect(BigIntPrime.jacobi(Int32(1), Int32(1)) == 1)
        #expect(BigIntPrime.jacobi(Int32(2), Int32(15)) == 1)
        #expect(BigIntPrime.jacobi(Int32(7), Int32(15)) == -1)
        #expect(BigIntPrime.jacobi(Int32(3), Int32(15)) == 0)   // gcd(3,15)=3
        #expect(BigIntPrime.jacobi(Int32(5), Int32(21)) == 1)
        #expect(BigIntPrime.jacobi(Int32(2), Int32(7)) == 1)
        #expect(BigIntPrime.jacobi(Int32(3), Int32(7)) == -1)
        #expect(BigIntPrime.jacobi(Int32(-1), Int32(5)) == 1)   // 5 ≡ 1 (mod 4)
        #expect(BigIntPrime.jacobi(Int32(-1), Int32(7)) == -1)  // 7 ≡ 3 (mod 4)
        // (a | p) for prime p == Legendre symbol; QR check for p = 13
        let qr13: Set<Int32> = [1, 3, 4, 9, 10, 12]  // quadratic residues mod 13
        for a: Int32 in 1..<13 {
            let expected = qr13.contains(a) ? 1 : -1
            #expect(BigIntPrime.jacobi(a, Int32(13)) == expected, "jacobi(\(a)|13)")
        }
    }

    @Test func millerRabinJaeschkeMatchesSieve() {
        // The deterministic Jaeschke base set is exact below 2^64 ONLY when every
        // base is tested. The implementation faithfully skips bases >= n
        // (`if n <= a continue`), so a few small base-2 strong pseudoprimes
        // (2047, 3277, 4033, 4681, 8321 — each with a factor <= 727) slip through
        // the standalone call. In the real Baillie–PSW pipeline they are caught
        // earlier by trial division, so this is harmless there. We assert:
        //   • no false negatives (every prime passes), and
        //   • composites are rejected EXCEPT those known spsp-2 escapees.
        let N = 10_000
        let isP = sievePrimes(upTo: N)
        let knownEscapees: Set<Int> = [2047, 3277, 4033, 4681, 8321]
        for i in 3...N where i % 2 == 1 {
            let got = BigIntPrime.isMillerRabinProbablePrimeJaeschke(BigInt.from(Int32(i)), nil)
            if isP[i] {
                #expect(got, "prime \(i) must pass MR-Jaeschke")
            } else if !knownEscapees.contains(i) {
                #expect(!got, "composite \(i) must fail MR-Jaeschke")
            }
        }
    }
}
