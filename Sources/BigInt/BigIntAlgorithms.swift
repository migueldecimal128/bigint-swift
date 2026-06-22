// SPDX-License-Identifier: MIT
//
// Port of BigIntAlgorithms.kt — factorial, gcd/lcm (Stein's binary GCD), pow
// (binary exponentiation), isqrt (Newton), montgomeryRedc (CIOS). Kotlin
// `object` → Swift caseless `enum`.

import Foundation   // log2 (factorial bit-length estimate)

enum BigIntAlgorithms {

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
