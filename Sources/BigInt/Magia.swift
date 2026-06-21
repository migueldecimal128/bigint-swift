// SPDX-License-Identifier: MIT
//
// Port of Magia.kt — the low-level **unsigned** arbitrary-precision limb
// engine. Magnitudes are little-endian 32-bit limbs.
//
// MEMORY MODEL (work order §6.1): in Kotlin `typealias Magia = IntArray` and the
// engine is ~2000 lines of free functions that write into a passed `IntArray`
// in place. Swift has no signed-Int-as-unsigned idiom worth keeping, so:
//
//   * limbs are native `UInt32` (`Limb`);
//   * `Magia` is a `final class` wrapping `ContiguousArray<Limb>` — reference
//     semantics give us in-place mutation through a passed reference AND O(1)
//     read-only sharing, exactly like Kotlin's `IntArray`. Aliased operands
//     (`z === x`) work because they are the same object.
//
// TRANSLITERATION CHEAT-SHEET (Kotlin → Swift), see PORTING_CONVENTIONS.md:
//   x[i].toDws()  →  x[i].toDws()      (Limb → Int64, zero-extended)
//   dw32(n)       →  dw32(n)           (Limb → UInt64, zero-extended)
//   t.toInt()     →  t.toLimb()        (low 32 bits → Limb)        [store]
//   t.toInt()     →  t.toInt32()       (low 32 bits → Int32)       [sign math]
//   x ushr n      →  x.ushr(n)         (LOGICAL right shift)
//   x shr n       →  x >> n            (arithmetic right shift on signed)
//   Long          →  Int64,   ULong  → UInt64,  Int(packed) → Int32
//   IntArray.size →  Magia.size  (capacity, NOT logical length)

import Foundation

typealias Limb = UInt32

/// `Magia` == MAGnitude array. Reference-type little-endian 32-bit limb buffer.
final class Magia {
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
}

// MARK: - scalar helpers / conversions

@inline(__always) func bitLen(_ n: Int32) -> Int { 32 - Int(n.leadingZeroBitCount) }

let MASK32: UInt64 = 0xFFFF_FFFF
let MASK32L: Int64 = 0xFFFF_FFFF

/// The one true zero-length array, usually used to represent ZERO.
/// `nonisolated(unsafe)`: a shared, never-mutated singleton (size 0).
nonisolated(unsafe) let MAGIA_ZERO = Magia(0)

/// The value ONE.  **WARNING** do NOT mutate this.
/// `nonisolated(unsafe)`: shared singleton, must not be mutated (as in Kotlin).
nonisolated(unsafe) let MAGIA_ONE = Magia(limbs: [1])

/// Returns the 32-bit limb `n` zero-extended to a 64-bit `UInt64`.
@inline(__always) func dw32(_ n: Limb) -> UInt64 { UInt64(n) }

extension Limb { // UInt32
    /// Kotlin `Int.toDws()` / `UInt.toDws()` — zero-extend a limb to a signed
    /// double word (`Long`).
    @inline(__always) func toDws() -> Int64 { Int64(self) }
}

extension Int64 {
    /// Kotlin `Long ushr n` — LOGICAL right shift on a signed 64-bit value.
    @inline(__always) func ushr(_ n: Int) -> Int64 {
        Int64(bitPattern: UInt64(bitPattern: self) >> UInt64(n))
    }
    /// Kotlin `Long.toInt()` truncated into a limb.
    @inline(__always) func toLimb() -> Limb { Limb(truncatingIfNeeded: self) }
    /// Kotlin `Long.toInt()` as a signed Int32 (for sign-mask arithmetic).
    @inline(__always) func toInt32() -> Int32 { Int32(truncatingIfNeeded: self) }
}

extension UInt64 {
    /// Kotlin `ULong.toInt()` truncated into a limb.
    @inline(__always) func toLimb() -> Limb { Limb(truncatingIfNeeded: self) }
}

extension Int32 {
    /// Kotlin `Int ushr n` — LOGICAL right shift on a signed 32-bit value.
    @inline(__always) func ushr(_ n: Int32) -> Int32 {
        Int32(bitPattern: UInt32(bitPattern: self) >> UInt32(n))
    }
}

/// Largest allowed limb-array length (2²⁶−1), so bitLength = len*32 < Int32.max.
let MAX_ALLOC_SIZE = (1 << 26) - 1

/// First limb of `x` as a `Limb` (0 if empty).
func toRawUInt(_ x: Magia) -> Limb { x.size == 0 ? 0 : x[0] }

/// Low 64 bits of the magnitude as `UInt64` (uses up to the first two limbs).
func toRawULong(_ x: Magia, _ xNormLen: Int) -> UInt64 {
    switch xNormLen {
    case 0: return 0
    case 1: return dw32(x[0])
    default: return (UInt64(x[1]) << 32) | dw32(x[0])
    }
}

/// First two limbs as `UInt64`, no bounds/normalization checks.
@inline(__always) func toRawULongExact(_ x: Magia) -> UInt64 {
    (UInt64(x[1]) << 32) | dw32(x[0])
}

/// Stores `dw` into `z` as little-endian limbs; returns the limb length (0–2).
func setULong(_ z: Magia, _ dw: UInt64) -> Int {
    let lo = dw.toLimb()
    let hi = (dw >> 32).toLimb()
    if dw == 0 { return 0 }
    z[0] = lo
    if hi == 0 { return 1 }
    z[1] = hi
    return 2
}

// MARK: - normalized length

/// Highest non-zero limb index + 1 over the whole array (0 if all zero).
/// WARNING: only safe on `new`-allocated magia (picks up garbage upper limbs).
func normLen(_ x: Magia) -> Int {
    var i = x.size
    while true {
        i -= 1
        if i < 0 { break }
        if x[i] != 0 { return i + 1 }
    }
    return 0
}

/// Highest non-zero limb index + 1 within the first `xLen` limbs.
func normLen(_ x: Magia, _ xLen: Int) -> Int {
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
func normLen(_ x: Magia, _ xOff: Int, _ xLen: Int) -> Int {
    if xOff < 0 || xLen < 0 || xOff + xLen > x.size { throwBoundsCheckViolation_Int() }
    var i = xLen
    while true {
        i -= 1
        if i < 0 { break }
        if x[xOff + i] != 0 { return i + 1 }
    }
    return 0
}

func isNormalized(_ x: Magia, _ xLen: Int) -> Bool {
    verify(xLen >= 0 && xLen <= x.size)
    return xLen == 0 || x[xLen - 1] != 0
}

func isNormalized(_ x: Magia, _ xOff: Int, _ xLen: Int) -> Bool {
    verify(xOff >= 0 && xLen >= 0 && xOff + xLen <= x.size)
    return xLen == 0 || x[xOff + xLen - 1] != 0
}

// MARK: - allocation

/// Limbs needed to hold `bitLen` bits (Kotlin `(bitLen + 0x1F) ushr 5`).
@inline(__always) func limbLenFromBitLen(_ bitLen: Int) -> Int { (bitLen + 0x1F) >> 5 }

func newWithBitLen(_ bitLen: Int) -> Magia {
    if bitLen >= 1 && bitLen <= MAX_ALLOC_SIZE * 32 {
        return Magia(limbLenFromBitLen(bitLen))
    }
    if bitLen == 0 {
        return MAGIA_ZERO
    }
    throwInvalidAllocationLength_Magia()
}

func newWithFloorLen(_ floorLen: Int) -> Magia {
    Magia(calcHeapLimbQuantum(floorLen))
}

/// Allocation size ≥ max(4, floorLen) rounded up to a multiple of 4.
@inline(__always) func calcHeapLimbQuantum(_ floorLen: Int) -> Int {
    if floorLen >= 0 && floorLen <= MAX_ALLOC_SIZE - 3 {
        // if floorLen == 0 then add 1  (Kotlin: floorLen + 1 - (-floorLen ushr 31))
        let t = floorLen + 1 - (floorLen > 0 ? 1 : 0)
        let allocSize = (t + 3) & ~3
        return allocSize
    }
    throwInvalidAllocationLength_Int()
}

func newCopyWithExactBitLen(_ x: Magia, _ xLen: Int, _ exactBitLen: Int) -> Magia {
    newCopyWithExactLimbLen(x, xLen, (exactBitLen + 0x1F) >> 5)
}

func newCopyWithExactLimbLen(_ x: Magia, _ xLen: Int, _ exactLimbLen: Int) -> Magia {
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
func mutAdd32(_ x: Magia, _ xNormLen: Int, _ w: Limb) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size {
        if w == 0 { return xNormLen }
        var carry = w.toDws()
        var i = 0
        while i < xNormLen {
            let t = x[i].toDws() + carry
            x[i] = t.toLimb()
            carry = t.ushr(32)
            if carry == 0 { return xNormLen }
            i += 1
        }
        if i < x.size {
            verify(carry != 0)
            x[i] = carry.toLimb()
            i += 1
            verify(isNormalized(x, i))
            return i
        }
        throwAddOverflow()
    }
    throwBoundsCheckViolation()
}

/// `x += dw` in place; returns new normalized length.
func mutAdd64(_ x: Magia, _ xNormLen: Int, _ dw: UInt64) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size {
        if dw == 0 { return xNormLen }
        var carry = Int64(bitPattern: dw)
        var i = 0
        while i < xNormLen {
            let t = x[i].toDws() + (carry & MASK32L)
            x[i] = t.toLimb()
            carry = carry.ushr(32) + t.ushr(32)
            if carry == 0 { return xNormLen }
            i += 1
        }
        if i < x.size {
            verify(carry != 0)
            x[i] = carry.toLimb()
            i += 1
            carry = carry.ushr(32)
            if carry == 0 {
                verify(isNormalized(x, i))
                return i
            }
            if i < x.size {
                x[i] = carry.toLimb()
                verify(isNormalized(x, i + 1))
                return i + 1
            }
        }
        throwAddOverflow()
    }
    throwBoundsCheckViolation()
}

/// `x += y` in place; returns new normalized length.
func mutAdd(_ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    verify(isNormalized(x, xNormLen))
    verify(isNormalized(y, yNormLen))
    if xNormLen > 0 && xNormLen <= x.size && yNormLen > 0 && yNormLen <= y.size {
        let maxNormLen = max(xNormLen, yNormLen)
        if maxNormLen <= x.size {
            // Pre-copy any hi limbs from y that extend beyond x
            if yNormLen > xNormLen {
                y.copyInto(x, xNormLen, xNormLen, yNormLen)
            }
            let minNormLen = min(xNormLen, yNormLen)
            var carry: Int64 = 0
            var i = 0
            repeat {
                let t = x[i].toDws() + y[i].toDws() + carry
                x[i] = t.toLimb()
                carry = t.ushr(32)
                i += 1
            } while i < minNormLen
            if carry == 0 { return maxNormLen }
            while i < maxNormLen {
                let t = x[i].toDws() + carry
                x[i] = t.toLimb()
                carry = t.ushr(32)
                if carry == 0 { return maxNormLen }
                i += 1
            }
            if carry != 0 {
                verify(i == maxNormLen && i < x.size)
                x[i] = 1
                i += 1
            }
            verify(isNormalized(x, i))
            return i
        }
    }
    throwBoundsCheckViolation_Int()
}

// MARK: - sub

/// `x -= w` in place (requires x ≥ w); returns new normalized length.
func mutSub32(_ x: Magia, _ xNormLen: Int, _ w: Limb) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size {
        var borrow = w.toDws()
        var i = 0
        while i < xNormLen {
            if borrow == 0 { return xNormLen }
            borrow = x[i].toDws() - borrow
            x[i] = borrow.toLimb()
            borrow = borrow.ushr(63)
            i += 1
        }
        if borrow == 0 {
            // The last limb might have become zero
            let zNormLen = xNormLen - (x[xNormLen - 1] == 0 ? 1 : 0)
            verify(isNormalized(x, zNormLen))
            return zNormLen
        }
        throwSubUnderflow_Int()
    }
    throwBoundsCheckViolation_Int()
}

/// `x -= dw` in place (requires x ≥ dw); returns new normalized length.
func mutSub64(_ x: Magia, _ xNormLen: Int, _ dw: UInt64) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size {
        var borrow = Int64(bitPattern: dw)
        var i = 0
        while i < xNormLen {
            if borrow == 0 { return xNormLen }
            let t = x[i].toDws() - (borrow & MASK32L)
            x[i] = t.toLimb()
            let carryOut = t.ushr(63)        // 1 if borrow-in consumed more than limb
            borrow = borrow.ushr(32) + carryOut
            i += 1
        }
        if borrow == 0 {
            var zNormLen = xNormLen
            if zNormLen > 0 && x[zNormLen - 1] == 0 {
                zNormLen -= 1
                if zNormLen > 0 && x[zNormLen - 1] == 0 {
                    zNormLen -= 1
                }
            }
            verify(isNormalized(x, zNormLen))
            return zNormLen
        }
        throwSubUnderflow_Int()
    }
    throwBoundsCheckViolation_Int()
}

/// `x -= y` in place (requires x ≥ y); returns new normalized length.
func mutSub(_ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    verify(isNormalized(x, xNormLen))
    verify(isNormalized(y, yNormLen))
    if xNormLen > 0 && xNormLen <= x.size && yNormLen > 0 && yNormLen <= y.size {
        if xNormLen >= yNormLen {
            var borrow: Int64 = 0
            var i = 0
            repeat {
                let t = x[i].toDws() - y[i].toDws() - borrow
                x[i] = t.toLimb()
                borrow = t.ushr(63)
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
                verify(isNormalized(x, zNormLen))
                return zNormLen
            }
            while i < xNormLen {
                let t = x[i].toDws() - borrow
                x[i] = t.toLimb()
                borrow = t.ushr(63)
                if borrow == 0 {
                    let zNormLen = xNormLen - (x[xNormLen - 1] == 0 ? 1 : 0)
                    verify(isNormalized(x, zNormLen))
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
func setSub(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size && yNormLen >= 0 && yNormLen <= y.size {
        verify(isNormalized(x, xNormLen))
        verify(isNormalized(y, yNormLen))
        if z.size >= xNormLen {
            if xNormLen >= yNormLen {
                var borrow: Int64 = 0
                var lastNonZeroIndex = -1
                var i = 0
                while i < yNormLen {
                    let t = x[i].toDws() - y[i].toDws() - borrow
                    let zi = t.toInt32()
                    z[i] = Limb(bitPattern: zi)
                    let nonZeroMask = Int((zi | (0 &- zi)) >> 31)
                    lastNonZeroIndex = (lastNonZeroIndex & ~nonZeroMask) | (i & nonZeroMask)
                    borrow = t.ushr(63)
                    i += 1
                }
                while i < xNormLen {
                    let t = x[i].toDws() - borrow
                    let zi = t.toInt32()
                    z[i] = Limb(bitPattern: zi)
                    let nonZeroMask = Int((zi | (0 &- zi)) >> 31)
                    lastNonZeroIndex = (lastNonZeroIndex & ~nonZeroMask) | (i & nonZeroMask)
                    borrow = t.ushr(63)
                    i += 1
                }
                if borrow == 0 {
                    let zNormLen = lastNonZeroIndex + 1
                    verify(isNormalized(z, zNormLen))
                    return zNormLen
                }
            }
            throwSubUnderflow()
        }
    }
    throwBoundsCheckViolation()
}

// ============================================================================
// PHASE 1 REMAINING (port in source order from Magia.kt; ~50 funcs):
//   setMul32/64, setMul, setMulSchoolbook, mutateFmaPow10,
//   setShiftRight/Left, isPowerOfTwo, bitLen(Magia)×2, normBitLen,
//   nonZeroNormBitLen, bitLengthBigIntegerStyle, ctz,
//   setAnd/setOr/setXor, testBit, testAnyBitInLowerN, extractULongAtBitIndex,
//   EQ×2, compare×2, setDiv32, setDivKnuth64, trySetDivFastPath(64),
//   calcRem32/64, setDivKnuth, setRem64, setRem, trySetRemFastPath, …
// Then MagiaSqr.kt.
// ============================================================================
