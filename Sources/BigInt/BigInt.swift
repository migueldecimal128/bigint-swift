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

struct BigInt: BigIntNumber, Comparable {
    let meta: Meta
    let magia: Magia

    private init(_ meta: Meta, _ magia: Magia) {
        self.meta = meta
        self.magia = magia
    }

    // MARK: canonical constants
    // `nonisolated(unsafe)`: immutable shared values over a never-mutated Magia.

    nonisolated(unsafe) static let ZERO = BigInt(Meta(0), MAGIA_ZERO)
    nonisolated(unsafe) static let ONE = BigInt(Meta(1), MAGIA_ONE)
    nonisolated(unsafe) static let TWO = BigInt(Meta(1), Magia(limbs: [2]))
    nonisolated(unsafe) static let NEG_ONE = BigInt(Meta(signBit: 1, normLen: 1), MAGIA_ONE)
    nonisolated(unsafe) static let TEN = BigInt(Meta(1), Magia(limbs: [10]))

    // MARK: internal normalized/non-normalized factories

    static func fromNormalizedNonZero(_ magia: Magia) -> BigInt {
        fromNormalizedNonZero(false, magia)
    }
    static func fromNormalizedNonZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        verify(magia.size > 0)
        verify(magia[magia.size - 1] != 0)
        return BigInt(Meta(signFlag: sign, normLen: Int32(magia.size)), magia)
    }
    static func fromNormalizedNonZero(_ magia: Magia, _ normLen: Int) -> BigInt {
        verify(magia.size > 0 && _validateNormLenAndInjectPoison(magia, normLen))
        return BigInt(Meta(Int32(normLen)), magia)
    }
    static func fromNormalizedNonZero(_ sign: Bool, _ magia: Magia, _ normLen: Int) -> BigInt {
        verify(magia.size > 0 && _validateNormLenAndInjectPoison(magia, normLen))
        return BigInt(Meta(signFlag: sign, normLen: Int32(normLen)), magia)
    }

    static func fromNormalizedOrZero(_ magia: Magia) -> BigInt {
        fromNormalizedOrZero(false, magia)
    }
    static func fromNormalizedOrZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        if magia.size == 0 {
            verify(magia === MAGIA_ZERO)
            return ZERO
        }
        verify(magia.size > 0)
        verify(magia[magia.size - 1] != 0)
        return BigInt(Meta(signFlag: sign, normLen: Int32(magia.size)), magia)
    }

    static func fromNonNormalizedManyNonZero(_ magia: Magia) -> BigInt {
        fromNonNormalizedManyNonZero(false, magia)
    }
    static func fromNonNormalizedManyNonZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        let nl = magia_normLen(magia)
        verify(nl > 0)
        verify(_validateNormLenAndInjectPoison(magia, nl))
        return BigInt(Meta(signFlag: sign, normLen: Int32(nl)), magia)
    }

    static func fromNonNormalized1NonZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        let nl = magia.size - (magia[magia.size - 1] != 0 ? 0 : 1)
        verify(nl > 0)
        verify(_validateNormLenAndInjectPoison(magia, nl))
        return BigInt(Meta(signFlag: sign, normLen: Int32(nl)), magia)
    }

    static func fromNonNormalizedOrZero(_ magia: Magia) -> BigInt {
        fromNonNormalizedOrZero(false, magia)
    }
    static func fromNonNormalizedOrZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        let nl = magia_normLen(magia)
        if nl > 0 {
            verify(_validateNormLenAndInjectPoison(magia, nl))
            return BigInt(Meta(signFlag: sign, normLen: Int32(nl)), magia)
        }
        return ZERO
    }

    // MARK: primitive factories

    static func from(_ n: Int32) -> BigInt {
        if n == 0 { return ZERO }
        biStat(.BI_CONSTRUCT_32)
        if n > 0 {
            return BigInt(Meta(signFlag: false, normLen: 1), Magia(limbs: [Limb(bitPattern: n)]))
        }
        return BigInt(Meta(signFlag: true, normLen: 1), Magia(limbs: [Limb(bitPattern: 0 &- n)]))
    }

    static func from(_ w: UInt32) -> BigInt {
        if w != 0 {
            biStat(.BI_CONSTRUCT_32)
            return BigInt(Meta(signFlag: false, normLen: 1), Magia(limbs: [w]))
        }
        return ZERO
    }

    static func from(_ sign: Bool, _ w: UInt32) -> BigInt {
        if w != 0 {
            biStat(.BI_CONSTRUCT_32)
            return BigInt(Meta(signFlag: sign, normLen: 1), Magia(limbs: [w]))
        }
        return ZERO
    }

    static func from(_ l: Int64) -> BigInt { from(l < 0, l.magnitude) }
    static func from(_ dw: UInt64) -> BigInt { from(false, dw) }

    static func from(_ sign: Bool, _ dwMagnitude: UInt64) -> BigInt {
        if dwMagnitude != 0 {
            biStat(.BI_CONSTRUCT_64)
            if (dwMagnitude >> 32) == 0 {
                return BigInt(Meta(signFlag: sign, normLen: 1), Magia(limbs: [dwMagnitude.toLimb()]))
            }
            return BigInt(Meta(signFlag: sign, normLen: 2),
                          Magia(limbs: [dwMagnitude.toLimb(), (dwMagnitude >> 32).toLimb()]))
        }
        return ZERO
    }

    /// Copy constructor from any BigIntNumber (immutable snapshot).
    static func from(_ other: BigIntNumber) -> BigInt {
        biStat(.BI_CONSTRUCT_COPY)
        if !other.meta.isZero {
            return BigInt(other.meta, other.magia.copyOf(Int(other.meta.normLen)))
        }
        return ZERO
    }

    static func from(_ sign: Bool, _ biMagnitude: BigIntNumber) -> BigInt {
        biStat(.BI_CONSTRUCT_COPY)
        return BigInt(Meta(signFlag: sign, normLen: biMagnitude.meta.normLen),
                      biMagnitude.magia.copyOf(Int(biMagnitude.meta.normLen)))
    }

    // MARK: text factories (Phase 3 BigIntParsePrint)

    static func from(_ str: String) -> BigInt { from(StringLatin1Iterator(str)) }
    static func from(_ str: String, _ off: Int, _ len: Int) -> BigInt {
        from(StringLatin1Iterator(str, off, len))
    }
    private static func from(_ src: Latin1Iterator) -> BigInt {
        biStat(.BI_CONSTRUCT_TEXT)
        return fromNonNormalizedOrZero(src.peek() == "-", BigIntParsePrint.from(src))
    }

    static func fromHex(_ str: String) -> BigInt { fromHex(StringLatin1Iterator(str)) }
    private static func fromHex(_ src: Latin1Iterator) -> BigInt {
        biStat(.BI_CONSTRUCT_TEXT)
        return fromNormalizedOrZero(src.peek() == "-", BigIntParsePrint.fromHex(src))
    }

    // MARK: BigIntNumber

    func toBigInt() -> BigInt { self }   // already an immutable snapshot

    // MARK: Comparable / Equatable (numeric value semantics)

    static func < (lhs: BigInt, rhs: BigInt) -> Bool { lhs.compareTo(rhs) < 0 }
    static func == (lhs: BigInt, rhs: BigInt) -> Bool { lhs.compareTo(rhs) == 0 }

    // MARK: sign

    func abs() -> BigInt { isNegative() ? BigInt(meta.abs(), magia) : self }
    var absoluteValue: BigInt { abs() }

    func negate() -> BigInt {
        if !isZero() {
            biStat(.BI_NEGATE)
            return BigInt(meta.negate(), magia)
        }
        return BigInt.ZERO
    }

    func withSign(_ sign: Bool) -> BigInt { isNegative() == sign ? self : negate() }
    func withSignOf(_ other: BigIntNumber) -> BigInt {
        isNegative() == other.isNegative() ? self : negate()
    }

    // MARK: add / sub impls (engine: mutAdd*/mutSub*/setSub)

    func addImpl(_ isSub: Bool, _ other: BigIntNumber) -> BigInt {
        biStat(.BI_ADD_SUB_BI)
        let thisSign = meta.signFlag
        let thisNormLen = Int(meta.normLen)
        let otherSign = isSub != other.meta.signFlag       // isSub xor sign
        let otherNormLen = Int(other.meta.normLen)
        if otherNormLen <= 2 {
            switch otherNormLen {
            case 2: return addImpl64(otherSign, magia_toRawULongExact(other.magia))
            case 1: return addImpl32(otherSign, other.magia[0])
            default: return self
            }
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

    func addImpl32(_ otherSign: Bool, _ w: Limb) -> BigInt {
        biStat(.BI_ADD_SUB_PRIMITIVE)
        let thisSign = meta.signFlag
        let thisNormLen = Int(meta.normLen)
        if thisNormLen <= magia.size {
            if thisNormLen > 0 && thisSign == otherSign && w != 0 {
                let wBitLen = 32 - Int(w.leadingZeroBitCount)
                let thisBitLen = magia_nonZeroNormBitLen(magia, thisNormLen)
                let newBitLen = max(thisBitLen, wBitLen) + 1
                let z = magia.copyOf(magia_limbLenFromBitLen(newBitLen))
                return BigInt.fromNormalizedNonZero(thisSign, z, magia_mutAdd32(z, thisNormLen, w))
            }
            if w == 0 { return self }
            if thisNormLen > 1 {
                let z = magia.copyOf()
                let zNormLen = magia_mutSub32(z, thisNormLen, w)
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

    func addImpl64(_ otherSign: Bool, _ dw: UInt64) -> BigInt {
        biStat(.BI_ADD_SUB_PRIMITIVE)
        let thisSign = meta.signFlag
        let thisNormLen = Int(meta.normLen)
        if thisNormLen <= magia.size {
            if thisNormLen > 0 && thisSign == otherSign && dw != 0 {
                let wBitLen = 64 - Int(dw.leadingZeroBitCount)
                let thisBitLen = magia_nonZeroNormBitLen(magia, thisNormLen)
                let newBitLen = max(thisBitLen, wBitLen) + 1
                let z = magia.copyOf(magia_limbLenFromBitLen(newBitLen))
                return BigInt.fromNormalizedNonZero(thisSign, z, magia_mutAdd64(z, thisNormLen, dw))
            }
            if dw == 0 { return self }
            if thisNormLen == 0 { return BigInt.from(otherSign, dw) }
            if thisNormLen > 2 {
                let z = magia.copyOf()
                let zNormLen = magia_mutSub64(z, thisNormLen, dw)
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

    // MARK: mul impls (engine: setMul32/64/setMul)

    func mulImpl32(_ dwSign: Bool, _ w: Limb) -> BigInt {
        biStat(.BI_MUL_PRIMITIVE)
        if !isZero() && w != 0 {
            let sign = meta.signFlag != dwSign
            let thisNormLen = Int(meta.normLen)
            let thisBitLen = magia_normBitLen(magia, thisNormLen)
            let wBitLen = 32 - Int(w.leadingZeroBitCount)
            let z = magia_newWithBitLen(thisBitLen + wBitLen)
            let zNormLen = magia_setMul32(z, magia, thisNormLen, w)
            return BigInt.fromNormalizedNonZero(sign, z, zNormLen)
        }
        return BigInt.ZERO
    }

    func mulImpl64(_ dwSign: Bool, _ dw: UInt64) -> BigInt {
        biStat(.BI_MUL_PRIMITIVE)
        if !isZero() && dw != 0 {
            let sign = meta.signFlag != dwSign
            let thisNormLen = Int(meta.normLen)
            let thisBitLen = magia_normBitLen(magia, thisNormLen)
            let dwBitLen = 64 - Int(dw.leadingZeroBitCount)
            let z = magia_newWithBitLen(thisBitLen + dwBitLen)
            let zNormLen = magia_setMul64(z, magia, thisNormLen, dw)
            return BigInt.fromNormalizedNonZero(sign, z, zNormLen)
        }
        return BigInt.ZERO
    }

    func mulImpl(_ other: BigIntNumber) -> BigInt {
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

    // MARK: div impls (engine: setDiv32/trySetDivFastPath64/setDivKnuth64/setDivKnuth)

    func divImpl32(_ wSign: Bool, _ w: Limb) -> BigInt {
        biStat(.BI_DIV_PRIMITIVE)
        if w == 0 { throwDivByZero() }
        if !isZero() {
            let thisNormLen = Int(meta.normLen)
            let z = Magia(thisNormLen)
            let zNormLen = magia_setDiv32(z, magia, thisNormLen, w)
            if zNormLen > 0 { return BigInt.fromNormalizedNonZero(meta.signFlag != wSign, z, zNormLen) }
        }
        return BigInt.ZERO
    }

    func divImpl64(_ dwSign: Bool, _ dw: UInt64) -> BigInt {
        if (dw >> 32) == 0 { return divImpl32(dwSign, Limb(truncatingIfNeeded: dw)) }
        biStat(.BI_DIV_PRIMITIVE)
        let thisNormLen = Int(meta.normLen)
        if thisNormLen < 2 { return BigInt.ZERO }
        let sign = meta.signFlag != dwSign
        let z = Magia(thisNormLen - 1)
        let tryFast64 = magia_trySetDivFastPath64(z, magia, thisNormLen, dw)
        let zNormLen: Int
        if tryFast64 > 0 { zNormLen = tryFast64 }
        else if tryFast64 == 0 { return BigInt.ZERO }
        else { zNormLen = magia_setDivKnuth64(z, magia, thisNormLen, nil, dw) }
        return BigInt.fromNormalizedNonZero(sign, z, zNormLen)
    }

    func divBig(_ other: BigInt) -> BigInt {
        let otherSign = other.meta.signFlag
        let otherNormLen = Int(other.meta.normLen)
        if otherNormLen <= 2 {
            if otherNormLen == 1 { return divImpl32(otherSign, other.magia[0]) }
            if otherNormLen == 2 {
                let divisor = (UInt64(other.magia[1]) << 32) | UInt64(other.magia[0])
                return divImpl64(otherSign, divisor)
            }
            throwDivByZero_BigInt()
        }
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

    // MARK: rem / mod impls (engine: calcRem64/setSub/setRem)

    func remModImpl64(_ dw: UInt64, _ isMod: Bool) -> BigInt {
        if dw == 0 { throwDivByZero() }
        if !isZero() {
            let rem = magia_calcRem64(magia, Int(meta.normLen), nil, dw)
            if rem != 0 {
                if meta.isNegative && isMod { return BigInt.from(dw &- rem) }
                return BigInt.from(meta.isNegative, rem)
            }
        }
        return BigInt.ZERO
    }

    func remModImpl(_ other: BigIntNumber, _ isMod: Bool) -> BigInt {
        let xNormLen = Int(meta.normLen)
        let yNormLen = Int(other.meta.normLen)
        if yNormLen <= 2 { return remModImpl64(other.toULongMagnitude(), isMod) }
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

    func mod(_ n: Int32) -> BigInt {
        if n < 0 { throwModNegDivisor() }
        return remModImpl64(UInt64(UInt32(n.magnitude)), true)
    }
    func mod(_ w: UInt32) -> BigInt { remModImpl64(UInt64(w), true) }
    func mod(_ l: Int64) -> BigInt {
        if l < 0 { throwModNegDivisor() }
        return remModImpl64(l.magnitude, true)
    }
    func mod(_ dw: UInt64) -> BigInt { remModImpl64(dw, true) }
    func mod(_ other: BigIntNumber) -> BigInt { remModImpl(other, true) }

    // MARK: operators

    static prefix func - (x: BigInt) -> BigInt { x.negate() }
    static prefix func + (x: BigInt) -> BigInt { x }

    static func + (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.addImpl(false, rhs) }
    static func - (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.addImpl(true, rhs) }
    static func * (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.mulImpl(rhs) }
    static func / (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.divBig(rhs) }
    static func % (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.remModImpl(rhs, false) }

    static func + (lhs: BigInt, n: Int32) -> BigInt { lhs.addImpl32(n < 0, UInt32(n.magnitude)) }
    static func + (lhs: BigInt, w: UInt32) -> BigInt { lhs.addImpl32(false, w) }
    static func + (lhs: BigInt, l: Int64) -> BigInt { lhs.addImpl64(l < 0, l.magnitude) }
    static func + (lhs: BigInt, dw: UInt64) -> BigInt { lhs.addImpl64(false, dw) }

    static func - (lhs: BigInt, n: Int32) -> BigInt { lhs.addImpl32(n >= 0, UInt32(n.magnitude)) }
    static func - (lhs: BigInt, w: UInt32) -> BigInt { lhs.addImpl32(true, w) }
    static func - (lhs: BigInt, l: Int64) -> BigInt { lhs.addImpl64(l >= 0, l.magnitude) }
    static func - (lhs: BigInt, dw: UInt64) -> BigInt { lhs.addImpl64(true, dw) }

    static func * (lhs: BigInt, n: Int32) -> BigInt { lhs.mulImpl32(n < 0, UInt32(n.magnitude)) }
    static func * (lhs: BigInt, w: UInt32) -> BigInt { lhs.mulImpl32(false, w) }
    static func * (lhs: BigInt, l: Int64) -> BigInt { lhs.mulImpl64(l < 0, l.magnitude) }
    static func * (lhs: BigInt, dw: UInt64) -> BigInt { lhs.mulImpl64(false, dw) }

    static func / (lhs: BigInt, n: Int32) -> BigInt { lhs.divImpl32(n < 0, UInt32(n.magnitude)) }
    static func / (lhs: BigInt, w: UInt32) -> BigInt { lhs.divImpl32(false, w) }
    static func / (lhs: BigInt, l: Int64) -> BigInt { lhs.divImpl64(l < 0, l.magnitude) }
    static func / (lhs: BigInt, dw: UInt64) -> BigInt { lhs.divImpl64(false, dw) }

    static func % (lhs: BigInt, n: Int32) -> BigInt { lhs.remModImpl64(UInt64(UInt32(n.magnitude)), false) }
    static func % (lhs: BigInt, w: UInt32) -> BigInt { lhs.remModImpl64(UInt64(w), false) }
    static func % (lhs: BigInt, l: Int64) -> BigInt { lhs.remModImpl64(l.magnitude, false) }
    static func % (lhs: BigInt, dw: UInt64) -> BigInt { lhs.remModImpl64(dw, false) }
}

// ============================================================================
// DEFERRED from BigInt.kt (next pushes):
//   - pow / gcd / square           → Phase 3 BigIntAlgorithms
//   - from(Double) / fromULongShiftLeft
//   - from(String/CharSequence/CharArray/ByteArray)  (Phase 3 ParsePrint +
//     Latin1Iterator); random; binary-array constructors
//   - bit ops (and/or/xor/shl/shr/setBit), public square
//   - Equatable/Hashable per Kotlin's exact equals/hashCode (verify vs source)
// ============================================================================
