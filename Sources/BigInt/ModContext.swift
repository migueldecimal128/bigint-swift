// SPDX-License-Identifier: MIT
//
// Port of ModContext.kt — reusable modular-arithmetic context for a fixed
// modulus. Barrett reduction for all moduli; Montgomery (with sliding-window
// modPow) for odd moduli. Comparisons that Kotlin writes as `>=`/`<` on
// MutableBigInt are expressed here via `.compareTo(...)`.

public final class ModContext {
    public let m: BigInt
    let kBits: Int
    private let barrett: Barrett
    private let montgomery: Montgomery?

    // modInv scratch (EEA), rotated buffers
    private var invR: MutableBigInt
    private var invNewR: MutableBigInt
    private var invTmpR: MutableBigInt
    private var invT: MutableBigInt
    private var invNewT: MutableBigInt
    private var invTmpT: MutableBigInt
    private let invQ: MutableBigInt
    private let invQNewR: MutableBigInt
    private let invQNewT: MutableBigInt

    public init(_ m: BigInt, useBarrettOnly: Bool = false) {
        if m.compareTo(Int32(1)) < 0 { fatalError() }
        self.m = m
        self.kBits = m.magnitudeBitLen()
        self.barrett = Barrett(m)
        self.montgomery = (m.isOdd() && !useBarrettOnly) ? Montgomery(m) : nil
        invR = MutableBigInt.withBitCapacityHint(kBits + 1)
        invNewR = MutableBigInt.withBitCapacityHint(kBits + 1)
        invTmpR = MutableBigInt.withBitCapacityHint(kBits + 1)
        invT = MutableBigInt.withBitCapacityHint(kBits + 1)
        invNewT = MutableBigInt.withBitCapacityHint(kBits + 1)
        invTmpT = MutableBigInt.withBitCapacityHint(kBits + 1)
        invQ = MutableBigInt.withBitCapacityHint(kBits + 1)
        invQNewR = MutableBigInt.withBitCapacityHint(kBits + 1)
        invQNewT = MutableBigInt.withBitCapacityHint(kBits + 1)
    }

    @discardableResult public func modSet(_ a: BigIntNumber, _ out: MutableBigInt) -> MutableBigInt { out.setMod(a, m) }
    @discardableResult public func modSet(_ a: Int32, _ out: MutableBigInt) -> MutableBigInt { out.set(a); return out.setMod(out, m) }
    @discardableResult public func modSet(_ a: Int64, _ out: MutableBigInt) -> MutableBigInt { out.set(a); return out.setMod(out, m) }

    public func modAdd(_ a: BigIntNumber, _ b: BigIntNumber, _ out: MutableBigInt) {
        out.setAdd(a, b)
        if out.compareTo(m) >= 0 { out -= m }
    }
    public func modAdd(_ a: BigIntNumber, _ b: Int32, _ out: MutableBigInt) { modAdd(a, Int64(b), out) }
    public func modAdd(_ a: BigIntNumber, _ b: Int64, _ out: MutableBigInt) {
        out.setAdd(a, b)
        if out.compareTo(m) >= 0 { out -= m }
    }

    public func modSub(_ a: BigIntNumber, _ b: BigIntNumber, _ out: MutableBigInt) {
        out.setSub(a, b)
        if out.isNegative() { out += m }
    }
    public func modSub(_ a: BigIntNumber, _ b: Int32, _ out: MutableBigInt) { modSub(a, Int64(b), out) }
    public func modSub(_ a: BigIntNumber, _ b: Int64, _ out: MutableBigInt) {
        out.setSub(a, b)
        if out.isNegative() { out += m }
    }

    public func modMul(_ a: BigIntNumber, _ b: BigIntNumber, _ out: MutableBigInt) { barrett.modMul(a, b, out) }
    public func modMul(_ a: BigIntNumber, _ b: Int32, _ out: MutableBigInt) { barrett.modMul(a, b, out) }
    public func modMul(_ a: BigIntNumber, _ b: Int64, _ out: MutableBigInt) { barrett.modMul(a, b, out) }
    public func modSqr(_ a: BigIntNumber, _ out: MutableBigInt) { barrett.modSqr(a, out) }

    public func modPow(_ base: BigIntNumber, _ exp: BigInt, _ out: MutableBigInt) {
        if let mont = montgomery { mont.modPow(base, exp, out) } else { barrett.modPow(base, exp, out) }
    }
    public func modPow(_ base: BigIntNumber, _ exp: Int, _ out: MutableBigInt) { modPow(base, Int64(exp), out) }
    public func modPow(_ base: BigIntNumber, _ exp: Int64, _ out: MutableBigInt) {
        if let mont = montgomery { mont.modPow(base, exp, out) } else { barrett.modPow(base, exp, out) }
    }

    public func modHalfLucas(_ a: MutableBigInt, _ out: MutableBigInt) { barrett.modHalfLucas(a, out) }

    /// Multiplicative inverse of `a` mod `m` (requires 0 ≤ a < m); throws if not invertible.
    public func modInv(_ a: BigIntNumber, _ out: MutableBigInt) {
        precondition(!a.isNegative() && a.compareTo(m) < 0)
        invR.set(m)
        invNewR.set(a)
        invT.setZero()
        invNewT.setOne()
        while invNewR.isNotZero() {
            invQ.setDiv(invR, invNewR)
            invQNewR.setMul(invQ, invNewR)
            invTmpR.setSub(invR, invQNewR)
            let rotateR = invR; invR = invNewR; invNewR = invTmpR; invTmpR = rotateR
            invQNewT.setMul(invQ, invNewT)
            invTmpT.setSub(invT, invQNewT)
            let rotateT = invT; invT = invNewT; invNewT = invTmpT; invTmpT = rotateT
        }
        if !invR.isOne() { fatalError("not invertible") }
        if invT.isNegative() { invT += m }
        if invT.compareTo(m) >= 0 { invT -= m }
        out.set(invT)
    }

    // MARK: Barrett

    private final class Barrett {
        let m: BigInt
        let mu: BigInt
        let mSquared: BigInt
        let kBits: Int
        let k: Int
        let shiftKMinus1Bits: Int
        let shiftKPlus1Bits: Int
        let bPowKPlus1: BigInt
        let q, r1, r2, mulTmp, baseTmp: MutableBigInt

        init(_ m: BigInt) {
            if m.isNegative() || m.compareTo(Int32(1)) <= 0 { fatalError("Barrett divisor must be >1") }
            self.m = m
            self.mu = Barrett.calcMu(m)
            self.mSquared = m.sqr()
            self.kBits = m.magnitudeBitLen()
            self.k = (kBits + 0x3F) >> 6
            self.shiftKMinus1Bits = (k - 1) * 64
            self.shiftKPlus1Bits = (k + 1) * 64
            self.bPowKPlus1 = BigInt.withSetBit(shiftKPlus1Bits)
            self.q = MutableBigInt.withBitCapacityHint(2 * kBits + 32)
            self.r1 = MutableBigInt.withBitCapacityHint(kBits + 32)
            self.r2 = MutableBigInt.withBitCapacityHint(2 * kBits + 32)
            self.mulTmp = MutableBigInt.withBitCapacityHint(2 * kBits + 32)
            self.baseTmp = MutableBigInt.withBitCapacityHint(2 * kBits + 32)
        }

        static func calcMu(_ m: BigInt) -> BigInt {
            BigInt.withSetBit(2 * Int(m.meta.normLen) * 64) / m
        }

        func reduceInto(_ x: MutableBigInt, _ out: MutableBigInt) {
            precondition(out !== q && out !== r1 && out !== r2 && out !== mulTmp)
            precondition(!x.isNegative())
            precondition(x.compareTo(mSquared) < 0)
            if x.compareTo(m) < 0 { out.set(x); return }
            let r = out
            q.set(x)
            q.mutShr(shiftKMinus1Bits)
            q *= mu
            q.mutShr(shiftKPlus1Bits)
            r1.set(x)
            r1.applyBitMask(shiftKPlus1Bits)
            r2.setMul(q, m)
            r2.applyBitMask(shiftKPlus1Bits)
            r.setSub(r1, r2)
            if r.isNegative() { r += bPowKPlus1 }
            if r.compareTo(m) >= 0 { r -= m }
            if r.compareTo(m) >= 0 { r -= m }
            if r.compareTo(m) >= 0 { fatalError() }
        }

        func modMul(_ a: BigIntNumber, _ b: BigIntNumber, _ out: MutableBigInt) {
            precondition(out !== mulTmp)
            mulTmp.setMul(a, b)
            reduceInto(mulTmp, out)
        }
        func modMul(_ a: BigIntNumber, _ b: Int64, _ out: MutableBigInt) {
            precondition((a as? MutableBigInt) !== mulTmp && out !== mulTmp)
            if b != 0 {
                mulTmp.setMul(a, b.magnitude)
                reduceInto(mulTmp, out)
                if b < 0 && out.isNotZero() { out.setSub(m, out) }
            } else {
                out.setZero()
            }
        }
        func modMul(_ a: BigIntNumber, _ b: Int32, _ out: MutableBigInt) {
            precondition((a as? MutableBigInt) !== mulTmp && out !== mulTmp)
            if b != 0 {
                mulTmp.setMul(a, UInt32(b.magnitude))
                reduceInto(mulTmp, out)
                if b < 0 && out.isNotZero() { out.setSub(m, out) }
            } else {
                out.setZero()
            }
        }
        func modSqr(_ a: BigIntNumber, _ out: MutableBigInt) {
            precondition(out !== mulTmp)
            mulTmp.setSqr(a)
            reduceInto(mulTmp, out)
        }

        func modPow(_ base: BigIntNumber, _ exp: BigIntNumber, _ out: MutableBigInt) {
            if exp.isNegative() { fatalError() }
            out.setOne()
            if exp.isZero() { return }
            baseTmp.set(base)
            if base.compareTo(m) >= 0 {
                if base.compareTo(mSquared) < 0 { reduceInto(baseTmp, baseTmp) }
                else { baseTmp.setRem(base, m) }
            }
            out.set(baseTmp)
            let topBitIndex = base_magBitLen(exp) - 1
            var i = topBitIndex - 1
            while i >= 0 {
                modSqr(out, out)
                if exp.testBit(i) { modMul(out, baseTmp, out) }
                i -= 1
            }
        }
        func modPow(_ base: BigIntNumber, _ exp: Int64, _ out: MutableBigInt) {
            if exp < 0 { fatalError() }
            out.setOne()
            if exp == 0 { return }
            baseTmp.set(base)
            if base.compareTo(m) >= 0 {
                if base.compareTo(mSquared) < 0 { reduceInto(baseTmp, baseTmp) }
                else { baseTmp.setRem(base, m) }
            }
            out.set(baseTmp)
            let topBitIndex = (64 - exp.leadingZeroBitCount) - 1
            var i = topBitIndex - 1
            while i >= 0 {
                modSqr(out, out)
                if ((Int64(1) << i) & exp) != 0 { modMul(out, baseTmp, out) }
                i -= 1
            }
        }

        func modHalfLucas(_ a: BigIntNumber, _ out: MutableBigInt) {
            precondition(m.isOdd())
            if (a as? MutableBigInt) !== out { out.set(a) }
            if out.isOdd() { out += m }
            out.mutShr(1)
        }
    }

    // MARK: Montgomery (odd modulus)

    final class Montgomery {
        let modulus: BigInt
        let k: Int
        let np: Limb
        let r2: BigInt
        let baseR = MutableBigInt()
        let xR = MutableBigInt()
        let MAX_WINDOW_WIDTH = 6
        var precomputedPowers: [MutableBigInt]

        init(_ modulus: BigInt) {
            precondition(modulus.compareTo(Int32(1)) >= 0 && modulus.isOdd())
            self.modulus = modulus
            self.k = Int(modulus.meta.normLen)
            self.np = Montgomery.computeNp(modulus.magia[0])
            // r2 = R^2 mod m, R = 2^(64·k); R^2 = 2^(2·64·k) = 2^(128·k)
            self.r2 = BigInt.withSetBit(128 * k) % modulus
            self.precomputedPowers = (0..<(1 << 6)).map { _ in MutableBigInt() }
        }

        // -n^-1 mod 2^64 (Newton doubling: 2→4→8→16→32→64 good bits, 5 steps)
        static func computeNp(_ n: Limb) -> Limb {
            precondition((n & 1) == 1)
            var x = (n &* 3) ^ 2     // ~2 good bits
            x = x &* (2 &- n &* x)   // 4
            x = x &* (2 &- n &* x)   // 8
            x = x &* (2 &- n &* x)   // 16
            x = x &* (2 &- n &* x)   // 32
            x = x &* (2 &- n &* x)   // 64
            return 0 &- x            // -n^-1 mod 2^64
        }

        @discardableResult func toMontgomery(_ x: BigIntNumber, _ out: MutableBigInt) -> MutableBigInt {
            out.setMul(x, r2).montgomeryRedc(modulus, np)
        }
        @discardableResult func fromMontgomery(_ xR: MutableBigInt) -> MutableBigInt {
            xR.montgomeryRedc(modulus, np)
        }
        @discardableResult func montMul(_ aR: BigIntNumber, _ bR: BigIntNumber, _ out: MutableBigInt) -> MutableBigInt {
            out.setMul(aR, bR).montgomeryRedc(modulus, np)
        }
        @discardableResult func montSqr(_ aR: BigIntNumber, _ out: MutableBigInt) -> MutableBigInt {
            out.setSqr(aR).montgomeryRedc(modulus, np)
        }

        func calcWindowSize(_ exp: BigIntNumber) -> Int {
            let n = exp.magnitudeBitLen()
            if n < 128 { return 3 }
            if n < 512 { return 4 }
            if n < 2048 { return 5 }
            return 6
        }

        func precomputeOddPowers(_ baseR: BigIntNumber, _ w: Int) {
            let numOdd = 1 << (w - 1)
            precomputedPowers[0].set(baseR)
            let baseSq = MutableBigInt()
            montMul(baseR, baseR, baseSq)
            for i in 1..<numOdd { montMul(precomputedPowers[i - 1], baseSq, precomputedPowers[i]) }
        }

        func modPow(_ base: BigIntNumber, _ exp: BigIntNumber, _ out: MutableBigInt) {
            precondition(!exp.isNegative())
            if exp.isZero() { out.set(Int32(1)); return }
            toMontgomery(base, baseR)
            toMontgomery(BigInt.ONE, xR)
            let w = calcWindowSize(exp)
            precomputeOddPowers(baseR, w)
            let bitLen = exp.magnitudeBitLen()
            var i = bitLen - 1
            while i >= 0 && !exp.testBit(i) { montSqr(xR, xR); i -= 1 }
            while i >= 0 {
                let maxWidth = min(w, i + 1)
                var width = 1
                var window = 1
                var j = 1
                while j < maxWidth {
                    if !exp.testBit(i - j) { break }
                    window = (window << 1) | 1
                    width += 1
                    j += 1
                }
                i -= width
                for _ in 0..<width { montSqr(xR, xR) }
                let idx = window >> 1
                montMul(xR, precomputedPowers[idx], xR)
                while i >= 0 && !exp.testBit(i) { montSqr(xR, xR); i -= 1 }
            }
            fromMontgomery(xR)
            out.set(xR)
        }

        func modPow(_ base: BigIntNumber, _ exp: Int64, _ out: MutableBigInt) {
            precondition(exp >= 0)
            if exp == 0 { out.set(Int32(1)); return }
            toMontgomery(base, baseR)
            toMontgomery(BigInt.ONE, xR)
            let bitLen = 64 - exp.leadingZeroBitCount
            var i = bitLen - 1
            while i >= 0 {
                montSqr(xR, xR)
                if ((Int64(1) << i) & exp) != 0 { montMul(xR, baseR, xR) }
                i -= 1
            }
            fromMontgomery(xR)
            out.set(xR)
        }
    }
}

// Kotlin reads exp.magnitudeBitLen() on a BigIntNumber; helper to avoid the
// `magnitudeBitLen` member-vs-free ambiguity inside the nested Barrett class.
private func base_magBitLen(_ x: BigIntNumber) -> Int { x.magnitudeBitLen() }
