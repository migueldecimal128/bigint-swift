// SPDX-License-Identifier: MIT
//
// Port of Magia.kt — the low-level **unsigned** arbitrary-precision limb
// engine. Magnitudes are little-endian 64-bit limbs.
//
// NOTE (64-bit limb upgrade, BigIntSwift64BitLimbWorkOrder.md): this Swift
// engine diverges from `bigint-kotlin` (which stays 32-bit `IntArray`). The
// limb type is `UInt64`; limb×limb products are 128-bit, so the dword
// accumulator type is `DWord` (`UInt128`). Same algorithms, wider limbs.
//
// MEMORY MODEL (work order §6.1): in Kotlin `typealias Magia = IntArray` and the
// engine is ~2000 lines of free functions that write into a passed `IntArray`
// in place. Swift has no signed-Int-as-unsigned idiom worth keeping, so:
//
//   * limbs are native `UInt64` (`Limb`);
//   * `Magia` is a `final class` wrapping `ContiguousArray<Limb>` — reference
//     semantics give us in-place mutation through a passed reference AND O(1)
//     read-only sharing, exactly like Kotlin's `IntArray`. Aliased operands
//     (`z === x`) work because they are the same object.
//
// TRANSLITERATION CHEAT-SHEET (Kotlin → Swift), see PORTING_CONVENTIONS.md:
//   x[i].toDws()  →  x[i].toDw()       (Limb → DWord/UInt128, zero-extended)
//   dw32(n)       →  magia_dw32(n)      (Limb → DWord/UInt128, zero-extended)
//   ENGINE FREE FUNCTIONS are `magia_`-prefixed (portability; avoids the
//   member-shadows-global clash with BigInt/MutableBigInt methods).
//   t.toInt()     →  t.toLimb()        (low 64 bits → Limb)        [store]
//   t.toInt()     →  t.toInt64()       (low 64 bits → Int64)       [sign math]
//   a + b / a * b →  a &+ b / a &* b   (WRAPPING; mirror Kotlin two's-complement)
//   x ushr n      →  x >> n            (dwords are UInt128 → `>>` IS logical)
//   Long          →  UInt64 (unsigned magnitudes), Int(packed) → Int32
//   IntArray.size →  Magia.size  (capacity, NOT logical length)

import Foundation

public typealias Limb = UInt64

/// Double-width-of-limb accumulator type (`limb × limb` is 128-bit).
typealias DWord = UInt128

/// `Magia` == MAGnitude array. Reference-type little-endian 64-bit limb buffer.
/// Public as a *type* only (it appears in the public `BigIntNumber.magia`
/// requirement); its members stay internal, so it is opaque to consumers.
public final class Magia {
    var a: ContiguousArray<Limb>

    init(_ size: Int) {
        a = ContiguousArray(repeating: 0, count: size)
    }

    init(limbs: ContiguousArray<Limb>) {
        a = limbs
    }

    /// Number of allocated limbs (Kotlin `IntArray.size`) — capacity, not the
    /// logical normalized length.
    var size: Int { a.count }

    @inline(__always)
    subscript(_ i: Int) -> Limb {
        get { a[i] }
        set { a[i] = newValue }
    }

    /// Kotlin `this.copyInto(dst, destOff, start, end)`.
    func copyInto(_ dst: Magia, _ destOff: Int, _ start: Int, _ end: Int) {
        var d = destOff
        var s = start
        while s < end {
            dst.a[d] = a[s]
            d += 1
            s += 1
        }
    }

    /// Kotlin `IntArray.copyOf(newSize)`: copy min(newSize, count) limbs into a
    /// fresh array of `newSize`, zero-padding (or truncating) as needed.
    func copyOf(_ newSize: Int) -> Magia {
        let dst = Magia(newSize)
        let m = Swift.min(newSize, a.count)
        var i = 0
        while i < m { dst.a[i] = a[i]; i += 1 }
        return dst
    }

    /// Kotlin `IntArray.copyOf()` — full-length copy.
    func copyOf() -> Magia { copyOf(a.count) }

    /// Kotlin `IntArray.fill(value, fromIndex, toIndex)`.
    func fill(_ value: Limb, _ fromIndex: Int, _ toIndex: Int) {
        var i = fromIndex
        while i < toIndex {
            a[i] = value
            i += 1
        }
    }
}

// MARK: - scalar helpers / conversions

@inline(__always) func magia_bitLen(_ n: Limb) -> Int { 64 - Int(n.leadingZeroBitCount) }

let MASK32: UInt64 = 0xFFFF_FFFF

/// The one true zero-length array, usually used to represent ZERO.
/// `nonisolated(unsafe)`: a shared, never-mutated singleton (size 0).
nonisolated(unsafe) let MAGIA_ZERO = Magia(0)

/// The value ONE.  **WARNING** do NOT mutate this.
/// `nonisolated(unsafe)`: shared singleton, must not be mutated (as in Kotlin).
nonisolated(unsafe) let MAGIA_ONE = Magia(limbs: [1])

/// Returns the 64-bit limb `n` zero-extended to a double-width `DWord`.
@inline(__always) func magia_dw32(_ n: Limb) -> DWord { DWord(n) }

extension Limb { // UInt64
    /// Kotlin `Int.toDw()` / `UInt.toDw()` — zero-extend a limb to a dword.
    /// We use UNSIGNED `DWord`/`UInt128` (not Kotlin's signed `Long`); `>>` is
    /// then logical, matching Kotlin's `ushr`. See PORTING_CONVENTIONS.md.
    @inline(__always) func toDw() -> DWord { DWord(self) }
}

extension DWord { // UInt128
    /// Kotlin `.toInt()` truncated into a limb (low 64 bits).
    @inline(__always) func toLimb() -> Limb { Limb(truncatingIfNeeded: self) }
    /// Kotlin `.toInt()` as a signed Int64 (for sign-mask arithmetic).
    @inline(__always) func toInt64() -> Int64 { Int64(truncatingIfNeeded: self) }
}

extension Int32 {
    /// Kotlin `Int ushr n` — LOGICAL right shift on a signed 32-bit value.
    @inline(__always) func ushr(_ n: Int32) -> Int32 {
        Int32(bitPattern: UInt32(bitPattern: self) >> UInt32(n))
    }
}

/// Largest allowed limb-array length (2²⁵−1), so bitLength = len*64 < Int32.max.
let MAX_ALLOC_SIZE = (1 << 25) - 1

/// First limb of `x` as a `Limb` (0 if empty).
func magia_toRawUInt(_ x: Magia) -> Limb { x.size == 0 ? 0 : x[0] }

/// Low 64 bits of the magnitude as `UInt64`. At 64-bit limbs this is exactly
/// the first limb (a limb IS a `UInt64`).
func magia_toRawULong(_ x: Magia, _ xNormLen: Int) -> UInt64 {
    xNormLen == 0 ? 0 : x[0]
}

/// First limb as `UInt64`, no bounds/normalization checks.
@inline(__always) func magia_toRawULongExact(_ x: Magia) -> UInt64 {
    x[0]
}

/// Stores `dw` into `z` as a little-endian limb; returns the limb length (0–1).
/// At 64-bit limbs a `UInt64` value occupies a single limb.
func magia_setULong(_ z: Magia, _ dw: UInt64) -> Int {
    if dw == 0 { return 0 }
    z[0] = dw
    return 1
}

// MARK: - normalized length

/// Highest non-zero limb index + 1 over the whole array (0 if all zero).
/// WARNING: only safe on `new`-allocated magia (picks up garbage upper limbs).
func magia_normLen(_ x: Magia) -> Int {
    var i = x.size
    while true {
        i -= 1
        if i < 0 { break }
        if x[i] != 0 { return i + 1 }
    }
    return 0
}

/// Highest non-zero limb index + 1 within the first `xLen` limbs.
func magia_normLen(_ x: Magia, _ xLen: Int) -> Int {
    if xLen < 0 || xLen > x.size { throwBoundsCheckViolation_Int() }
    var i = xLen
    while true {
        i -= 1
        if i < 0 { break }
        if x[i] != 0 { return i + 1 }
    }
    return 0
}

/// Highest non-zero limb index + 1 within `xLen` limbs starting at `xOff`.
func magia_normLen(_ x: Magia, _ xOff: Int, _ xLen: Int) -> Int {
    if xOff < 0 || xLen < 0 || xOff + xLen > x.size { throwBoundsCheckViolation_Int() }
    var i = xLen
    while true {
        i -= 1
        if i < 0 { break }
        if x[xOff + i] != 0 { return i + 1 }
    }
    return 0
}

func magia_isNormalized(_ x: Magia, _ xLen: Int) -> Bool {
    verify(xLen >= 0 && xLen <= x.size)
    return xLen == 0 || x[xLen - 1] != 0
}

func magia_isNormalized(_ x: Magia, _ xOff: Int, _ xLen: Int) -> Bool {
    verify(xOff >= 0 && xLen >= 0 && xOff + xLen <= x.size)
    return xLen == 0 || x[xOff + xLen - 1] != 0
}

// MARK: - allocation

/// Limbs needed to hold `bitLen` bits (64-bit limbs: `(bitLen + 0x3F) ushr 6`).
@inline(__always) func magia_limbLenFromBitLen(_ bitLen: Int) -> Int { (bitLen + 0x3F) >> 6 }

func magia_newWithBitLen(_ bitLen: Int) -> Magia {
    if bitLen >= 1 && bitLen <= MAX_ALLOC_SIZE * 64 {
        return Magia(magia_limbLenFromBitLen(bitLen))
    }
    if bitLen == 0 {
        return MAGIA_ZERO
    }
    throwInvalidAllocationLength_Magia()
}

func magia_newWithFloorLen(_ floorLen: Int) -> Magia {
    Magia(magia_calcHeapLimbQuantum(floorLen))
}

/// Allocation size ≥ max(4, floorLen) rounded up to a multiple of 4.
@inline(__always) func magia_calcHeapLimbQuantum(_ floorLen: Int) -> Int {
    if floorLen >= 0 && floorLen <= MAX_ALLOC_SIZE - 3 {
        // if floorLen == 0 then add 1  (Kotlin: floorLen + 1 - (-floorLen ushr 31))
        let t = floorLen + 1 - (floorLen > 0 ? 1 : 0)
        let allocSize = (t + 3) & ~3
        return allocSize
    }
    throwInvalidAllocationLength_Int()
}

func magia_newCopyWithExactBitLen(_ x: Magia, _ xLen: Int, _ exactBitLen: Int) -> Magia {
    magia_newCopyWithExactLimbLen(x, xLen, (exactBitLen + 0x3F) >> 6)
}

func magia_newCopyWithExactLimbLen(_ x: Magia, _ xLen: Int, _ exactLimbLen: Int) -> Magia {
    if exactLimbLen >= 1 && exactLimbLen <= MAX_ALLOC_SIZE {
        let dst = Magia(exactLimbLen)
        x.copyInto(dst, 0, 0, min(xLen, dst.size))
        return dst
    }
    if exactLimbLen == 0 {
        return MAGIA_ZERO
    }
    throwInvalidAllocationLength_Magia()
}

// MARK: - add

/// `x += w` in place; returns new normalized length.
func magia_mutAddLimb(_ x: Magia, _ xNormLen: Int, _ w: Limb) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size {
        if w == 0 { return xNormLen }
        var carry: Limb = w
        var i = 0
        while i < xNormLen {
            let (s, c) = x[i].addingReportingOverflow(carry)
            x[i] = s
            carry = c ? 1 : 0
            if carry == 0 { return xNormLen }
            i += 1
        }
        if i < x.size {
            verify(carry != 0)
            x[i] = carry
            i += 1
            verify(magia_isNormalized(x, i))
            return i
        }
        throwAddOverflow()
    }
    throwBoundsCheckViolation()
}

/// `x += y` in place; returns new normalized length.
func magia_mutAdd(_ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    verify(magia_isNormalized(x, xNormLen))
    verify(magia_isNormalized(y, yNormLen))
    if xNormLen > 0 && xNormLen <= x.size && yNormLen > 0 && yNormLen <= y.size {
        let maxNormLen = max(xNormLen, yNormLen)
        if maxNormLen <= x.size {
            // Pre-copy any hi limbs from y that extend beyond x
            if yNormLen > xNormLen {
                y.copyInto(x, xNormLen, xNormLen, yNormLen)
            }
            let minNormLen = min(xNormLen, yNormLen)
            var carry: Limb = 0
            var i = 0
            repeat {
                let (s0, c0) = x[i].addingReportingOverflow(y[i])
                let (s1, c1) = s0.addingReportingOverflow(carry)
                x[i] = s1
                carry = (c0 ? 1 : 0) &+ (c1 ? 1 : 0)
                i += 1
            } while i < minNormLen
            if carry == 0 { return maxNormLen }
            while i < maxNormLen {
                let (s, c) = x[i].addingReportingOverflow(carry)
                x[i] = s
                carry = c ? 1 : 0
                if carry == 0 { return maxNormLen }
                i += 1
            }
            if carry != 0 {
                verify(i == maxNormLen && i < x.size)
                x[i] = 1
                i += 1
            }
            verify(magia_isNormalized(x, i))
            return i
        }
    }
    throwBoundsCheckViolation_Int()
}

// MARK: - sub

/// `x -= w` in place (requires x ≥ w); returns new normalized length.
func magia_mutSubLimb(_ x: Magia, _ xNormLen: Int, _ w: Limb) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size {
        var borrow: Limb = w
        var i = 0
        while i < xNormLen {
            if borrow == 0 { return xNormLen }
            let (d, b) = x[i].subtractingReportingOverflow(borrow)
            x[i] = d
            borrow = b ? 1 : 0
            i += 1
        }
        if borrow == 0 {
            // The last limb might have become zero
            let zNormLen = xNormLen - (x[xNormLen - 1] == 0 ? 1 : 0)
            verify(magia_isNormalized(x, zNormLen))
            return zNormLen
        }
        throwSubUnderflow_Int()
    }
    throwBoundsCheckViolation_Int()
}

/// `x -= y` in place (requires x ≥ y); returns new normalized length.
func magia_mutSub(_ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    verify(magia_isNormalized(x, xNormLen))
    verify(magia_isNormalized(y, yNormLen))
    if xNormLen > 0 && xNormLen <= x.size && yNormLen > 0 && yNormLen <= y.size {
        if xNormLen >= yNormLen {
            var borrow: Limb = 0
            var i = 0
            repeat {
                let (d0, b0) = x[i].subtractingReportingOverflow(y[i])
                let (d1, b1) = d0.subtractingReportingOverflow(borrow)
                x[i] = d1
                borrow = (b0 ? 1 : 0) &+ (b1 ? 1 : 0)
                i += 1
            } while i < yNormLen
            if borrow == 0 {
                var zNormLen = xNormLen
                if x[xNormLen - 1] == 0 {
                    zNormLen -= 1
                    if yNormLen == xNormLen {
                        while zNormLen > 0 && x[zNormLen - 1] == 0 {
                            zNormLen -= 1
                        }
                    }
                }
                verify(magia_isNormalized(x, zNormLen))
                return zNormLen
            }
            while i < xNormLen {
                let (d, b) = x[i].subtractingReportingOverflow(borrow)
                x[i] = d
                borrow = b ? 1 : 0
                if borrow == 0 {
                    // a full 2^64 underflow at an inner limb can zero several top
                    // limbs at once, so trim all trailing zeros (not just one)
                    var zNormLen = xNormLen
                    while zNormLen > 0 && x[zNormLen - 1] == 0 { zNormLen -= 1 }
                    verify(magia_isNormalized(x, zNormLen))
                    return zNormLen
                }
                i += 1
            }
            verify(borrow != 0)
        }
        // y is longer than x, guaranteed underflow
        throwSubUnderflow_Int()
    }
    throwBoundsCheckViolation_Int()
}

/// `z = x - y` (requires x ≥ y); z may alias x or y. Returns normalized length.
func magia_setSub(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size && yNormLen >= 0 && yNormLen <= y.size {
        verify(magia_isNormalized(x, xNormLen))
        verify(magia_isNormalized(y, yNormLen))
        if z.size >= xNormLen {
            if xNormLen >= yNormLen {
                var borrow: Limb = 0
                var lastNonZeroIndex = -1
                var i = 0
                while i < yNormLen {
                    let (d0, b0) = x[i].subtractingReportingOverflow(y[i])
                    let (d1, b1) = d0.subtractingReportingOverflow(borrow)
                    z[i] = d1
                    let zi = Int64(bitPattern: d1)
                    let nonZeroMask = Int((zi | (0 &- zi)) >> 63)
                    lastNonZeroIndex = (lastNonZeroIndex & ~nonZeroMask) | (i & nonZeroMask)
                    borrow = (b0 ? 1 : 0) &+ (b1 ? 1 : 0)
                    i += 1
                }
                while i < xNormLen {
                    let (d, b) = x[i].subtractingReportingOverflow(borrow)
                    z[i] = d
                    let zi = Int64(bitPattern: d)
                    let nonZeroMask = Int((zi | (0 &- zi)) >> 63)
                    lastNonZeroIndex = (lastNonZeroIndex & ~nonZeroMask) | (i & nonZeroMask)
                    borrow = b ? 1 : 0
                    i += 1
                }
                if borrow == 0 {
                    let zNormLen = lastNonZeroIndex + 1
                    verify(magia_isNormalized(z, zNormLen))
                    return zNormLen
                }
            }
            throwSubUnderflow()
        }
    }
    throwBoundsCheckViolation()
}

// MARK: - mul
//
// NOTE: limb products use `multipliedFullWidth(by:)` → (high, low) UInt64 pair,
// and the running carry is a single `Limb` (the product's high word). A limb*limb
// product is ≤ (2^64-1)^2, so the full accumulator (product + carry + addend)
// stays ≤ 2^128-1 and the next carry `hi &+ (addCarryBits)` never overflows a
// UInt64 — the wrapping `&+` is provably non-wrapping here.

/// `z = x * w`; safe in place (z may === x). Returns normalized length.
func magia_setMulLimb(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ w: Limb) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size {
        verify(magia_isNormalized(x, xNormLen))
        if xNormLen > 0 && w.nonzeroBitCount > 1 {
            var carry: Limb = 0
            var i = 0
            while i < xNormLen {
                let (hi, lo) = x[i].multipliedFullWidth(by: w)
                let (s, c) = lo.addingReportingOverflow(carry)
                z[i] = s
                carry = hi &+ (c ? 1 : 0)
                i += 1
            }
            if carry != 0 {
                if i >= z.size { throwMulOverflow() }
                z[i] = carry
                i += 1
            }
            verify(magia_isNormalized(z, i))
            return i
        }
        if xNormLen == 0 || w == 0 { return 0 }
        return magia_setShiftLeft(z, x, xNormLen, Int(w.trailingZeroBitCount))
    }
    throwBoundsCheckViolation()
}

func magia_setMul(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    magia_setMulSchoolbook(z, x, xNormLen, y, yNormLen)
}

func magia_setMulSchoolbook(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    verify(z !== x && z !== y)
    if xNormLen >= 0 && xNormLen <= x.size &&
        yNormLen >= 0 && yNormLen <= y.size &&
        z.size >= xNormLen + yNormLen - 1
    {
        if xNormLen == 0 || yNormLen == 0 { return 0 }

        let corto = xNormLen < yNormLen ? x : y
        let largo = xNormLen < yNormLen ? y : x
        let cortoLen = xNormLen < yNormLen ? xNormLen : yNormLen
        let largoLen = xNormLen < yNormLen ? yNormLen : xNormLen

        // zero out the minimum amount needed; higher limbs written before read
        z.fill(0, 0, largoLen)
        for i in 0..<cortoLen {
            let cortoLimb = corto[i]
            var carry: Limb = 0
            for j in 0..<largoLen {
                let (hi, lo) = cortoLimb.multipliedFullWidth(by: largo[j])
                let (s0, c0) = lo.addingReportingOverflow(carry)
                let (s1, c1) = s0.addingReportingOverflow(z[i + j])
                z[i + j] = s1
                carry = hi &+ (c0 ? 1 : 0) &+ (c1 ? 1 : 0)
            }
            if i + largoLen < z.size {
                z[i + largoLen] = carry
            } else if carry != 0 {
                throwMulOverflow()
            }
        }
        var lastIndex = cortoLen + largoLen - 1
        // >= instead of == to help bounds check elimination
        if lastIndex >= z.size || z[lastIndex] == 0 { lastIndex -= 1 }
        let zNormLen = lastIndex + 1
        verify(magia_isNormalized(z, zNormLen))
        return zNormLen
    }
    throwBoundsCheckViolation()
}

/// Powers of 10 from 10⁰ through 10⁹, for fast small-power decimal scaling.
private let POW10: [UInt64] = [
    1, 10, 100, 1000, 10000, 100000, 1000000,
    10000000, 100000000, 1000000000
]

/// In-place fused multiply-add: `x = x * 10^pow10 + a`, pow10 in 0..9.
func magia_mutateFmaPow10(_ x: Magia, _ xLen: Int, _ pow10: Int, _ a: Limb) {
    if pow10 >= 0 && pow10 <= 9 {
        let m = POW10[pow10]
        var carry: Limb = a
        for i in 0..<xLen {
            let (hi, lo) = x[i].multipliedFullWidth(by: m)
            let (s, c) = lo.addingReportingOverflow(carry)
            x[i] = s
            carry = hi &+ (c ? 1 : 0)
        }
    } else {
        fatalError() // IllegalArgumentException
    }
}

// MARK: - shifts

/// `z = x >> bitCount`; safe in place (z may === x). Returns normalized length.
func magia_setShiftRight(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ bitCount: Int) -> Int {
    precondition(bitCount >= 0 && xNormLen >= 0 && xNormLen <= x.size)
    verify(magia_isNormalized(x, xNormLen))
    if xNormLen == 0 { return 0 }
    precondition(x[xNormLen - 1] != 0)
    let newBitLen = magia_normBitLen(x, xNormLen) - bitCount
    if newBitLen <= 0 { return 0 }
    let zNormLen = (newBitLen + 0x3F) >> 6
    precondition(zNormLen <= z.size)
    let wordShift = bitCount >> 6
    let innerShift = bitCount & ((1 << 6) - 1)
    if innerShift != 0 {
        let iLast = zNormLen - 1
        for i in 0..<iLast {
            z[i] = (x[i + wordShift + 1] << (64 - innerShift)) | (x[i + wordShift] >> innerShift)
        }
        let srcIndex = iLast + wordShift + 1
        z[iLast] = (
            srcIndex < xNormLen
                ? (x[iLast + wordShift + 1] << (64 - innerShift))
                : 0
        ) | (x[iLast + wordShift] >> innerShift)
    } else {
        for i in 0..<zNormLen {
            z[i] = x[i + wordShift]
        }
    }
    verify(magia_isNormalized(z, zNormLen))
    return zNormLen
}

/// `z = x << bitCount`; safe in place (z may === x). Returns normalized length.
func magia_setShiftLeft(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ bitCount: Int) -> Int {
    verify(magia_isNormalized(x, xNormLen))

    if xNormLen == 0 { return 0 }

    let xBitLen = magia_normBitLen(x, xNormLen)

    let wordShift = bitCount >> 6
    let innerShift = bitCount & 63

    let zBitLen = xBitLen + bitCount
    let zNormLen = magia_limbLenFromBitLen(zBitLen)

    if zNormLen > z.size { throwShlOverflow() }

    // Fast path: whole-limb shift only
    if innerShift == 0 {
        x.copyInto(z, wordShift, 0, xNormLen)
        z.fill(0, 0, wordShift)

        precondition(magia_isNormalized(z, zNormLen))
        return zNormLen
    }

    // Non-zero inner shift: detect spill from top limb
    let top = x[xNormLen - 1]
    let spill = top >> (64 - innerShift)   // 0 if no spill

    // Write spill limb FIRST (important if z === x)
    if spill != 0 {
        z[zNormLen - 1] = spill
    }

    // Main shift loop: high → low (in-place safe)
    for src in stride(from: xNormLen - 1, through: 1, by: -1) {
        let dst = src + wordShift
        z[dst] = (x[src] << innerShift) | (x[src - 1] >> (64 - innerShift))
    }

    // lowest shifted limb
    z[wordShift] = x[0] << innerShift

    // clear lower limbs
    z.fill(0, 0, wordShift)

    verify(magia_isNormalized(z, zNormLen))
    return zNormLen
}

// MARK: - bit queries

func magia_isPowerOfTwo(_ x: Magia, _ xNormLen: Int) -> Bool {
    verify(magia_isNormalized(x, xNormLen))
    if xNormLen >= 0 && xNormLen <= x.size {
        var bitSeen = false
        for i in 0..<xNormLen {
            let w = x[i]
            if w != 0 {
                if bitSeen || (w & (w - 1)) != 0 { return false }
                bitSeen = true
            }
        }
        return bitSeen
    }
    throwBoundsCheckViolation()
}

func magia_bitLen(_ x: Magia) -> Int { magia_bitLen(x, x.size) }

func magia_bitLen(_ x: Magia, _ xLen: Int) -> Int {
    if xLen >= 0 && xLen <= x.size {
        var i = xLen - 1
        while i >= 0 {
            if x[i] != 0 {
                return 64 - Int(x[i].leadingZeroBitCount) + (i * 64)
            }
            i -= 1
        }
        return 0
    }
    throwBoundsCheckViolation()
}

func magia_normBitLen(_ x: Magia, _ xLen: Int) -> Int {
    if xLen > 0 {
        let lastLimb = x[xLen - 1]
        verify(lastLimb != 0)
        return (xLen << 6) - Int(lastLimb.leadingZeroBitCount)
    }
    return 0
}

@inline(__always) func magia_nonZeroNormBitLen(_ x: Magia, _ xLen: Int) -> Int {
    let lastLimb = x[xLen - 1]
    verify(lastLimb != 0)
    return (xLen << 6) - Int(lastLimb.leadingZeroBitCount)
}

/// Bit length using Java BigInteger semantics (two's-complement, minus sign bit).
func magia_bitLengthBigIntegerStyle(_ sign: Bool, _ x: Magia, _ xNormLen: Int) -> Int {
    verify(magia_isNormalized(x, xNormLen))
    if xNormLen >= 0 && xNormLen <= x.size {
        let bitLen = magia_normBitLen(x, xNormLen)
        let isNegPowerOfTwo = sign && magia_isPowerOfTwo(x, xNormLen)
        return bitLen - (isNegPowerOfTwo ? 1 : 0)
    }
    throwBoundsCheckViolation()
}

/// Count of trailing zero bits in the magnitude; -1 if zero.
func magia_ctz(_ x: Magia, _ normLen: Int) -> Int {
    if normLen >= 0 && normLen <= x.size {
        for i in 0..<normLen {
            if x[i] != 0 {
                return (i << 6) + Int(x[i].trailingZeroBitCount)
            }
        }
        return -1
    }
    throwBoundsCheckViolation()
}

// MARK: - bitwise
//
// magia_setAnd / magia_setOr / magia_setXor removed: the BigInt/MutableBigInt
// bitwise ops are now two's-complement (matching java.math.BigInteger) and are
// implemented at the BigInt layer (BigInt.bitwise / twosComplementLimb), so the
// old magnitude-only engine kernels are no longer used.

// MARK: - bit tests / extraction

func magia_testBit(_ x: Magia, _ xLen: Int, _ bitIndex: Int) -> Bool {
    if xLen >= 0 && xLen <= x.size {
        let wordIndex = bitIndex >> 6
        if wordIndex >= xLen { return false }
        let word = x[wordIndex]
        let bitMask: Limb = 1 << (bitIndex & 0x3F)
        return (word & bitMask) != 0
    }
    throwBoundsCheckViolation()
}

func magia_testAnyBitInLowerN(_ x: Magia, _ xLen: Int, _ bitCount: Int) -> Bool {
    if xLen >= 0 && xLen <= x.size {
        let lastBitIndex = bitCount - 1
        let lastWordIndex = lastBitIndex >> 6
        for i in 0..<lastWordIndex {
            if i == xLen { return false }
            if x[i] != 0 { return true }
        }
        if lastWordIndex == xLen { return false }
        // -1 ushr (63 - r)  →  low (r+1) bits set
        let bitMask: Limb = Limb.max >> (0x3F - (lastBitIndex & 0x3F))
        return (x[lastWordIndex] & bitMask) != 0
    }
    throwBoundsCheckViolation()
}

/// `(x >> bitIndex) mod 2^64`. Reads up to two limbs.
func magia_extractULongAtBitIndex(_ x: Magia, _ xNormLen: Int, _ bitIndex: Int) -> UInt64 {
    if bitIndex >= 0 {
        let loLimb = bitIndex >> 6
        let innerShift = bitIndex & 0x3F
        if bitIndex == 0 { return magia_toRawULong(x, xNormLen) }
        if loLimb >= xNormLen { return 0 }
        let lo = x[loLimb]
        if innerShift == 0 { return lo }                 // window is exactly one limb
        if (loLimb + 1) == xNormLen { return lo >> innerShift }
        let hi = x[loLimb + 1]
        return (hi << (64 - innerShift)) | (lo >> innerShift)
    }
    throwNegBitIndex()
}

// MARK: - compare / equality

/// `true` if the normalized magnitude `x` equals the single value `y` (bit pattern).
func magia_EQ(_ x: Magia, _ xNormLen: Int, _ y: Int64) -> Bool {
    xNormLen == 1 && x[0] == Limb(bitPattern: y)
}

func magia_EQ(_ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Bool {
    magia_compare(x, xNormLen, y, yNormLen) == 0
}

/// Unsigned compare: -1 if x < y, 0 if equal, 1 if x > y.
func magia_compare(_ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    verify(magia_isNormalized(x, xNormLen))
    verify(magia_isNormalized(y, yNormLen))
    if xNormLen >= 0 && xNormLen <= x.size && yNormLen >= 0 && yNormLen <= y.size {
        if xNormLen != yNormLen {
            return ((xNormLen - yNormLen) >> 63) | 1
        }
        var i = xNormLen - 1
        while i >= 0 {
            if x[i] != y[i] {
                return x[i] < y[i] ? -1 : 1   // unsigned limb compare
            }
            i -= 1
        }
        return 0
    }
    throwBoundsCheckViolation()
}

/// Compare the magnitude with an unsigned 64-bit value.
func magia_compare(_ x: Magia, _ xNormLen: Int, _ dw: UInt64) -> Int {
    verify(magia_isNormalized(x, xNormLen))
    if xNormLen >= 0 && xNormLen <= x.size {
        if xNormLen > 1 { return 1 }      // ≥2 limbs ⇒ > 2^64 > any UInt64
        let xv = magia_toRawULong(x, xNormLen)
        return xv < dw ? -1 : (xv > dw ? 1 : 0)
    }
    throwBoundsCheckViolation()
}

// MARK: - division / remainder
//
// Single-limb division (setDivLimb/calcRemLimb) builds a 128-bit dividend
// (DWord) from (remainder:limb) and uses native UInt128 `/` and `%`. The Knuth
// path uses UInt128 for the quotient ESTIMATE (qhat/rhat) and SIGNED Int128 for
// the multiply-and-subtract BORROW propagation, which relies on an arithmetic
// `t >> 64` of a negative intermediate. The Kotlin signed-vs-unsigned two-path
// split was only a JVM unsigned-division workaround; here it collapses to one path.

/// `z = x / w`; supports in place. Returns normalized length.
func magia_setDivLimb(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ w: Limb) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size && z.size >= xNormLen {
        verify(magia_isNormalized(x, xNormLen))
        if w == 0 { throwDivByZero_Int() }
        if xNormLen == 0 { return 0 }
        if w.nonzeroBitCount == 1 {
            return magia_setShiftRight(z, x, xNormLen, Int(w.trailingZeroBitCount))
        }
        let dw = DWord(w)
        var carry: UInt64 = 0
        var i = xNormLen - 1
        while i >= 0 {
            let t = (DWord(carry) << 64) | x[i].toDw()
            z[i] = (t / dw).toLimb()
            carry = (t % dw).toLimb()
            i -= 1
        }
        let zNormLen = xNormLen - (z[xNormLen - 1] == 0 ? 1 : 0)
        verify(magia_isNormalized(z, zNormLen))
        return zNormLen
    }
    throwBoundsCheckViolation()
}

/// Fast paths for `x / y`. Writes quotient to z and returns its length, or -1.
func magia_trySetDivFastPath(_ zMagia: Magia, _ xMagia: Magia, _ xNormLen: Int, _ yMagia: Magia, _ yNormLen: Int) -> Int {
    if yNormLen == 0 { throwDivByZero_Int() }
    if xNormLen == 0 { return 0 }
    if xNormLen < yNormLen { return 0 }
    if xNormLen <= 1 {        // both x and y fit in a single 64-bit limb
        return magia_setULong(zMagia, magia_toRawULong(xMagia, xNormLen) / magia_toRawULong(yMagia, yNormLen))
    }
    if yNormLen == 1 {
        return magia_setDivLimb(zMagia, xMagia, xNormLen, yMagia[0])
    }
    if magia_isPowerOfTwo(yMagia, yNormLen) {
        return magia_setShiftRight(zMagia, xMagia, xNormLen, magia_ctz(yMagia, yNormLen))
    }
    // note that this also handles aliasing when x === y
    if xNormLen == yNormLen {
        let xBitLen = magia_normBitLen(xMagia, xNormLen)
        let yBitLen = magia_normBitLen(yMagia, yNormLen)
        if xBitLen < yBitLen { return 0 }
        if xBitLen == yBitLen {
            let cmp = magia_compare(xMagia, xNormLen, yMagia, yNormLen)
            if cmp < 0 { return 0 }
            zMagia[0] = 1
            return 1
        }
    }
    return -1
}

/// `x mod w` as a single limb.
func magia_calcRemLimb(_ x: Magia, _ xNormLen: Int, _ w: Limb) -> Limb {
    if xNormLen >= 0 && xNormLen <= x.size {
        verify(magia_isNormalized(x, xNormLen))
        if w == 0 { throwDivByZero() }
        if xNormLen == 0 { return 0 }
        if w.nonzeroBitCount == 1 {
            return x[0] & ((Limb(1) << w.trailingZeroBitCount) - 1)
        }
        if xNormLen == 1 { return x[0] % w }
        let dw = DWord(w)
        var carry: UInt64 = 0
        var i = xNormLen - 1
        while i >= 0 {
            let t = (DWord(carry) << 64) | x[i].toDw()
            carry = (t % dw).toLimb()
            i -= 1
        }
        return carry
    }
    throwBoundsCheckViolation()
}

/// `z = x / y` via Knuth (z is the quotient). xTmp/yTmp optional scratch.
func magia_setDivKnuth(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ xTmp: Magia?,
                 _ y: Magia, _ yNormLen: Int, _ yTmp: Magia?) -> Int {
    verify(magia_isNormalized(x, xNormLen))
    verify(magia_isNormalized(y, yNormLen))
    verify(xTmp == nil || xTmp!.size >= xNormLen + 1)
    verify(yTmp == nil || yTmp!.size >= yNormLen)
    if xNormLen < yNormLen || yNormLen < 2 { throwBadKnuthArgument() }
    let m = xNormLen
    let n = yNormLen
    let u = x
    let v = y
    if z.size < m - n + 1 { throwBadKnuthArgument() }
    let q = z
    let r: Magia? = nil
    // At 64-bit limbs every multi-limb divisor (n >= 2) goes through the general
    // Knuth path; there is no UInt64-fits-in-two-limbs special case anymore.
    let qNormLen = magia_knuthDivide(q, r, u, v, m, n, xTmp, yTmp)
    verify(magia_isNormalized(q, qNormLen))
    return qNormLen
}

/// `z = x mod y`. Returns normalized length of the remainder.
func magia_setRem(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    verify(magia_isNormalized(x, xNormLen))
    verify(magia_isNormalized(y, yNormLen))
    let rLen0 = magia_trySetRemFastPath(z, x, xNormLen, y, yNormLen)
    if rLen0 >= 0 { return rLen0 }
    let n = yNormLen
    let m = xNormLen
    let u = x
    let v = y
    let q: Magia? = nil
    if z.size < yNormLen { throwBoundsCheckViolation() }
    let r = z
    let rNormLen = magia_knuthDivide(q, r, u, v, m, n)
    verify(rNormLen <= n)
    verify(magia_isNormalized(r, rNormLen))
    return rNormLen
}

func magia_trySetRemFastPath(_ zMagia: Magia, _ xMagia: Magia, _ xNormLen: Int, _ yMagia: Magia, _ yNormLen: Int) -> Int {
    if yNormLen == 0 { throwDivByZero() }
    if xNormLen < yNormLen {
        xMagia.copyInto(zMagia, 0, 0, xNormLen)
        return xNormLen
    }
    if yNormLen == 1 {
        // single-limb divisor → single-limb remainder
        let rem = magia_calcRemLimb(xMagia, xNormLen, yMagia[0])
        zMagia[0] = rem
        return rem == 0 ? 0 : 1
    }
    // note that this also handles aliasing when x === y
    if xNormLen == yNormLen {
        let xBitLen = magia_normBitLen(xMagia, xNormLen)
        let yBitLen = magia_normBitLen(yMagia, yNormLen)
        if xBitLen < yBitLen {
            xMagia.copyInto(zMagia, 0, 0, xNormLen)
            verify(magia_isNormalized(zMagia, xNormLen))
            return xNormLen
        }
        if xBitLen == yBitLen {
            let cmp = magia_compare(xMagia, xNormLen, yMagia, yNormLen)
            if cmp < 0 {
                xMagia.copyInto(zMagia, 0, 0, xNormLen)
                verify(magia_isNormalized(zMagia, xNormLen))
                return xNormLen
            }
            if cmp == 0 { return 0 }
            return magia_setSub(zMagia, xMagia, xNormLen, yMagia, yNormLen)
        }
    }
    return -1
}

/// `z = x mod y` via Knuth (z is the remainder). xTmp/yTmp optional scratch.
func magia_setRem(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ xTmp: Magia?,
            _ y: Magia, _ yNormLen: Int, _ yTmp: Magia?) -> Int {
    verify(magia_isNormalized(x, xNormLen))
    verify(magia_isNormalized(y, yNormLen))
    verify(xTmp == nil || xTmp!.size >= xNormLen + 1)
    verify(yTmp == nil || yTmp!.size >= yNormLen)
    if xNormLen < yNormLen || yNormLen < 2 { fatalError() }
    let m = xNormLen
    let n = yNormLen
    let u = x
    let v = y
    if z.size < yNormLen { fatalError() }
    let r = z
    // At 64-bit limbs every multi-limb divisor (n >= 2) goes through the general
    // Knuth path; there is no UInt64-fits-in-two-limbs special case anymore.
    let rNormLen = magia_knuthDivide(nil, r, u, v, m, n, xTmp, yTmp)
    verify(magia_isNormalized(z, rNormLen))
    return rNormLen
}

// MARK: - Knuth Algorithm D (base 2^64)

/// Multi-word division. q (length ≥ m-n+1) or nil; r (length ≥ n) or nil.
/// Returns qNormLen if q != nil, rNormLen if r != nil, else -1.
func magia_knuthDivide(_ q: Magia?, _ r: Magia?, _ u: Magia, _ v: Magia, _ m: Int, _ n: Int,
                 _ unBuf: Magia? = nil, _ vnBuf: Magia? = nil) -> Int {
    if m < n || n < 2 || v[n - 1] == 0 { fatalError() }
    verify(r !== q)

    // Step D1: Normalize
    let un: Magia
    if let unBuf {
        if unBuf.size < m + 1 { fatalError() }
        un = unBuf
    } else if let r, r.size >= m + 1, r !== v {
        un = r
    } else {
        un = Magia(m + 1)
    }
    u.copyInto(un, 0, 0, m)
    un[m] = 0
    let vn: Magia
    if let vnBuf {
        if vnBuf.size < n { fatalError() }
        vn = vnBuf
    } else {
        vn = Magia(n)
    }
    v.copyInto(vn, 0, 0, n)

    let shift = Int(vn[n - 1].leadingZeroBitCount)
    if shift > 0 {
        _ = magia_setShiftLeft(vn, vn, n, shift)
        _ = magia_setShiftLeft(un, un, m, shift)
    }

    magia_knuthDivideNormalizedCore(q, un, vn, m, n)

    var rNormLen = 0
    if let r {
        rNormLen = magia_setShiftRight(r, un, magia_normLen(un, m + 1), shift)
    }

    if let q { return magia_normLen(q, m - n + 1) }
    if r != nil { return rNormLen }
    return -1
}

/// Core of Knuth division; `un` is side-effected and holds the remainder.
func magia_knuthDivideNormalizedCore(_ q: Magia?, _ un: Magia, _ vn: Magia, _ m: Int, _ n: Int) {
    // top limb must be normalized (hi bit of the 64-bit limb set)
    if m < n || n < 2 || vn[n - 1] < 0x8000_0000_0000_0000 { fatalError() }

    let vn_1 = vn[n - 1]               // UInt64, normalized (>= 2^63)
    let vn_2 = vn[n - 2]               // UInt64
    let vn_1d = DWord(vn_1)
    let vn_2d = DWord(vn_2)

    var j = m - n
    while j >= 0 {
        let jn = j + n
        let jn1 = jn - 1
        let jn2 = jn - 2
        // estimate q̂ = (un[j+n]*B + un[j+n-1]) / vn[n-1], with B = 2^64.
        let hiLimb = un[jn]
        let loLimb = un[jn1]
        var qhat: DWord
        var rhat: DWord
        if hiLimb >= vn_1 {
            // True quotient would be >= 2^64 (un[jn] <= vn_1 by the Knuth
            // invariant, so this is the un[jn] == vn_1 edge). dividingFullWidth
            // would TRAP here — cap qhat at B-1 and derive the matching rhat.
            qhat = DWord(UInt64.max)
            let num = (DWord(hiLimb) << 64) | DWord(loLimb)
            rhat = num &- qhat &* vn_1d
        } else {
            let (q64, r64) = vn_1.dividingFullWidth((high: hiLimb, low: loLimb))
            qhat = DWord(q64)
            rhat = DWord(r64)
        }

        // refine (Knuth D3, ≤2 iterations). Guard `rhat < B` so `rhat << 64`
        // can't overflow; once rhat >= B the test is false and we stop.
        let un_j = DWord(un[jn2])
        while rhat >> 64 == 0 && qhat &* vn_2d > (rhat << 64) | un_j {
            qhat &-= 1
            rhat = rhat &+ vn_1d
        }

        // multiply & subtract (SIGNED Int128 borrow propagation)
        var carry: Int128 = 0
        var i = 0
        while i < n {
            let prod = qhat &* vn[i].toDw()       // DWord, < 2^128
            let prodHi = prod >> 64
            let prodLo = prod & DWord(UInt64.max)
            let unIJ = un[j + i].toDw()
            let t = Int128(bitPattern: unIJ) &- Int128(bitPattern: prodLo) &- carry
            un[j + i] = Limb(truncatingIfNeeded: t)
            carry = Int128(bitPattern: prodHi) &- (t >> 64)   // arithmetic shift
            i += 1
        }
        let t = Int128(bitPattern: un[jn].toDw()) &- carry
        un[jn] = Limb(truncatingIfNeeded: t)
        if let q {
            let borrow: Int128 = t < 0 ? 1 : 0
            q[j] = Limb(truncatingIfNeeded: Int128(bitPattern: qhat) &- borrow)
        }
        if t < 0 {
            var c2: DWord = 0
            var i2 = 0
            while i2 < n {
                let sum = un[j + i2].toDw() &+ vn[i2].toDw() &+ c2
                un[j + i2] = sum.toLimb()
                c2 = sum >> 64
                i2 += 1
            }
            un[j + n] = un[j + n] &+ Limb(truncatingIfNeeded: c2)
        }
        j -= 1
    }
}

// ============================================================================
// PHASE 1 REMAINING: MagiaSqr.kt (615 lines) — squaring, used by pow.
// ============================================================================
