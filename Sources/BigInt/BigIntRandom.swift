// SPDX-License-Identifier: MIT
//
// Port of the random BigInt factories from BigInt.kt. Kotlin draws on the
// stdlib `kotlin.random.Random`; Swift's `RandomNumberGenerator` protocol gives
// the unbiased typed draws (`Int.random(in:using:)`, `Bool.random(using:)`,
// `Double.random(in:using:)`), but its only stdlib conformer —
// `SystemRandomNumberGenerator` — is NOT seedable. The self-tests want seeded
// reproducibility (Kotlin `Random(12345)`), so `BigIntRandom` supplies the one
// thing stdlib lacks: a seedable `next() -> UInt64` (SplitMix64). Every bounded
// draw delegates to the stdlib; only the bit source is hand-rolled.
//
// It is a `final class` so a shared seeded stream behaves like Kotlin's
// reference-typed `Random` (passing it to several factories advances one stream).
// The random *values* are NOT sequence-identical to Kotlin (different PRNG); the
// self-tests are property tests against an oracle, so only correct ranges and
// uniformity matter, not byte-for-byte stream parity.

/// Seedable `RandomNumberGenerator` analog of `kotlin.random.Random`.
public final class BigIntRandom: RandomNumberGenerator {
    private var state: UInt64

    public init(_ seed: Int64) { state = UInt64(bitPattern: seed) }
    public init(_ seed: UInt64) { state = seed }

    /// Shared default instance (Kotlin `Random.Default`). Fixed seed so test
    /// runs that use the default RNG are reproducible.
    nonisolated(unsafe) public static let Default = BigIntRandom(0x2545_F491_4F6C_DD1D as UInt64)

    /// The sole hand-rolled primitive (SplitMix64) — the seedable bit source the
    /// stdlib does not provide. Everything else routes through stdlib randomness.
    public func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    // Kotlin-`Random`-named shims so the ported self-tests read like the
    // originals; each delegates to the (unbiased) stdlib generic. `var g = self`
    // gives an `inout`-able binding to the same instance (class → shared state).
    /// Uniform full-width `Int32` (negatives included), Kotlin `nextInt()`.
    public func nextInt() -> Int32 { Int32(truncatingIfNeeded: next()) }
    /// Uniform `Int32` in `[0, until)`. Kotlin `nextInt(until)`.
    public func nextInt(_ until: Int32) -> Int32 { var g = self; return Int32.random(in: 0..<until, using: &g) }
    /// Uniform `Int32` in `[from, until)`. Kotlin `nextInt(from, until)`.
    public func nextInt(_ from: Int32, _ until: Int32) -> Int32 { var g = self; return Int32.random(in: from..<until, using: &g) }
    /// Uniform full-width `Int64`, Kotlin `nextLong()`.
    public func nextLong() -> Int64 { Int64(bitPattern: next()) }
    /// Kotlin `nextBoolean()`.
    public func nextBoolean() -> Bool { var g = self; return Bool.random(using: &g) }
    /// Uniform `Double` in `[from, until)`, Kotlin `nextDouble(from, until)`.
    public func nextDouble(_ from: Double, _ until: Double) -> Double { var g = self; return Double.random(in: from..<until, using: &g) }
    public func nextDouble() -> Double { var g = self; return Double.random(in: 0..<1, using: &g) }
}

extension BigInt {

    /// Random BigInt with magnitude uniform in `0 ..< 2^maxBitLen`.
    public static func randomWithMaxBitLen(
        _ maxBitLen: Int,
        _ rng: BigIntRandom = BigIntRandom.Default,
        withRandomSign: Bool = false
    ) -> BigInt {
        if maxBitLen > 0 {
            var zeroTest: Limb = 0
            let magia = magia_newWithBitLen(maxBitLen)
            let topBits = maxBitLen & 0x1F
            // note parenthesization on this mask creation ... 0 - 1
            var mask: Limb = ((UInt32(bitPattern: 0 &- Int32(topBits)) >> 31) << topBits) &- 1
            var i = magia.size - 1
            while i >= 0 {
                let rand = Limb(bitPattern: rng.nextInt()) & mask
                magia[i] = rand
                zeroTest |= rand
                mask = Limb(bitPattern: -1)
                i -= 1
            }
            let sign = withRandomSign && rng.nextBoolean()
            if zeroTest != 0 {
                biStat(.BI_CONSTRUCT_RANDOM)
                return fromNonNormalizedManyNonZero(sign, magia)
            }
            return ZERO
        }
        if maxBitLen == 0 { return ZERO }
        throwBitLenLE0()
    }

    /// Random BigInt with a bit length uniform in `[bitLenMin, bitLenMax]`.
    public static func randomWithMaxBitLen(
        _ bitLenMin: Int,
        _ bitLenMax: Int,
        _ rng: BigIntRandom = BigIntRandom.Default,
        withRandomSign: Bool = false
    ) -> BigInt {
        let range = bitLenMax - bitLenMin
        if bitLenMin < 0 || range < 0 { throwInvalidBitLenRange() }
        let bitLen = bitLenMin + Int(rng.nextInt(Int32(range + 1)))
        return randomWithMaxBitLen(bitLen, rng, withRandomSign: withRandomSign)
    }

    /// Random BigInt with **exactly** `bitLen` bits (top bit always set).
    public static func randomWithBitLen(
        _ bitLen: Int,
        _ rng: BigIntRandom = BigIntRandom.Default,
        withRandomSign: Bool = false,
        ensureOdd: Bool = false
    ) -> BigInt {
        if bitLen > 0 {
            let magia = magia_newWithBitLen(bitLen)
            let topBits = bitLen & 0x1F
            var mask: Limb = ((UInt32(bitPattern: 0 &- Int32(topBits)) >> 31) << topBits) &- 1
            var i = magia.size - 1
            while i >= 0 {
                let rand = Limb(bitPattern: rng.nextInt()) & mask
                magia[i] = rand
                mask = Limb(bitPattern: -1)
                i -= 1
            }
            let topBitIndex = bitLen - 1
            let limbIndex = topBitIndex >> 5
            verify(limbIndex == magia.size - 1)
            magia[limbIndex] = magia[limbIndex] | (Limb(1) << (topBitIndex & 0x1F))
            magia[0] = magia[0] | (ensureOdd ? 1 : 0)
            let sign = withRandomSign && rng.nextBoolean()
            biStat(.BI_CONSTRUCT_RANDOM)
            return fromNormalizedNonZero(sign, magia)
        }
        if bitLen == 0 { return ZERO }
        throwBitLenLE0()
    }

    /// Random BigInt with bit length uniform in `0 .. maxBitLen`.
    public static func randomWithRandomBitLen(
        _ maxBitLen: Int,
        _ rng: BigIntRandom = BigIntRandom.Default,
        withRandomSign: Bool = false
    ) -> BigInt {
        randomWithMaxBitLen(Int(rng.nextInt(Int32(maxBitLen + 1))), rng, withRandomSign: withRandomSign)
    }

    /// Uniform random BigInt in `[0, max)` (rejection sampling). `max` must be > 0.
    public static func randomBelow(_ max: BigInt, _ rnd: BigIntRandom = BigIntRandom.Default) -> BigInt {
        precondition(max.compareTo(BigInt.ZERO) > 0, "max must be > 0 for randomBelow(max)")
        let bitLen = max.magnitudeBitLen()
        while true {
            let x = randomWithMaxBitLen(bitLen, rnd)
            if x.compareTo(max) < 0 { return x }
            biStatDec(.BI_CONSTRUCT_RANDOM)   // don't double-count
        }
    }
}
