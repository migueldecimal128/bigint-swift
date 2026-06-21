import Testing
@testable import BigInt

@Suite struct TestBigIntModVsRem {

    @Test func mod_basicInvariant() {
        let n: Int32 = 7

        for x in Int32(-50)...50 {
            let r = BigInt.from(x).mod(n)
            #expect(r >= BigInt.ZERO, "negative result for x=\(x)")
            #expect(r < BigInt.from(n), "out of range for x=\(x)")
            #expect(r.toInt() == ((x % n) + n) % n, "wrong modulo for x=\(x)")
        }
    }

    @Test func mod_differsFromRemainderForNegativeValues() {
        let n: Int32 = 5

        let x = BigInt.from(Int32(-3))

        let rem = x % n
        let mod = x.mod(n)

        #expect(rem == BigInt.from(Int32(-3)))
        #expect(mod == BigInt.from(Int32(2)))
    }

    @Test func mod_zeroAlwaysZero() {
        let zero = BigInt.ZERO

        #expect(zero.mod(Int32(1)) == BigInt.ZERO)
        #expect(zero.mod(Int32(7)) == BigInt.ZERO)
        #expect(zero.mod(UInt64.max) == BigInt.ZERO)
    }

    @Test func mod_identityWhenAlreadyInRange() {
        let n: Int32 = 97

        for x in Int32(0)..<n {
            #expect(BigInt.from(x).mod(n) == BigInt.from(x),
                    "identity failed for x=\(x)")
        }
    }

    @Test func mod_largePositiveAndNegative() {
        let n: Int32 = 1_000_003 // prime, not power of two

        let big = BigInt.from("123456789012345678901234567890")
        let neg = -big

        let r1 = big.mod(n)
        let r2 = neg.mod(n)

        #expect(r1 >= BigInt.ZERO && r1 < BigInt.from(n))
        #expect(r2 >= BigInt.ZERO && r2 < BigInt.from(n))

        // x + (-x) ≡ 0 mod n
        #expect((r1 + r2).mod(n) == BigInt.ZERO)
    }

    @Test func mod_crossTypeConsistency() {
        let x = BigInt.from("98765432109876543210")

        let nInt: Int32 = 97
        let nUInt: UInt32 = 97
        let nLong: Int64 = 97
        let nULong: UInt64 = 97

        let r = x.mod(nInt)

        #expect(x.mod(nUInt) == r)
        #expect(x.mod(nLong) == r)
        #expect(x.mod(nULong) == r)
    }

    // PORT-NOTE: assertFailsWith<ArithmeticException> for a negative mod divisor
    // cannot be ported. The Swift port's mod(Int32:)/mod(Int64:) reject negative
    // divisors via throwModNegDivisor() which is `-> Never` (fatalError); a trap
    // is not catchable by swift-testing. Negative-divisor rejection is therefore
    // unasserted here.
    @Test func mod_negativeDivisorUsesAbsoluteValue() {
        let x = BigInt.from(Int32(-42))
        _ = x
    }

    @Test func mod_oneAlwaysZero() {
        for x in Int32(-100)...100 {
            #expect(BigInt.from(x).mod(Int32(1)) == BigInt.ZERO,
                    "mod 1 failed for x=\(x)")
        }
    }

    @Test func mod_preservesLucasInvariant() {
        let n: Int32 = 101
        let Qk = BigInt.from(Int32(-250))

        let r = Qk.mod(n)

        #expect(r >= BigInt.ZERO)
        #expect(r < BigInt.from(n))

        // value congruent modulo n
        #expect((Qk - r) % n == BigInt.ZERO)
    }

    @Test func mod_randomStress() {
        let rnd = BigIntRandom(Int64(1))
        let n: Int32 = 1_000_000_007

        for _ in 0..<10_000 {
            let x = BigInt.from(rnd.nextLong()) * BigInt.from(rnd.nextLong())
            let r = x.mod(n)

            #expect(r >= BigInt.ZERO)
            #expect(r < BigInt.from(n))
        }
    }
}
