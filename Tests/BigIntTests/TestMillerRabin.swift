import Testing
@testable import BigInt

@Suite struct TestMillerRabin {

    @Test func testKnownProblem() {
        // 2047 a known composite that passes MR base 2 but fails
        // with better bases
        let n = BigInt.from(Int32(23 * 89))

        // base 2 only
        #expect(BigIntPrime.isMillerRabinProbablePrime(n, [Int32(2)]))        // ==> true

        // 64-bit deterministic bases
        let bases64: [Int32] = [2, 325, 9375, 28178, 450775, 9780504, 1795265022]
        #expect(!BigIntPrime.isMillerRabinProbablePrime(n, bases64))
    }
}
