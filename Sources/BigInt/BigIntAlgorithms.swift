// SPDX-License-Identifier: MIT
//
// Port of BigIntAlgorithms.kt — factorial, gcd/lcm (Stein's binary GCD), pow
// (binary exponentiation), isqrt (Newton), montgomeryRedc (CIOS). Kotlin
// `object` → Swift caseless `enum`.

import Foundation   // log2 (factorial bit-length estimate)

enum BigIntAlgorithms {

    static func factorial(_ n: Int) -> BigInt {
        if n < 0 { fatalError("factorial of a negative number") }
        if n <= 20 {
            if n <= 1 { return BigInt.ONE }
            var f: Int64 = 1
            var i: Int64 = 2
            while i <= Int64(n) { f &*= i; i += 1 }
            return BigInt.from(f)
        }
        let bitCapacityRequired = estimateFactorialBitLen(n)
        let f = MutableBigInt.withBitCapacityHint(bitCapacityRequired)
        let twentyBang: Int64 = 2_432_902_008_176_640_000
        f.set(twentyBang)
        for i in 21...n { f *= Int32(i) }
        return f.toBigInt()
    }

    private static func estimateFactorialBitLen(_ n: Int) -> Int {
        if n < 2 { return 1 }
        let nn = Double(n)
        let log2e = 1.4426950408889634
        let pi = 3.141592653589793
        let term1 = nn * log2(nn)
        let term2 = -log2e * nn
        let term3 = 0.5 * log2(2 * pi * nn)
        let estimate = term1 + term2 + term3
        let correction = 0.12022644346 / nn
        let finalV = estimate + Double(Int64(correction)) + 1.0
        if finalV > Double(Int32.max) {
            fatalError("factorial will overflow max bitLen of Int.MAX_VALUE")
        }
        return Int(finalV)
    }

    /// Stein's binary GCD; result is non-negative.
    static func gcd(_ a: BigInt, _ b: BigInt) -> BigInt {
        if a.isZero() { return b.abs() }
        if b.isZero() { return a.abs() }
        var x = a.toMutableBigInt().mutAbs()
        var y = b.toMutableBigInt().mutAbs()
        let ctzX = x.countTrailingZeroBits()
        let ctzY = y.countTrailingZeroBits()
        let initialShift = min(ctzX, ctzY)
        x.mutShr(ctzX)
        y.mutShr(ctzY)
        while y.isNotZero() {
            y.mutShr(y.countTrailingZeroBits())
            if x.compareTo(y) > 0 { let swap = x; x = y; y = swap }
            y -= x
        }
        x.mutShl(initialShift)
        return x.toBigInt()
    }

    static func lcm(_ a: BigInt, _ b: BigInt) -> BigInt {
        if a.isZero() || b.isZero() { return BigInt.ZERO }
        let aAbs = a.abs()
        let bAbs = b.abs()
        let g = gcd(aAbs, bAbs)
        if aAbs < bAbs { return (aAbs / g) * bAbs }
        return (bAbs / g) * aAbs
    }

    static func pow(_ base: BigInt, _ exp: Int) -> BigInt {
        let resultSign = base.isNegative() && ((exp & 1) != 0)
        let baseAbs = base.abs()
        if exp < 0 { fatalError("cannot raise BigInt to negative power:\(exp)") }
        if exp == 0 { return BigInt.ONE }
        if exp == 1 { return base }
        if exp == 2 { return baseAbs.sqr() }
        if base.isZero() { return BigInt.ZERO }
        if baseAbs.EQ(Int32(1)) { return resultSign ? BigInt.NEG_ONE : BigInt.ONE }
        if baseAbs.EQ(Int32(2)) { return BigInt.withSetBit(exp).withSign(resultSign) }
        let maxBitLen = base.magnitudeBitLen() * exp
        let r = MutableBigInt.withBitCapacityHint(maxBitLen).setOne()
        powLeftToRight(base, exp, r)
        return r.toBigInt()
    }

    @discardableResult
    static func tryPowFastPath(_ base: BigIntNumber, _ exp: Int, _ mbi: MutableBigInt) -> Bool {
        let resultSign = base.isNegative() && ((exp & 1) != 0)
        if exp < 0 { fatalError("cannot raise BigInt to negative power:\(exp)") }
        else if exp == 0 { mbi.setOne() }
        else if exp == 1 { mbi.set(base) }
        else if exp == 2 { mbi.setSqr(base) }
        else if base.isZero() { mbi.setZero() }
        else if base.magEQ(Int32(1)) { mbi.set(Int32(resultSign ? -1 : 1)) }
        else if base.magEQ(Int32(2)) { mbi.setBit(exp).mutWithSign(resultSign) }
        else { return false }
        return true
    }

    /// Left-to-right binary exponentiation; `ret` must not alias `base`.
    static func powLeftToRight(_ base: BigIntNumber, _ exp: Int, _ ret: MutableBigInt) {
        if exp <= 2 { fatalError() }   // should have been fast-path
        let maxBitLen = base.magnitudeBitLen() * exp
        ret.hintBitCapacity(maxBitLen).set(base)
        var bitIndex = 31 - Int(UInt32(exp).leadingZeroBitCount) - 1   // 32-bit clz on exp
        while bitIndex >= 0 {
            ret.setSqr(ret)
            if ((exp >> bitIndex) & 1) != 0 { ret *= base }
            bitIndex -= 1
        }
    }

    /// Integer square root: largest r with r*r ≤ n < (r+1)^2. Throws if negative.
    static func isqrt(_ radicand: BigIntNumber) -> BigInt {
        if radicand.isNegative() { fatalError("Square root of a negative BigInt") }
        let bitLen = radicand.magnitudeBitLen()
        if bitLen <= 53 {
            if bitLen == 0 { return BigInt.ZERO }
            if bitLen == 1 { return BigInt.ONE }
            let dw = radicand.toULong()
            let d = Double(dw)
            let sqrtV = d.squareRoot()
            var isqrt = UInt64(sqrtV)
            var crossCheck = isqrt &* isqrt
            isqrt = isqrt &+ ((crossCheck &- dw) >> 63)
            crossCheck = isqrt &* isqrt
            isqrt = isqrt &+ ((crossCheck &- dw) >> 63)
            crossCheck = isqrt &* isqrt
            isqrt = isqrt &- ((dw &- crossCheck) >> 63)
            verify(isqrt &* isqrt <= dw && (isqrt &+ 1) &* (isqrt &+ 1) > dw)
            return BigInt.from(Limb(truncatingIfNeeded: isqrt))
        }
        let topBitsIndex = (bitLen - 52) & ~1
        let top = radicand.extractULongAtBitIndex(topBitsIndex) &+ 2
        var topSqrt = UInt64(Double(top).squareRoot().rounded(.up))
        let crossCheck = topSqrt &* topSqrt
        topSqrt = topSqrt &+ ((crossCheck &- top) >> 63)   // add 1 iff crossCheck < top

        var x = MutableBigInt().set(topSqrt)
        x.setShl(x, topBitsIndex >> 1)

        var xPrev = MutableBigInt()
        repeat {
            let t = xPrev; xPrev = x; x = t
            x.setDiv(radicand, xPrev)
            x += xPrev
            x.mutShr(1)
        } while x.compareTo(xPrev) < 0
        return xPrev.toBigInt()
    }

    static func isPerfectSquare(_ radicand: BigIntNumber) -> Bool {
        let r = isqrt(radicand)
        let squared = r.sqr()
        return squared.EQ(radicand)
    }

    /// Montgomery REDC (CIOS), 64-bit limbs: t = t·R⁻¹ mod N, R = 2^(64·k).
    /// Returns the normalized limb length of the reduced residue.
    static func montgomeryRedc(_ t: Magia, _ tLen: Int, _ n: Magia, _ k: Int, _ np: Limb) -> Int {
        precondition(k > 0 && k <= n.size)
        precondition(tLen <= t.size)
        precondition(t.size >= 2 * k + 1)
        precondition((n[0] & 1) != 0)

        t.fill(0, tLen, 2 * k + 1)

        // Phase 1: eliminate low limbs one at a time
        for i in 0..<k {
            let m = t[i] &* np                    // (t[i] * np) mod 2^64
            var carry: DWord = 0
            var j = 0
            while j < k {
                let acc = DWord(t[i + j]) &+ DWord(m) &* DWord(n[j]) &+ carry
                t[i + j] = acc.toLimb()
                carry = acc >> 64
                j += 1
            }
            carry = carry &+ DWord(t[i + k])
            t[i + k] = carry.toLimb()
            // propagate the remaining carry through the high limbs (a single-limb
            // push loses a carry when t[i+k+1] is already 0xFFFF…FFFF — observable
            // for sparse moduli just above a power of two)
            var c = carry >> 64
            var idx = i + k + 1
            while c != 0 {
                let acc = DWord(t[idx]) &+ c
                t[idx] = acc.toLimb()
                c = acc >> 64
                idx += 1
            }
        }

        // Phase 2: shift down the upper half (forward self-copy, dest < src)
        t.copyInto(t, 0, k, k + k + 1)

        // Phase 3: conditional subtract modulus
        let tNormLen = magia_normLen(t, k + 1)
        if magia_compare(t, tNormLen, n, k) < 0 { return tNormLen }
        return magia_setSub(t, t, tNormLen, n, k)
    }
}
