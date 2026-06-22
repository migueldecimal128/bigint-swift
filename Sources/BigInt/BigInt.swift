// SPDX-License-Identifier: MIT
//
// Port of BigInt.kt — the immutable arbitrary-precision integer. Kotlin's
// `class BigInt : BigIntNumber, Comparable<BigInt>` becomes a value
// `struct BigInt: BigIntNumber, Comparable` (work order §6.1): copying shares
// the never-mutated `Magia` reference O(1).
//
// LOAD-BEARING INVARIANT: a `BigInt` never mutates its `Magia`. Every factory
// allocates a fresh `Magia` or shares one strictly read-only.
//
// This file currently covers the value façade + factories + conversions +
// comparison. Arithmetic operators (which delegate to MutableBigInt), String/
// Double parsing, bit ops, pow/gcd are DEFERRED (see marker at end).

// File-scope wrapper: the global `validateNormLenAndInjectPoison(_:_:)` is
// shadowed by the same-named BigIntNumber instance method inside BigInt's scope.
private func _validateNormLenAndInjectPoison(_ m: Magia, _ n: Int) -> Bool {
    validateNormLenAndInjectPoison(m, n)
}

public struct BigInt: BigIntNumber, Comparable {
    public let meta: Meta
    public let magia: Magia

    private init(_ meta: Meta, _ magia: Magia) {
        self.meta = meta
        self.magia = magia
    }

    // MARK: canonical constants
    // `nonisolated(unsafe)`: immutable shared values over a never-mutated Magia.

    nonisolated(unsafe) public static let ZERO = BigInt(Meta(0), MAGIA_ZERO)
    nonisolated(unsafe) public static let ONE = BigInt(Meta(1), MAGIA_ONE)
    nonisolated(unsafe) public static let TWO = BigInt(Meta(1), Magia(limbs: [2]))
    nonisolated(unsafe) public static let NEG_ONE = BigInt(Meta(signBit: 1, normLen: 1), MAGIA_ONE)
    nonisolated(unsafe) public static let TEN = BigInt(Meta(1), Magia(limbs: [10]))

    // MARK: internal normalized/non-normalized factories

    public static func fromNormalizedNonZero(_ magia: Magia) -> BigInt {
        fromNormalizedNonZero(false, magia)
    }
    public static func fromNormalizedNonZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        verify(magia.size > 0)
        verify(magia[magia.size - 1] != 0)
        return BigInt(Meta(signFlag: sign, normLen: Int32(magia.size)), magia)
    }
    public static func fromNormalizedNonZero(_ magia: Magia, _ normLen: Int) -> BigInt {
        verify(magia.size > 0 && _validateNormLenAndInjectPoison(magia, normLen))
        return BigInt(Meta(Int32(normLen)), magia)
    }
    public static func fromNormalizedNonZero(_ sign: Bool, _ magia: Magia, _ normLen: Int) -> BigInt {
        verify(magia.size > 0 && _validateNormLenAndInjectPoison(magia, normLen))
        return BigInt(Meta(signFlag: sign, normLen: Int32(normLen)), magia)
    }

    public static func fromNormalizedOrZero(_ magia: Magia) -> BigInt {
        fromNormalizedOrZero(false, magia)
    }
    public static func fromNormalizedOrZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        if magia.size == 0 {
            verify(magia === MAGIA_ZERO)
            return ZERO
        }
        verify(magia.size > 0)
        verify(magia[magia.size - 1] != 0)
        return BigInt(Meta(signFlag: sign, normLen: Int32(magia.size)), magia)
    }

    public static func fromNonNormalizedManyNonZero(_ magia: Magia) -> BigInt {
        fromNonNormalizedManyNonZero(false, magia)
    }
    public static func fromNonNormalizedManyNonZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        let nl = magia_normLen(magia)
        verify(nl > 0)
        verify(_validateNormLenAndInjectPoison(magia, nl))
        return BigInt(Meta(signFlag: sign, normLen: Int32(nl)), magia)
    }

    public static func fromNonNormalized1NonZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        let nl = magia.size - (magia[magia.size - 1] != 0 ? 0 : 1)
        verify(nl > 0)
        verify(_validateNormLenAndInjectPoison(magia, nl))
        return BigInt(Meta(signFlag: sign, normLen: Int32(nl)), magia)
    }

    public static func fromNonNormalizedOrZero(_ magia: Magia) -> BigInt {
        fromNonNormalizedOrZero(false, magia)
    }
    public static func fromNonNormalizedOrZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        let nl = magia_normLen(magia)
        if nl > 0 {
            verify(_validateNormLenAndInjectPoison(magia, nl))
            return BigInt(Meta(signFlag: sign, normLen: Int32(nl)), magia)
        }
        return ZERO
    }

    // MARK: primitive factories

    public static func from(_ n: Int32) -> BigInt {
        if n == 0 { return ZERO }
        biStat(.BI_CONSTRUCT_32)
        // n.magnitude (UInt32) handles Int32.min; one 64-bit limb either way
        return BigInt(Meta(signFlag: n < 0, normLen: 1), Magia(limbs: [Limb(n.magnitude)]))
    }

    public static func from(_ w: UInt32) -> BigInt {
        if w != 0 {
            biStat(.BI_CONSTRUCT_32)
            return BigInt(Meta(signFlag: false, normLen: 1), Magia(limbs: [Limb(w)]))
        }
        return ZERO
    }

    public static func from(_ sign: Bool, _ w: UInt32) -> BigInt {
        if w != 0 {
            biStat(.BI_CONSTRUCT_32)
            return BigInt(Meta(signFlag: sign, normLen: 1), Magia(limbs: [Limb(w)]))
        }
        return ZERO
    }

    public static func from(_ l: Int64) -> BigInt { from(l < 0, l.magnitude) }
    public static func from(_ dw: UInt64) -> BigInt { from(false, dw) }

    public static func from(_ sign: Bool, _ dwMagnitude: UInt64) -> BigInt {
        if dwMagnitude != 0 {
            biStat(.BI_CONSTRUCT_64)
            // a UInt64 magnitude is exactly one 64-bit limb
            return BigInt(Meta(signFlag: sign, normLen: 1), Magia(limbs: [dwMagnitude]))
        }
        return ZERO
    }

    /// Copy constructor from any BigIntNumber (immutable snapshot).
    public static func from(_ other: BigIntNumber) -> BigInt {
        biStat(.BI_CONSTRUCT_COPY)
        if !other.meta.isZero {
            return BigInt(other.meta, other.magia.copyOf(Int(other.meta.normLen)))
        }
        return ZERO
    }

    public static func from(_ sign: Bool, _ biMagnitude: BigIntNumber) -> BigInt {
        biStat(.BI_CONSTRUCT_COPY)
        return BigInt(Meta(signFlag: sign, normLen: biMagnitude.meta.normLen),
                      biMagnitude.magia.copyOf(Int(biMagnitude.meta.normLen)))
    }

    /// Constructs a BigInt from the integral part of a finite `Double` (truncates
    /// toward zero; +0/-0, sub-1 magnitudes, NaN and ±Inf all yield ZERO).
    public static func from(_ dbl: Double) -> BigInt {
        // 1 + 11 + 52 == 64
        let longBits = Int64(bitPattern: dbl.bitPattern)
        let sign = longBits < 0
        let signMask = longBits >> 63
        let biasedExp = Int((UInt64(bitPattern: longBits) >> 52) & 0x7FF)
        let exp = biasedExp - 1023
        if exp < 0 ||                 // +0, -0, fractional amounts
           biasedExp == 0x7FF {       // fractional values + NaN + Infinity
            return ZERO
        }
        // finite, non-zero
        biStat(.BI_CONSTRUCT_DBL)
        let significand53 = (longBits & ((Int64(1) << 52) - 1)) | (Int64(1) << 52)
        let shift = exp - 52
        if shift <= 0 {
            let magnitude = Int64(bitPattern: UInt64(bitPattern: significand53) >> -shift)
            let l = (magnitude ^ signMask) - signMask
            biStatDec(.BI_CONSTRUCT_64)   // don't double-count
            return from(l)
        }
        biStatDec(.BI_CONSTRUCT_BITWISE)  // don't double-count
        return fromULongShiftLeft(UInt64(bitPattern: significand53), shift, sign)
    }

    /// `(dw << shiftLeftCount)` with the given sign, as a BigInt.
    public static func fromULongShiftLeft(_ dw: UInt64, _ shiftLeftCount: Int, _ sign: Bool = false) -> BigInt {
        if shiftLeftCount >= 0 {
            let dwBitLen = 64 - dw.leadingZeroBitCount
            switch true {
            case shiftLeftCount == 0: return from(sign, dw)
            case dwBitLen == 0: return ZERO
            case dwBitLen == 1: return withSetBit(shiftLeftCount)
            default:
                let totalBitLen = dwBitLen + shiftLeftCount
                let magia = magia_newWithBitLen(totalBitLen)
                let innerShift = shiftLeftCount & 0x3F
                if innerShift == 0 {
                    // dw lands wholly in the top 64-bit limb
                    magia[magia.size - 1] = dw
                } else {
                    let lo = dw << innerShift
                    let hi = dw >> (64 - innerShift)   // high spill bits, 0 if none
                    if hi != 0 {
                        magia[magia.size - 1] = hi
                        magia[magia.size - 2] = lo
                    } else {
                        magia[magia.size - 1] = lo
                    }
                }
                biStat(.BI_CONSTRUCT_BITWISE)
                return fromNormalizedNonZero(sign, magia)
            }
        }
        throwBoundsCheckViolation()
    }

    // MARK: text factories (Phase 3 BigIntParsePrint)

    public static func from(_ str: String) -> BigInt { from(StringLatin1Iterator(str)) }
    public static func from(_ str: String, _ off: Int, _ len: Int) -> BigInt {
        from(StringLatin1Iterator(str, off, len))
    }
    private static func from(_ src: Latin1Iterator) -> BigInt {
        biStat(.BI_CONSTRUCT_TEXT)
        return fromNonNormalizedOrZero(src.peek() == "-", BigIntParsePrint.from(src))
    }

    public static func fromHex(_ str: String) -> BigInt { fromHex(StringLatin1Iterator(str)) }
    private static func fromHex(_ src: Latin1Iterator) -> BigInt {
        biStat(.BI_CONSTRUCT_TEXT)
        return fromNormalizedOrZero(src.peek() == "-", BigIntParsePrint.fromHex(src))
    }

    // MARK: BigIntNumber

    public func toBigInt() -> BigInt { self }   // already an immutable snapshot

    // MARK: Comparable / Equatable (numeric value semantics)

    public static func < (lhs: BigInt, rhs: BigInt) -> Bool { lhs.compareTo(rhs) < 0 }
    public static func == (lhs: BigInt, rhs: BigInt) -> Bool { lhs.compareTo(rhs) == 0 }

    // MARK: sign

    public func abs() -> BigInt { isNegative() ? BigInt(meta.abs(), magia) : self }
    public var absoluteValue: BigInt { abs() }

    public func negate() -> BigInt {
        if !isZero() {
            biStat(.BI_NEGATE)
            return BigInt(meta.negate(), magia)
        }
        return BigInt.ZERO
    }

    public func withSign(_ sign: Bool) -> BigInt { isNegative() == sign ? self : negate() }
    public func withSignOf(_ other: BigIntNumber) -> BigInt {
        isNegative() == other.isNegative() ? self : negate()
    }

    // MARK: square / pow / gcd / algorithms (Phase 3 BigIntAlgorithms)

    public func sqr() -> BigInt {
        if isNotZero() {
            let normLen = Int(meta.normLen)
            if normLen < KARATSUBA_SQR_THRESHOLD {
                let z = Magia(2 * normLen)
                let zNormLen = magia_setSqr(z, magia, normLen)
                return BigInt.fromNormalizedNonZero(z, zNormLen)
            }
            let z = Magia(2 * normLen + 1)
            let t = Magia(3 * ((normLen + 1) / 2) + 3)
            let zNormLen = magia_setSqrKaratsuba(z, magia, normLen, t)
            return BigInt.fromNormalizedNonZero(z, zNormLen)
        }
        return BigInt.ZERO
    }

    public func pow(_ exp: Int) -> BigInt { BigIntAlgorithms.pow(self, exp) }
    public func toMutableBigInt() -> MutableBigInt { MutableBigInt(self) }

    /// `2^bitIndex` as a BigInt.
    public static func withSetBit(_ bitIndex: Int) -> BigInt {
        if bitIndex < 0 { throwNegBitIndex() }
        if bitIndex == 0 { return ONE }
        let magia = magia_newWithBitLen(bitIndex + 1)
        magia[magia.size - 1] = 1 << (bitIndex & 0x3F)
        biStat(.BI_CONSTRUCT_BITWISE)
        return fromNormalizedNonZero(magia)
    }

    // factorial(_:) / gcd(_:_:) / lcm(_:_:) live in the BigIntMath module
    // (extensions on BigInt). Import BigIntMath to use them.

    // MARK: bit operations (magnitude-only; non-negative results)

    public func and(_ other: BigInt) -> BigInt {
        var iLast = min(Int(meta.normLen), Int(other.meta.normLen))
        let thisMagia = magia, otherMagia = other.magia
        if iLast <= thisMagia.size && iLast <= otherMagia.size {
            repeat {
                iLast -= 1
                if iLast < 0 { return BigInt.ZERO }
            } while (thisMagia[iLast] & otherMagia[iLast]) == 0
            let z = Magia(iLast + 1)
            while iLast >= 0 {
                z[iLast] = thisMagia[iLast] & otherMagia[iLast]
                iLast -= 1
            }
            return BigInt.fromNormalizedNonZero(z)
        }
        throwBoundsCheckViolation()
    }

    public func or(_ other: BigInt) -> BigInt {
        let thisNormLen = Int(meta.normLen), otherNormLen = Int(other.meta.normLen)
        let maxLen = max(thisNormLen, otherNormLen)
        if maxLen > 0 {
            let z = Magia(maxLen)
            return BigInt.fromNormalizedNonZero(z, magia_setOr(z, magia, thisNormLen, other.magia, otherNormLen))
        }
        return BigInt.ZERO
    }

    public func xor(_ other: BigInt) -> BigInt {
        let thisNormLen = Int(meta.normLen), otherNormLen = Int(other.meta.normLen)
        let maxLen = max(thisNormLen, otherNormLen)
        let z = Magia(maxLen)
        let zNormLen = magia_setXor(z, magia, thisNormLen, other.magia, otherNormLen)
        if zNormLen > 0 { return BigInt.fromNormalizedNonZero(z, zNormLen) }
        return BigInt.ZERO
    }

    public func ushr(_ bitCount: Int) -> BigInt {
        if bitCount > 0 {
            let newBitLen = magia_normBitLen(magia, Int(meta.normLen)) - bitCount
            if newBitLen <= 0 { return BigInt.ZERO }
            let z = magia_newWithBitLen(newBitLen)
            return BigInt.fromNormalizedNonZero(z, magia_setShiftRight(z, magia, Int(meta.normLen), bitCount))
        }
        if bitCount == 0 { return abs() }
        throwNegBitCount()
    }

    public func shr(_ bitCount: Int) -> BigInt {
        if bitCount > 0 {
            let newBitLen = magia_normBitLen(magia, Int(meta.normLen)) - bitCount
            if newBitLen <= 0 { return meta.isNegative ? BigInt.NEG_ONE : BigInt.ZERO }
            let z = magia_newWithBitLen(newBitLen)
            let zNormLen = magia_setShiftRight(z, magia, Int(meta.normLen), bitCount)
            verify(zNormLen == z.size)
            let needsIncrement = meta.isNegative && magia_testAnyBitInLowerN(magia, Int(meta.normLen), bitCount)
            if !needsIncrement { return BigInt.fromNormalizedNonZero(meta.signFlag, z, zNormLen) }
            var i = 0
            repeat {
                let t = z[i] &+ 1
                z[i] = t
                if t != 0 { return BigInt.fromNormalizedNonZero(meta.signFlag, z, zNormLen) }
                i += 1
            } while i < z.size
            let z1 = Magia(i + 1)
            z1[i] = 1
            return BigInt.fromNormalizedNonZero(meta.signFlag, z1, i + 1)
        }
        if bitCount == 0 { return self }
        throwNegBitCount()
    }

    public func shl(_ bitCount: Int) -> BigInt {
        if isZero() || bitCount == 0 { return self }
        if bitCount > 0 {
            let thisBitLen = magia_normBitLen(magia, Int(meta.normLen))
            let z = magia_newWithBitLen(thisBitLen + bitCount)
            let zNormLen = magia_setShiftLeft(z, magia, Int(meta.normLen), bitCount)
            verify(zNormLen == z.size)
            return BigInt.fromNormalizedNonZero(meta.signFlag, z)
        }
        throwNegBitCount()
    }

    public func withSetBit(_ bitIndex: Int) -> BigInt { withBitOp(bitIndex, true) }
    public func withClearBit(_ bitIndex: Int) -> BigInt { withBitOp(bitIndex, false) }

    private func withBitOp(_ bitIndex: Int, _ isSetOp: Bool) -> BigInt {
        if bitIndex >= 0 {
            if testBit(bitIndex) == isSetOp { return self }
            if isMagnitudePowerOfTwo() && magnitudeBitLen() - 1 == bitIndex {
                verify(!isSetOp)
                return BigInt.ZERO
            }
            let newBitLen = max(bitIndex + 1, magia_normBitLen(magia, Int(meta.normLen)))
            let m = magia_newCopyWithExactBitLen(magia, Int(meta.normLen), newBitLen)
            let wordIndex = bitIndex >> 6
            let isolatedBit: Limb = 1 << (bitIndex & 0x3F)
            let limb = m[wordIndex]
            m[wordIndex] = isSetOp ? (limb | isolatedBit) : (limb & ~isolatedBit)
            return BigInt.fromNonNormalizedManyNonZero(meta.signFlag, m)
        }
        throwBoundsCheckViolation()
    }

    /// A contiguous run of `bitWidth` set bits starting at bit `bitIndex` (i.e.
    /// `((1 << bitWidth) - 1) << bitIndex`).
    public static func withBitMask(_ bitWidth: Int, _ bitIndex: Int = 0) -> BigInt {
        if bitIndex < 0 || bitWidth < 0 { throwInvalidBitLenRange() }
        if bitWidth == 0 { return ZERO }
        if bitWidth == 1 { return withSetBit(bitIndex) }
        // non-zero and more than 1 bit wide
        let bitLen = bitWidth + bitIndex
        let magia = magia_newWithBitLen(bitLen)
        let loIndex = bitIndex >> 6
        magia.fill(Limb.max, loIndex, magia.size)
        let nlz = (magia.size << 6) - bitLen
        magia[magia.size - 1] = Limb.max >> nlz
        let ctz = bitIndex & 0x3F
        magia[loIndex] = magia[loIndex] & (Limb.max << ctz)
        biStat(.BI_CONSTRUCT_BITWISE)
        return fromNormalizedNonZero(magia)
    }

    public func withBitMask(_ bitWidth: Int, _ bitIndex: Int = 0) -> BigInt {
        let myBitLen = magnitudeBitLen()
        if bitIndex < 0 || bitWidth < 0 { throwInvalidBitLenRange() }
        if bitWidth == 0 || bitIndex >= myBitLen { return BigInt.ZERO }
        if bitWidth == 1 && !testBit(bitIndex) { return BigInt.ZERO }
        if bitWidth == 1 { return BigInt.withSetBit(bitIndex) }
        let clampedBitLen = min(bitWidth + bitIndex, myBitLen)
        let ret = magia_newCopyWithExactBitLen(magia, Int(meta.normLen), clampedBitLen)
        let nlz = (ret.size << 6) - clampedBitLen
        ret[ret.size - 1] = ret[ret.size - 1] & (Limb.max >> nlz)
        let loIndex = bitIndex >> 6
        ret.fill(0, 0, loIndex)
        let ctz = bitIndex & 0x3F
        ret[loIndex] = ret[loIndex] & (Limb.max << ctz)
        return BigInt.fromNonNormalizedOrZero(ret)
    }

    // MARK: binary (two's-complement) constructors

    public static func fromTwosComplementBigEndianBytes(_ bytes: [UInt8], _ offset: Int = 0, _ length: Int? = nil) -> BigInt {
        fromBinaryBytes(true, true, bytes, offset, length)
    }

    public static func fromBinaryBytes(_ isTwosComplement: Bool, _ isBigEndian: Bool,
                                _ bytes: [UInt8], _ offset: Int = 0, _ length: Int? = nil) -> BigInt {
        let len = length ?? (bytes.count - offset)
        if offset < 0 || len < 0 || len > bytes.count - offset { throwBoundsCheckViolation() }
        if len > 0 {
            let ibSign = offset - 1 + (isBigEndian ? 1 : len)
            let isNegative = isTwosComplement && (bytes[ibSign] & 0x80) != 0
            let magia = BigIntSerde.fromBinaryBytes(isNegative, isBigEndian, bytes, offset, len)
            if magia !== MAGIA_ZERO {
                biStat(.BI_CONSTRUCT_BINARY_ARRAY)
                return fromNormalizedNonZero(isNegative, magia)
            }
        }
        return ZERO
    }

    public static func fromLittleEndianIntArray(_ sign: Bool, _ a: [Limb], _ len: Int? = nil) -> BigInt {
        let l = len ?? a.count
        if l >= 0 && l <= a.count {
            let tmp = Magia(limbs: ContiguousArray(a[0..<l]))
            let nl = magia_normLen(tmp, l)
            if nl > 0 {
                biStat(.BI_CONSTRUCT_BINARY_ARRAY)
                return fromNormalizedNonZero(sign, tmp.copyOf(nl))
            }
            return ZERO
        }
        throwBoundsCheckViolation()
    }

    // MARK: add / sub impls (engine: mutAdd*/mutSub*/setSub)

    public func addImpl(_ isSub: Bool, _ other: BigIntNumber) -> BigInt {
        biStat(.BI_ADD_SUB_BI)
        let thisSign = meta.signFlag
        let thisNormLen = Int(meta.normLen)
        let otherSign = isSub != other.meta.signFlag       // isSub xor sign
        let otherNormLen = Int(other.meta.normLen)
        if otherNormLen <= 1 {
            // a one-limb operand is a single UInt64; 2+ limbs go the general path
            if otherNormLen == 1 { return addImpl64(otherSign, other.magia[0]) }
            return self                                   // otherNormLen == 0
        }
        if thisNormLen == 0 {
            if let o = other as? BigInt {
                return isSub ? o.negate() : o
            }
            return BigInt.from(other.meta.signFlag != isSub, other)
        }
        if thisSign == otherSign {
            let thisBitLen = magnitudeBitLen()
            let otherBitLen = other.magnitudeBitLen()
            let zBitLen = max(thisBitLen, otherBitLen) + 1
            let z = Magia(magia_limbLenFromBitLen(zBitLen))
            let zNormLen: Int
            if thisNormLen >= otherNormLen {
                magia.copyInto(z, 0, 0, thisNormLen)
                zNormLen = magia_mutAdd(z, thisNormLen, other.magia, otherNormLen)
            } else {
                other.magia.copyInto(z, 0, 0, otherNormLen)
                zNormLen = magia_mutAdd(z, otherNormLen, magia, thisNormLen)
            }
            return BigInt.fromNormalizedNonZero(thisSign, z, zNormLen)
        } else {
            let cmp = magnitudeCompareTo(other)
            if cmp != 0 {
                let sign = (!thisSign) != (cmp > 0)        // !thisSign xor (cmp>0)
                let largeNormLen = cmp > 0 ? thisNormLen : otherNormLen
                let smallNormLen = cmp > 0 ? otherNormLen : thisNormLen
                let largeMagia = cmp > 0 ? magia : other.magia
                let smallMagia = cmp > 0 ? other.magia : magia
                let z = Magia(largeNormLen)
                let zNormLen = magia_setSub(z, largeMagia, largeNormLen, smallMagia, smallNormLen)
                if zNormLen > 0 {
                    return BigInt.fromNormalizedNonZero(sign, z, zNormLen)
                }
            }
        }
        return BigInt.ZERO
    }

    public func addImpl32(_ otherSign: Bool, _ w: Limb) -> BigInt {
        biStat(.BI_ADD_SUB_PRIMITIVE)
        let thisSign = meta.signFlag
        let thisNormLen = Int(meta.normLen)
        if thisNormLen <= magia.size {
            if thisNormLen > 0 && thisSign == otherSign && w != 0 {
                let wBitLen = 64 - Int(w.leadingZeroBitCount)
                let thisBitLen = magia_nonZeroNormBitLen(magia, thisNormLen)
                let newBitLen = max(thisBitLen, wBitLen) + 1
                let z = magia.copyOf(magia_limbLenFromBitLen(newBitLen))
                return BigInt.fromNormalizedNonZero(thisSign, z, magia_mutAddLimb(z, thisNormLen, w))
            }
            if w == 0 { return self }
            if thisNormLen > 1 {
                let z = magia.copyOf()
                let zNormLen = magia_mutSubLimb(z, thisNormLen, w)
                if zNormLen > 0 { return BigInt.fromNormalizedNonZero(thisSign, z, zNormLen) }
                return BigInt.ZERO
            }
            if thisNormLen == 1 {
                let loLimb = magia[0]
                if loLimb > w { return BigInt.from(thisSign, loLimb &- w) }
                if loLimb < w { return BigInt.from(!thisSign, w &- loLimb) }
                return BigInt.ZERO
            }
            return BigInt.from(otherSign, w)               // thisNormLen == 0
        }
        throwBoundsCheckViolation()
    }

    public func addImpl64(_ otherSign: Bool, _ dw: UInt64) -> BigInt {
        biStat(.BI_ADD_SUB_PRIMITIVE)
        let thisSign = meta.signFlag
        let thisNormLen = Int(meta.normLen)
        if thisNormLen <= magia.size {
            if thisNormLen > 0 && thisSign == otherSign && dw != 0 {
                let wBitLen = 64 - Int(dw.leadingZeroBitCount)
                let thisBitLen = magia_nonZeroNormBitLen(magia, thisNormLen)
                let newBitLen = max(thisBitLen, wBitLen) + 1
                let z = magia.copyOf(magia_limbLenFromBitLen(newBitLen))
                return BigInt.fromNormalizedNonZero(thisSign, z, magia_mutAddLimb(z, thisNormLen, dw))
            }
            if dw == 0 { return self }
            if thisNormLen == 0 { return BigInt.from(otherSign, dw) }
            if thisNormLen > 1 {        // ≥2 limbs ⇒ > 2^64 > dw; full multi-limb subtract
                let z = magia.copyOf()
                let zNormLen = magia_mutSubLimb(z, thisNormLen, dw)
                if zNormLen > 0 { return BigInt.fromNormalizedNonZero(thisSign, z, zNormLen) }
                return BigInt.ZERO
            }
            let thisMag = toULongMagnitude()
            if thisMag > dw { return BigInt.from(thisSign, thisMag &- dw) }
            if thisMag < dw { return BigInt.from(!thisSign, dw &- thisMag) }
            return BigInt.ZERO
        }
        throwBoundsCheckViolation()
    }

    // MARK: mul impls (engine: setMulLimb/setMul)

    public func mulImpl32(_ dwSign: Bool, _ w: Limb) -> BigInt {
        biStat(.BI_MUL_PRIMITIVE)
        if !isZero() && w != 0 {
            let sign = meta.signFlag != dwSign
            let thisNormLen = Int(meta.normLen)
            let thisBitLen = magia_normBitLen(magia, thisNormLen)
            let wBitLen = 64 - Int(w.leadingZeroBitCount)
            let z = magia_newWithBitLen(thisBitLen + wBitLen)
            let zNormLen = magia_setMulLimb(z, magia, thisNormLen, w)
            return BigInt.fromNormalizedNonZero(sign, z, zNormLen)
        }
        return BigInt.ZERO
    }

    public func mulImpl64(_ dwSign: Bool, _ dw: UInt64) -> BigInt {
        biStat(.BI_MUL_PRIMITIVE)
        if !isZero() && dw != 0 {
            let sign = meta.signFlag != dwSign
            let thisNormLen = Int(meta.normLen)
            let thisBitLen = magia_normBitLen(magia, thisNormLen)
            let dwBitLen = 64 - Int(dw.leadingZeroBitCount)
            let z = magia_newWithBitLen(thisBitLen + dwBitLen)
            let zNormLen = magia_setMulLimb(z, magia, thisNormLen, dw)
            return BigInt.fromNormalizedNonZero(sign, z, zNormLen)
        }
        return BigInt.ZERO
    }

    public func mulImpl(_ other: BigIntNumber) -> BigInt {
        biStat(.BI_MUL_BI)
        if !isZero() && !other.isZero() {
            let sign = meta.signFlag != other.meta.signFlag
            let thisNormLen = Int(meta.normLen)
            let otherNormLen = Int(other.meta.normLen)
            let thisBitLen = magia_normBitLen(magia, thisNormLen)
            let otherBitLen = magia_normBitLen(other.magia, otherNormLen)
            let z = magia_newWithBitLen(thisBitLen + otherBitLen)
            let zNormLen = magia_setMul(z, magia, thisNormLen, other.magia, otherNormLen)
            return BigInt.fromNormalizedNonZero(sign, z, zNormLen)
        }
        return BigInt.ZERO
    }

    // MARK: div impls (engine: setDivLimb/trySetDivFastPath/setDivKnuth)

    public func divImpl32(_ wSign: Bool, _ w: Limb) -> BigInt {
        biStat(.BI_DIV_PRIMITIVE)
        if w == 0 { throwDivByZero() }
        if !isZero() {
            let thisNormLen = Int(meta.normLen)
            let z = Magia(thisNormLen)
            let zNormLen = magia_setDivLimb(z, magia, thisNormLen, w)
            if zNormLen > 0 { return BigInt.fromNormalizedNonZero(meta.signFlag != wSign, z, zNormLen) }
        }
        return BigInt.ZERO
    }

    public func divImpl64(_ dwSign: Bool, _ dw: UInt64) -> BigInt {
        // At 64-bit limbs a UInt64 divisor is a single limb — identical to divImpl32.
        return divImpl32(dwSign, dw)
    }

    public func divBig(_ other: BigInt) -> BigInt {
        let otherSign = other.meta.signFlag
        let otherNormLen = Int(other.meta.normLen)
        if otherNormLen == 0 { throwDivByZero_BigInt() }
        // a one-limb divisor is a single UInt64; 2+ limbs use the general Knuth path
        if otherNormLen == 1 { return divImpl32(otherSign, other.magia[0]) }
        let thisNormLen = Int(meta.normLen)
        if thisNormLen >= otherNormLen {
            if thisNormLen == otherNormLen {
                let cmp = magia_compare(magia, thisNormLen, other.magia, otherNormLen)
                if cmp < 0 { return BigInt.ZERO }
                if cmp == 0 { return BigInt.ONE }
            }
            let z = Magia(thisNormLen - otherNormLen + 1)
            let zNormLen = magia_setDivKnuth(z, magia, thisNormLen, nil, other.magia, otherNormLen, nil)
            if zNormLen > 0 { return BigInt.fromNormalizedNonZero(meta.signFlag != otherSign, z, zNormLen) }
        }
        return BigInt.ZERO
    }

    // MARK: rem / mod impls (engine: calcRemLimb/setSub/setRem)

    public func remModImpl64(_ dw: UInt64, _ isMod: Bool) -> BigInt {
        if dw == 0 { throwDivByZero() }
        if !isZero() {
            let rem = magia_calcRemLimb(magia, Int(meta.normLen), dw)
            if rem != 0 {
                if meta.isNegative && isMod { return BigInt.from(dw &- rem) }
                return BigInt.from(meta.isNegative, rem)
            }
        }
        return BigInt.ZERO
    }

    public func remModImpl(_ other: BigIntNumber, _ isMod: Bool) -> BigInt {
        let xNormLen = Int(meta.normLen)
        let yNormLen = Int(other.meta.normLen)
        if yNormLen <= 1 { return remModImpl64(other.toULongMagnitude(), isMod) }
        if xNormLen == 0 { return BigInt.ZERO }
        let x = magia
        let y = other.magia
        let applyModRingNormalization = isNegative() && isMod
        let z: Magia
        var zNormLen = 0
        if magia_normBitLen(x, xNormLen) <= magia_normBitLen(y, yNormLen) {
            let cmp = magia_compare(x, xNormLen, y, yNormLen)
            if cmp < 0 && !applyModRingNormalization { return self }
            if cmp < 0 {
                z = Magia(yNormLen)
                zNormLen = magia_setSub(z, y, yNormLen, x, xNormLen)
                return BigInt.fromNormalizedNonZero(z, zNormLen)
            }
            if cmp == 0 { return BigInt.ZERO }
            z = Magia(xNormLen)                            // cmp > 0
            zNormLen = magia_setSub(z, x, xNormLen, y, yNormLen)
        } else {
            z = Magia(yNormLen)
            zNormLen = magia_setRem(z, magia, xNormLen, other.magia, yNormLen)
            if zNormLen == 0 { return BigInt.ZERO }
        }
        if applyModRingNormalization {
            zNormLen = magia_setSub(z, y, yNormLen, z, zNormLen)
        }
        return BigInt.fromNormalizedNonZero(meta.signFlag && !isMod, z, zNormLen)
    }

    // MARK: mod (always non-negative result; rejects negative divisor)

    public func mod(_ n: Int32) -> BigInt {
        if n < 0 { throwModNegDivisor() }
        return remModImpl64(UInt64(UInt32(n.magnitude)), true)
    }
    public func mod(_ w: UInt32) -> BigInt { remModImpl64(UInt64(w), true) }
    public func mod(_ l: Int64) -> BigInt {
        if l < 0 { throwModNegDivisor() }
        return remModImpl64(l.magnitude, true)
    }
    public func mod(_ dw: UInt64) -> BigInt { remModImpl64(dw, true) }
    public func mod(_ other: BigIntNumber) -> BigInt { remModImpl(other, true) }

    // MARK: operators

    public static prefix func - (x: BigInt) -> BigInt { x.negate() }
    public static prefix func + (x: BigInt) -> BigInt { x }

    public static func + (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.addImpl(false, rhs) }
    public static func - (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.addImpl(true, rhs) }
    public static func * (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.mulImpl(rhs) }
    public static func / (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.divBig(rhs) }
    public static func % (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.remModImpl(rhs, false) }

    public static func + (lhs: BigInt, n: Int32) -> BigInt { lhs.addImpl32(n < 0, UInt64(n.magnitude)) }
    public static func + (lhs: BigInt, w: UInt32) -> BigInt { lhs.addImpl32(false, UInt64(w)) }
    public static func + (lhs: BigInt, l: Int64) -> BigInt { lhs.addImpl64(l < 0, l.magnitude) }
    public static func + (lhs: BigInt, dw: UInt64) -> BigInt { lhs.addImpl64(false, dw) }

    public static func - (lhs: BigInt, n: Int32) -> BigInt { lhs.addImpl32(n >= 0, UInt64(n.magnitude)) }
    public static func - (lhs: BigInt, w: UInt32) -> BigInt { lhs.addImpl32(true, UInt64(w)) }
    public static func - (lhs: BigInt, l: Int64) -> BigInt { lhs.addImpl64(l >= 0, l.magnitude) }
    public static func - (lhs: BigInt, dw: UInt64) -> BigInt { lhs.addImpl64(true, dw) }

    public static func * (lhs: BigInt, n: Int32) -> BigInt { lhs.mulImpl32(n < 0, UInt64(n.magnitude)) }
    public static func * (lhs: BigInt, w: UInt32) -> BigInt { lhs.mulImpl32(false, UInt64(w)) }
    public static func * (lhs: BigInt, l: Int64) -> BigInt { lhs.mulImpl64(l < 0, l.magnitude) }
    public static func * (lhs: BigInt, dw: UInt64) -> BigInt { lhs.mulImpl64(false, dw) }

    public static func / (lhs: BigInt, n: Int32) -> BigInt { lhs.divImpl32(n < 0, UInt64(n.magnitude)) }
    public static func / (lhs: BigInt, w: UInt32) -> BigInt { lhs.divImpl32(false, UInt64(w)) }
    public static func / (lhs: BigInt, l: Int64) -> BigInt { lhs.divImpl64(l < 0, l.magnitude) }
    public static func / (lhs: BigInt, dw: UInt64) -> BigInt { lhs.divImpl64(false, dw) }

    public static func % (lhs: BigInt, n: Int32) -> BigInt { lhs.remModImpl64(UInt64(UInt32(n.magnitude)), false) }
    public static func % (lhs: BigInt, w: UInt32) -> BigInt { lhs.remModImpl64(UInt64(w), false) }
    public static func % (lhs: BigInt, l: Int64) -> BigInt { lhs.remModImpl64(l.magnitude, false) }
    public static func % (lhs: BigInt, dw: UInt64) -> BigInt { lhs.remModImpl64(dw, false) }
}

// Hashable: consistent with `==` (numeric value). Mirrors Kotlin's
// `31 * isNegative.hashCode() + magnitudeHashCode()` (JVM Boolean.hashCode =
// 1231/1237) so the hash is bit-identical across ports.
extension BigInt: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(31 &* Int32(meta.isNegative ? 1231 : 1237) &+ magnitudeHashCode())
    }
}

// ExpressibleByIntegerLiteral: allow `let x: BigInt = 5`. Literals are limited to
// the platform `Int` range (64-bit here); larger magnitudes use from(String).
extension BigInt: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = BigInt.from(Int64(value))
    }
}

// AdditiveArithmetic: + / - and Equatable are already provided; `zero` aliases the
// port-faithful `ZERO` constant (kept uppercase to mirror bigint-kotlin).
extension BigInt: AdditiveArithmetic {
    public static var zero: BigInt { ZERO }
}

// Numeric: refines AdditiveArithmetic + ExpressibleByIntegerLiteral (both done);
// `*` / `*=` are already provided. Magnitude is BigInt itself (no separate unsigned
// type). `init?(exactly:)` never fails for arbitrary precision — every BinaryInteger
// is representable; wide sources rebuild from the magnitude's little-endian words
// (UInt == Limb on the 64-bit-only target).
extension BigInt: Numeric {
    public typealias Magnitude = BigInt
    public var magnitude: BigInt { absoluteValue }

    public init?<T: BinaryInteger>(exactly source: T) {
        if let i = Int64(exactly: source) { self = BigInt.from(i); return }
        if let u = UInt64(exactly: source) { self = BigInt.from(u); return }
        let limbs = source.magnitude.words.map { Limb($0) }
        self = BigInt.fromLittleEndianIntArray(source < 0, Array(limbs))
    }

    public static func *= (lhs: inout BigInt, rhs: BigInt) { lhs = lhs * rhs }
}

// ============================================================================
// DEFERRED from BigInt.kt: from(CharSequence/CharArray/ByteArray) parse
// overloads (minor; String done). from(Double)/fromULongShiftLeft, the random
// constructors, and static withBitMask are now ported (Phase 5 prerequisites).
// ============================================================================
