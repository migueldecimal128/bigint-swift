// SPDX-License-Identifier: MIT
//
// Port of BigIntNumber.kt — the read-only API shared by `BigInt` (immutable
// value struct) and `MutableBigInt` (mutable class).
//
// Kotlin models this as a `sealed class` base; Swift can't share a class
// hierarchy between a struct and a class, so it becomes a `protocol` (requiring
// `meta`/`magia`) plus a protocol extension carrying the shared implementation
// once (work order §6.1; user-approved). No arithmetic or mutation here.
//
// Type mapping for the public conversion surface:
//   Kotlin Int → Int32,  UInt → UInt32 (Limb),  Long → Int64,  ULong → UInt64.

protocol BigIntNumber {
    var meta: Meta { get }
    var magia: Magia { get }
    func currentLimbCapacityHint() -> Int
    func toBigInt() -> BigInt
}


extension BigIntNumber {
    func currentLimbCapacityHint() -> Int { 0 }

    // MARK: predicates

    func isZero() -> Bool { meta.normLen == 0 }
    func isNotZero() -> Bool { meta.normLen > 0 }
    func isOne() -> Bool { meta._meta == 1 && magia[0] == 1 }
    func isNegative() -> Bool { meta.isNegative }
    func isPositive() -> Bool { meta.isPositive }
    func signum() -> Int32 { meta.signum }
    func isEven() -> Bool { isZero() || (magia[0] & 1) == 0 }
    func isOdd() -> Bool { isNotZero() && (magia[0] & 1) != 0 }
    func isMagnitudePowerOfTwo() -> Bool { magia_isPowerOfTwo(magia, Int(meta.normLen)) }

    func isNormalized() -> Bool {
        magia_isNormalized(magia, Int(meta.normLen)) && meta._meta != Int32.min
    }
    func isSuperNormalized() -> Bool {
        isNormalized() && Int(meta.normLen) == magia.size
    }

    // MARK: fits

    func fitsInt() -> Bool {
        if meta.isZero { return true }
        if meta.normLen > 1 { return false }
        let limb = magia[0]
        if limb < 0x8000_0000 { return true }                  // Kotlin: limb >= 0
        return meta.isNegative && limb == 0x8000_0000          // Int.MIN_VALUE
    }
    func fitsUInt() -> Bool { meta.isPositive && meta.normLen <= 1 }
    func fitsLong() -> Bool {
        if meta.normLen > 2 { return false }
        if meta.normLen < 2 { return true }
        if magia[1] < 0x8000_0000 { return true }              // Kotlin: magia[1] >= 0
        return meta.isNegative && magia[1] == 0x8000_0000 && magia[0] == 0
    }
    func fitsULong() -> Bool { meta.isPositive && meta.normLen <= 2 }

    // MARK: to-primitive (low bits, wrapping — matches Kotlin .toInt()/.toLong())

    func toInt() -> Int32 {
        isZero() ? 0 : (Int32(bitPattern: magia[0]) ^ meta.signMask) &- meta.signMask
    }
    func toIntExact() -> Int32 {
        if fitsInt() { return toInt() }
        fatalError("BigInt out of Int range")
    }
    func toIntClamped() -> Int32 {
        if magnitudeBitLen() <= 31 { return toInt() }
        return meta.isPositive ? Int32.max : Int32.min
    }

    func toUInt() -> UInt32 { UInt32(bitPattern: toInt()) }
    func toUIntExact() -> UInt32 {
        if fitsUInt() { return toUInt() }
        fatalError("out of UInt range")
    }
    func toUIntClamped() -> UInt32 {
        if meta.isNegative { return 0 }
        if magnitudeBitLen() <= 32 { return toUInt() }
        return UInt32.max
    }

    func toLong() -> Int64 {
        let l: Int64
        switch meta.normLen {
        case 0: l = 0
        case 1: l = Int64(magia[0])
        default: l = Int64(bitPattern: (UInt64(magia[1]) << 32) | UInt64(magia[0]))
        }
        let mask = Int64(meta.signMask)
        return (l ^ mask) &- mask
    }
    func toLongExact() -> Int64 {
        if fitsLong() { return toLong() }
        fatalError("out of Long range")
    }
    func toLongClamped() -> Int64 {
        if magnitudeBitLen() <= 63 { return toLong() }
        return meta.isPositive ? Int64.max : Int64.min
    }

    func toULong() -> UInt64 { UInt64(bitPattern: toLong()) }
    func toULongExact() -> UInt64 {
        if fitsULong() { return toULong() }
        fatalError("out of ULong range")
    }
    func toULongClamped() -> UInt64 {
        if meta.isNegative { return 0 }
        if magnitudeBitLen() <= 64 { return toULong() }
        return UInt64.max
    }

    func toUIntMagnitude() -> UInt32 { meta.normLen == 0 ? 0 : magia[0] }
    func toULongMagnitude() -> UInt64 {
        switch meta.normLen {
        case 0: return 0
        case 1: return UInt64(magia[0])
        default: return (UInt64(magia[1]) << 32) | UInt64(magia[0])
        }
    }

    func modInt(_ n: Int32) -> Int32 {
        precondition(n > 0, "modulus must be > 0")
        precondition(!isNegative())
        return Int32(bitPattern: magia_calcRem32(magia, Int(meta.normLen), UInt32(bitPattern: n)))
    }

    func extractULongAtBitIndex(_ bitIndex: Int) -> UInt64 {
        magia_extractULongAtBitIndex(magia, Int(meta.normLen), bitIndex)
    }

    // MARK: bit-length / counts

    func magnitudeBitLen() -> Int { magia_normBitLen(magia, Int(meta.normLen)) }
    func bitLengthBigIntegerStyle() -> Int {
        magia_bitLengthBigIntegerStyle(meta.signFlag, magia, Int(meta.normLen))
    }
    func magnitudeIntArrayLen() -> Int { (magnitudeBitLen() + 31) >> 5 }
    func magnitudeLongArrayLen() -> Int { (magnitudeBitLen() + 63) >> 6 }

    func calcTwosComplementByteLength() -> Int {
        if meta.isZero { return 1 }
        let bitLen2sComplement = bitLengthBigIntegerStyle() + 1
        return (bitLen2sComplement + 7) >> 3
    }

    func countTrailingZeroBits() -> Int { magia_ctz(magia, Int(meta.normLen)) }

    func magnitudeCountOneBits() -> Int {
        let n = Int(meta.normLen)
        if n >= 0 && n <= magia.size {
            var popCount = 0
            for i in 0..<n { popCount += magia[i].nonzeroBitCount }
            return popCount
        }
        fatalError()
    }

    func testBit(_ bitIndex: Int) -> Bool { magia_testBit(magia, Int(meta.normLen), bitIndex) }

    // MARK: compare (value)

    func compareTo(_ other: BigIntNumber) -> Int {
        if meta.signMask != other.meta.signMask { return Int(meta.signMask | 1) }
        let cmp = magia_compare(magia, Int(meta.normLen), other.magia, Int(other.meta.normLen))
        return Int(meta.negateIfNegative(Int32(cmp)))
    }
    func compareTo(_ n: Int32) -> Int { compareToHelper(n < 0, UInt64(n.magnitude)) }
    func compareTo(_ w: UInt32) -> Int { compareToHelper(false, UInt64(w)) }
    func compareTo(_ l: Int64) -> Int { compareToHelper(l < 0, l.magnitude) }
    func compareTo(_ dw: UInt64) -> Int { compareToHelper(false, dw) }

    func compareToHelper(_ dwSign: Bool, _ dwMag: UInt64) -> Int {
        if meta.isNegative != dwSign { return Int(meta.signMask | 1) }
        let cmp = magia_compare(magia, Int(meta.normLen), dwMag)
        return dwSign ? -cmp : cmp
    }

    // MARK: compare (magnitude)

    func magnitudeCompareTo(_ n: Int32) -> Int { magia_compare(magia, Int(meta.normLen), UInt64(n.magnitude)) }
    func magnitudeCompareTo(_ w: UInt32) -> Int { magia_compare(magia, Int(meta.normLen), UInt64(w)) }
    func magnitudeCompareTo(_ l: Int64) -> Int { magia_compare(magia, Int(meta.normLen), l.magnitude) }
    func magnitudeCompareTo(_ dw: UInt64) -> Int { magia_compare(magia, Int(meta.normLen), dw) }
    func magnitudeCompareTo(_ a: Magia, _ length: Int) -> Int {
        magia_compare(magia, Int(meta.normLen), a, magia_normLen(a, length))
    }
    func magnitudeCompareTo(_ a: Magia) -> Int { magnitudeCompareTo(a, a.size) }
    func magnitudeCompareTo(_ other: BigIntNumber) -> Int {
        magia_compare(magia, Int(meta.normLen), other.magia, Int(other.meta.normLen))
    }
    func magnitudeCompareTo(_ otherMeta: Meta, _ otherMagia: Magia) -> Int {
        magia_compare(magia, Int(meta.normLen), otherMagia, Int(otherMeta.normLen))
    }

    // MARK: EQ / NE (value)

    func EQ(_ other: BigIntNumber) -> Bool { compareTo(other) == 0 }
    func EQ(_ n: Int32) -> Bool { compareTo(n) == 0 }
    func EQ(_ w: UInt32) -> Bool { compareTo(w) == 0 }
    func EQ(_ l: Int64) -> Bool { compareTo(l) == 0 }
    func EQ(_ dw: UInt64) -> Bool { compareTo(dw) == 0 }

    func NE(_ other: BigIntNumber) -> Bool { !EQ(other) }
    func NE(_ n: Int32) -> Bool { !EQ(n) }
    func NE(_ w: UInt32) -> Bool { !EQ(w) }
    func NE(_ l: Int64) -> Bool { !EQ(l) }
    func NE(_ dw: UInt64) -> Bool { !EQ(dw) }

    // MARK: magEQ / magNE (magnitude)

    func magEQ(_ other: BigIntNumber) -> Bool { magnitudeCompareTo(other) == 0 }
    func magEQ(_ n: Int32) -> Bool { magnitudeCompareTo(n) == 0 }
    func magEQ(_ w: UInt32) -> Bool { magnitudeCompareTo(w) == 0 }
    func magEQ(_ l: Int64) -> Bool { magnitudeCompareTo(l) == 0 }
    func magEQ(_ dw: UInt64) -> Bool { magnitudeCompareTo(dw) == 0 }

    func magNE(_ other: BigIntNumber) -> Bool { !magEQ(other) }
    func magNE(_ n: Int32) -> Bool { !magEQ(n) }
    func magNE(_ w: UInt32) -> Bool { !magEQ(w) }
    func magNE(_ l: Int64) -> Bool { !magEQ(l) }
    func magNE(_ dw: UInt64) -> Bool { !magEQ(dw) }

    // MARK: hashing

    func magnitudeHashCode() -> Int32 {
        verify(isNormalized())
        let c4: Int32 = 31 &* 31 &* 31 &* 31
        let c3: Int32 = 31 &* 31 &* 31
        let c2: Int32 = 31 &* 31
        var h: Int32 = 0
        var i = 0
        let n = Int(meta.normLen)
        while i + 3 < n {
            var t = c4 &* h
            t = t &+ c3 &* Int32(bitPattern: magia[i])
            t = t &+ c2 &* Int32(bitPattern: magia[i + 1])
            t = t &+ 31 &* Int32(bitPattern: magia[i + 2])
            t = t &+ Int32(bitPattern: magia[i + 3])
            h = t
            i += 4
        }
        while i < n {
            h = 31 &* h &+ Int32(bitPattern: magia[i])
            i += 1
        }
        return h
    }

    // MARK: string conversions (Phase 3 BigIntParsePrint)

    /// Decimal string (negatives prefixed with `-`).
    func toString() -> String { BigIntParsePrint.toString(meta.isNegative, magia, Int(meta.normLen)) }

    /// Hex string, `0x`-prefixed, uppercase (negatives prefixed with `-`).
    func toHexString() -> String { BigIntParsePrint.toHexString(self) }

    // MARK: algorithms (Phase 3 BigIntAlgorithms)

    /// Integer square root: largest r with r*r ≤ self < (r+1)^2.
    func isqrt() -> BigInt { BigIntAlgorithms.isqrt(self) }
    func isPerfectSquare() -> Bool { BigIntAlgorithms.isPerfectSquare(self) }

    // MARK: serde (Phase 3 BigIntSerde)

    func toTwosComplementBigEndianByteArray() -> [UInt8] {
        BigIntSerde.toTwosComplementBigEndianByteArray(self)
    }
    func toBinaryByteArray(_ isTwosComplement: Bool, _ isBigEndian: Bool) -> [UInt8] {
        BigIntSerde.toBinaryByteArray(self, isTwosComplement: isTwosComplement, isBigEndian: isBigEndian)
    }
    func magnitudeToLittleEndianIntArray() -> [Limb] {
        BigIntSerde.magnitudeToLittleEndianIntArray(self)
    }
    func magnitudeToLittleEndianLongArray() -> [UInt64] {
        BigIntSerde.magnitudeToLittleEndianLongArray(self)
    }
}

// Static debug helper (Kotlin companion `validateNormLenAndInjectPoison`).
@discardableResult
func validateNormLenAndInjectPoison(_ magia: Magia, _ normLen: Int) -> Bool {
    if magia.size > 0 {
        if normLen > 0 {
            if magia[normLen - 1] != 0 {
                magia.fill(0xDEAD, normLen, magia.size)
                return true
            }
        } else if normLen == 0 {
            magia.fill(0, 0, magia.size)
            return true
        }
    } else if normLen == 0 {
        return true
    }
    return false
}

extension BigIntNumber {
    @discardableResult
    func validateNormLenAndInjectPoison() -> Bool {
        let n = Int(meta.normLen)
        if magia.size >= 4 {
            if n > 0 {
                if magia[n - 1] != 0 {
                    magia.fill(0xDEAD, n, magia.size)
                    return true
                }
            } else {
                magia.fill(0, 0, magia.size)
                return true
            }
        }
        return false
    }
}

// ============================================================================
// DEFERRED from BigIntNumber.kt (depend on later phases):
//   isProbablePrime / nextProbablePrime        → Phase 4 BigIntPrime
//   toString / toHexString(×2)                 → Phase 3 BigIntParsePrint
//   toTwosComplementBigEndianByteArray,
//   toBinaryByteArray, toBinaryBytes,
//   magnitudeToLittleEndian{Int,Long}Array     → Phase 3 BigIntSerde
//   isqrt / isPerfectSquare                    → Phase 3 BigIntAlgorithms
//   toBigInt()  (protocol requirement; impl on each conformer in Phase 2)
// ============================================================================
