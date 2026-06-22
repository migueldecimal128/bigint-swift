// SPDX-License-Identifier: MIT
//
// Port of BigIntPrime.kt — Baillie–PSW primality testing for BigInt:
//   • Trial division by a fixed set of small primes
//   • A base-2 (here: Jaeschke-set) Miller–Rabin strong probable-prime test
//   • A strong Lucas probable-prime test (Selfridge parameter selection)
//
// Kotlin's `object BigIntPrime` becomes a Swift caseless enum namespace.
// Comparisons Kotlin writes as `n <= 1` / `n >= 0` on a BigIntNumber are
// expressed here via `.compareTo(...)`. The reference-identity guard
// `n !== tmp` becomes `(n as? MutableBigInt) !== tmp`.

import BigInt

public enum BigIntPrime {

    public static func nextProbablePrime(_ n: BigIntNumber) -> BigInt {
        if n.compareTo(Int32(1)) <= 0 {
            precondition(n.compareTo(Int32(0)) >= 0)
            return BigInt.TWO
        }
        let tmp = MutableBigInt()
        let candidate = MutableBigInt(n)
        candidate += Int32(n.isOdd() ? 2 : 1)
        while !isProbablePrime(candidate, tmp) {
            candidate += Int32(2)
        }
        return candidate.toBigInt()
    }

    /// Returns `true` if `n` is a probable prime (Baillie–PSW test).
    public static func isProbablePrime(_ n: BigIntNumber, _ tmp: MutableBigInt = MutableBigInt()) -> Bool {
        isBailliePSWProbablePrime(n, tmp)
    }

    public static func isBailliePSWProbablePrime(_ n: BigIntNumber, _ tmp: MutableBigInt = MutableBigInt()) -> Bool {
        precondition((n as? MutableBigInt) !== tmp)
        precondition(!n.isNegative())
        switch classifyBySmallPrimes(n, tmp) {
        case .composite: return false
        case .prime: return true
        case .inconclusive:
            let biN = n.toBigInt()
            if !isMillerRabinProbablePrimeBase2(biN, tmp) { return false }
            let selfridge = selectSelfridgeParams(biN)
            return selfridge.D != 0 && isStrongLucasProbablePrime(biN, selfridge)
        }
    }

    // TODO - there are multiple ways to pack this if need be. A byte array
    //  of deltas would cut the size in half, yet still be easy to handle.
    //  A bitmap would be harder to handle, but smaller.
    private static let SMALL_PRIMES: [Int32] = [
        3, 5, 7, 11, 13, 17, 19, 23,
        29, 31, 37, 41, 43, 47, 53, 59,
        61, 67, 71, 73, 79, 83, 89, 97,
        101, 103, 107, 109, 113, 127, 131, 137,
        139, 149, 151, 157, 163, 167, 173, 179,
        181, 191, 193, 197, 199, 211, 223, 227,
        229, 233, 239, 241, 251, 257, 263, 269,
        271, 277, 281, 283, 293, 307, 311, 313,
        317, 331, 337, 347, 349, 353, 359, 367,
        373, 379, 383, 389, 397, 401, 409, 419,
        421, 431, 433, 439, 443, 449, 457, 461,
        463, 467, 479, 487, 491, 499, 503, 509,
        521, 523, 541, 547, 557, 563, 569, 571,
        577, 587, 593, 599, 601, 607, 613, 617,
        619, 631, 641, 643, 647, 653, 659, 661,
        673, 677, 683, 691, 701, 709, 719, 727
    ]

    private enum SmallPrimeResult {
        case composite, prime, inconclusive
    }

    private static func classifyBySmallPrimes(
        _ n: BigIntNumber,
        _ tmp: MutableBigInt
    ) -> SmallPrimeResult {
        precondition((n as? MutableBigInt) !== tmp)
        if n.compareTo(Int32(1)) <= 0 { return .composite }
        if n.compareTo(Int32(3)) <= 0 { return .prime }
        if n.isEven() { return .composite }
        for p in SMALL_PRIMES {
            let mod = n.modInt(p)
            if mod == 0 {
                return n.EQ(p) ? .prime : .composite
            }
        }
        return .inconclusive
    }

    /// Strong Miller–Rabin probable-prime test on odd `n >= 3` for the given `bases`.
    public static func isMillerRabinProbablePrime(
        _ n: BigInt, _ bases: [Int32],
        _ tmpP: MutableBigInt? = nil
    ) -> Bool {
        precondition(n.compareTo(Int32(3)) >= 0 && n.isOdd())
        let nMinusOne = n - Int32(1)
        let s = nMinusOne.countTrailingZeroBits()
        let d = nMinusOne.ushr(s)

        let ctx = ModContext(n)
        let tmp = tmpP ?? MutableBigInt()

        for a in bases {
            if n.compareTo(a) <= 0 { continue }   // important for small n

            ctx.modPow(BigInt.from(a), d, tmp)

            if tmp.isOne() || tmp.EQ(nMinusOne) { continue }

            var witness = true
            var rep = 0
            while rep < s - 1 {
                ctx.modSqr(tmp, tmp)
                if tmp.EQ(nMinusOne) {
                    witness = false
                    break
                }
                rep += 1
            }

            if witness { return false }
        }
        return true
    }

    private static let MILLER_RABIN_BASE_2: [Int32] = [2]

    /// Strong Miller–Rabin probable-prime test to base 2 (the Baillie–PSW MR stage).
    public static func isMillerRabinProbablePrimeBase2(_ n: BigInt, _ tmp: MutableBigInt? = nil) -> Bool {
        isMillerRabinProbablePrime(n, MILLER_RABIN_BASE_2, tmp)
    }

    /// Deterministic Miller–Rabin bases sufficient for all `n < 2^64`
    /// (Jaeschke, Sinclair, Feitsma, & Galway).
    private static let MILLER_RABIN_JAESCHKE_BASES: [Int32] = [
        2,
        325,
        9375,
        28178,
        450775,
        9780504,
        1795265022
    ]

    public static func isMillerRabinProbablePrimeJaeschke(_ n: BigInt, _ tmp: MutableBigInt?) -> Bool {
        isMillerRabinProbablePrime(n, MILLER_RABIN_JAESCHKE_BASES, tmp)
    }

    /// Computes the Jacobi symbol `(a | n)`.
    public static func jacobi(_ a: Int32, _ n: Int32) -> Int { jacobi(a, BigInt.from(n)) }

    /// Computes the Jacobi symbol `(a | n)`; returns -1, 0, or 1.
    public static func jacobi(_ a: Int32, _ n: BigInt) -> Int {
        precondition(n.compareTo(Int32(0)) > 0 && n.isOdd())
        var v = n.toMutableBigInt()
        var u = MutableBigInt(a)
        u %= v
        if u.compareTo(Int32(0)) < 0 { u += n }
        var j = 1
        while u.isNotZero() {
            while u.isEven() {
                u.mutShr(1)
                precondition(!v.isNegative())
                let v8 = v.toInt() & 0x07
                if v8 == 3 || v8 == 5 { j = -j }
            }
            // swap
            let t = u; u = v; v = t
            if (u.toInt() & 3) == 3 && (v.toInt() & 3) == 3 { j = -j }
            u %= v
        }
        return v.EQ(Int32(1)) ? j : 0
    }

    /// Parameters `(D, P, Q)` for Lucas sequences, Selfridge-selected.
    public struct LucasParams: Sendable {
        public let D: Int32
        public let P: Int32
        public let Q: Int32
    }

    private static let LUCAS_COMPOSITE = LucasParams(D: 0, P: 0, Q: 0)

    /// Selects Lucas parameters `(D, P, Q)` via the Selfridge method.
    public static func selectSelfridgeParams(_ n: BigInt) -> LucasParams {
        precondition(n.isPositive() && n.isOdd())
        if n.isPerfectSquare() { return LUCAS_COMPOSITE }
        var D: Int32 = 5
        var sign: Int32 = 1
        while true {
            let dSigned = sign * D
            let jac = jacobi(dSigned, n)
            if jac == -1 {
                // P = 1, Q = (1 - D) / 4  (exact, D ≡ 1 mod 4)
                let Q = (1 - dSigned) >> 2
                return LucasParams(D: dSigned, P: 1, Q: Q)
            }
            if jac == 0 {
                // gcd(D, n) > 1 ⇒ composite unless n == |D|
                if n.EQ(D) {
                    let Q = (1 - dSigned) >> 2
                    return LucasParams(D: dSigned, P: 1, Q: Q)
                }
                return LUCAS_COMPOSITE
            }
            // next D in 5, -7, 9, -11, 13, ...
            D += 2
            sign = -sign
        }
    }

    /// Strong Lucas probable-prime test on `n` with Lucas params `params`.
    public static func isStrongLucasProbablePrime(
        _ n: BigInt,
        _ params: LucasParams
    ) -> Bool {

        // n + 1 = d * 2^s, with d odd
        let n1 = n + Int32(1)
        let s = n1.countTrailingZeroBits()
        let d = n1.shr(s)

        let modCtx = ModContext(n)
        // U_d, V_d, Q^d (all normalized mod n)
        let (U, V, Qk) = lucasUVQk(modCtx, d, params.D, params.Q)

        if U.isZero() || V.isZero() { return true }

        var Vcur = V
        var Qcur = Qk

        var rep = 0
        while rep < s - 1 {
            Vcur = (Vcur * Vcur - Qcur.shl(1)).mod(n)
            Qcur = (Qcur * Qcur).mod(n)
            if Vcur.isZero() { return true }
            rep += 1
        }

        return false
    }

    /// Computes Lucas sequence values `U_d`, `V_d`, `Q^d (mod n)` (allocation-free
    /// variant using a ModContext). `d` is odd.
    public static func lucasUVQk(
        _ modCtx: ModContext,
        _ d: BigInt,   // odd
        _ D: Int32,
        _ Q: Int32
    ) -> (BigInt, BigInt, BigInt) {

        var U = MutableBigInt(Int32(1))
        var V = MutableBigInt(Int32(1))
        var Qk = MutableBigInt()
        modCtx.modSet(Q, Qk)

        var U2m = MutableBigInt()
        var V2m = MutableBigInt()
        let V2 = MutableBigInt()
        let QkDoubled = MutableBigInt()
        var Q2m = MutableBigInt()
        var U2m1 = MutableBigInt()
        var V2m1 = MutableBigInt()
        var Q2m1 = MutableBigInt()
        let tmp1 = MutableBigInt()
        let tmp2 = MutableBigInt()

        var i = d.magnitudeBitLen() - 2
        while i >= 0 {
            let bit = d.testBit(i)

            // U2m = (U * V) mod n
            modCtx.modMul(U, V, U2m)

            // V2m = (V * V - (Qk shl 1)) mod n
            modCtx.modSqr(V, V2)
            modCtx.modAdd(Qk, Qk, QkDoubled)
            modCtx.modSub(V2, QkDoubled, V2m)

            // Q2m = (Qk * Qk) mod n
            modCtx.modSqr(Qk, Q2m)

            if !bit {
                let swapU = U; U = U2m; U2m = swapU
                let swapV = V; V = V2m; V2m = swapV
                let swapQk = Qk; Qk = Q2m; Q2m = swapQk
            } else {
                // U2m1 = modHalfLucas((U2m + V2m) mod n, n)
                modCtx.modAdd(U2m, V2m, tmp1)
                modCtx.modHalfLucas(tmp1, U2m1)

                // V2m1 = modHalfLucas((V2m + (U2m * D)) mod n, n)
                modCtx.modMul(U2m, D, tmp1)
                modCtx.modAdd(V2m, tmp1, tmp2)
                modCtx.modHalfLucas(tmp2, V2m1)

                // Q2m1 = (Q2m * Q) mod n
                modCtx.modMul(Q2m, Q, Q2m1)

                let swapU = U; U = U2m1; U2m1 = swapU
                let swapV = V; V = V2m1; V2m1 = swapV
                let swapQk = Qk; Qk = Q2m1; Q2m1 = swapQk
            }
            i -= 1
        }

        return (U.toBigInt(), V.toBigInt(), Qk.toBigInt())
    }

    /// Computes Lucas sequence values `U_d`, `V_d`, `Q^d (mod n)` using plain
    /// BigInt arithmetic (left-to-right binary method). `d` is odd.
    public static func lucasUVQk_BigInt(
        _ n: BigInt,
        _ d: BigInt,   // odd
        _ D: Int32,
        _ Q: Int32
    ) -> (BigInt, BigInt, BigInt) {

        var U = BigInt.ONE
        var V = BigInt.ONE
        var Qk = BigInt.from(Q).mod(n)

        var i = d.magnitudeBitLen() - 2
        while i >= 0 {
            let bit = d.testBit(i)

            let U2m = (U * V).mod(n)
            let V2m = (V * V - Qk.shl(1)).mod(n)
            let Q2m = (Qk * Qk).mod(n)

            if !bit {
                U = U2m
                V = V2m
                Qk = Q2m
            } else {
                let U2m1 = modHalfLucas((U2m + V2m).mod(n), n)
                let V2m1 = modHalfLucas((V2m + (U2m * D)).mod(n), n)
                let Q2m1 = (Q2m * Q).mod(n)

                U = U2m1
                V = V2m1
                Qk = Q2m1
            }
            i -= 1
        }

        return (U, V, Qk)
    }

    /// Computes `x / 2` modulo odd modulus `n`. Precondition: `0 ≤ x < n`, `n` odd.
    private static func modHalfLucas(_ x: BigInt, _ n: BigInt) -> BigInt {
        precondition(n.isOdd())
        // x is already reduced mod n
        return x.isOdd() ? (x + n).shr(1) : x.shr(1)
    }
}

extension BigIntNumber {
    /// Baillie–PSW probable-prime test.
    public func isProbablePrime() -> Bool { BigIntPrime.isProbablePrime(self) }
    /// Smallest probable prime strictly greater than `self`.
    public func nextProbablePrime() -> BigInt { BigIntPrime.nextProbablePrime(self) }
}
