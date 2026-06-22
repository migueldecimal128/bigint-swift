// SPDX-License-Identifier: MIT
//
// Number-theory helpers split out of core BigIntAlgorithms into BigIntMath:
// factorial, gcd/lcm (Stein), isqrt (Newton), isPerfectSquare. Exposed via
// extensions so BigInt.gcd(_:_:) and value.isqrt() keep their original call
// sites — consumers just add `import BigIntMath`.

import Foundation   // log2 (factorial), squareRoot (isqrt)
import BigInt

enum BigIntMathAlgorithms {

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
            precondition(isqrt &* isqrt <= dw && (isqrt &+ 1) &* (isqrt &+ 1) > dw)
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
}

extension BigInt {
    public static func factorial(_ n: Int) -> BigInt { BigIntMathAlgorithms.factorial(n) }
    public static func gcd(_ a: BigInt, _ b: BigInt) -> BigInt { BigIntMathAlgorithms.gcd(a, b) }
    public static func lcm(_ a: BigInt, _ b: BigInt) -> BigInt { BigIntMathAlgorithms.lcm(a, b) }
}

extension BigIntNumber {
    public func isqrt() -> BigInt { BigIntMathAlgorithms.isqrt(self) }
    public func isPerfectSquare() -> Bool { BigIntMathAlgorithms.isPerfectSquare(self) }
}
