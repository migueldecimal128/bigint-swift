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
//   x[i].toDws()  →  x[i].toDw()       (Limb → UInt64, zero-extended)
//   dw32(n)       →  dw32(n)           (Limb → UInt64, zero-extended)
//   t.toInt()     →  t.toLimb()        (low 32 bits → Limb)        [store]
//   t.toInt()     →  t.toInt32()       (low 32 bits → Int32)       [sign math]
//   a + b / a * b →  a &+ b / a &* b   (WRAPPING; mirror Kotlin two's-complement)
//   x ushr n      →  x >> n            (dwords are UInt64 → `>>` IS logical)
//   Long          →  UInt64 (unsigned magnitudes), Int(packed) → Int32
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

@inline(__always) func bitLen(_ n: Int32) -> Int { 32 - Int(n.leadingZeroBitCount) }

let MASK32: UInt64 = 0xFFFF_FFFF

/// The one true zero-length array, usually used to represent ZERO.
/// `nonisolated(unsafe)`: a shared, never-mutated singleton (size 0).
nonisolated(unsafe) let MAGIA_ZERO = Magia(0)

/// The value ONE.  **WARNING** do NOT mutate this.
/// `nonisolated(unsafe)`: shared singleton, must not be mutated (as in Kotlin).
nonisolated(unsafe) let MAGIA_ONE = Magia(limbs: [1])

/// Returns the 32-bit limb `n` zero-extended to a 64-bit `UInt64`.
@inline(__always) func dw32(_ n: Limb) -> UInt64 { UInt64(n) }

extension Limb { // UInt32
    /// Kotlin `Int.toDw()` / `UInt.toDw()` — zero-extend a limb to a dword.
    /// We use UNSIGNED `UInt64` (not Kotlin's signed `Long`); `>>` is then
    /// logical, matching Kotlin's `ushr`. See PORTING_CONVENTIONS.md.
    @inline(__always) func toDw() -> UInt64 { UInt64(self) }
}

extension UInt64 {
    /// Kotlin `.toInt()` truncated into a limb.
    @inline(__always) func toLimb() -> Limb { Limb(truncatingIfNeeded: self) }
    /// Kotlin `.toInt()` as a signed Int32 (for sign-mask arithmetic).
    @inline(__always) func toInt32() -> Int32 { Int32(truncatingIfNeeded: self) }
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
        var carry = w.toDw()
        var i = 0
        while i < xNormLen {
            let t = x[i].toDw() &+ carry
            x[i] = t.toLimb()
            carry = t >> 32
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
        var carry = dw
        var i = 0
        while i < xNormLen {
            let t = x[i].toDw() &+ (carry & MASK32)
            x[i] = t.toLimb()
            carry = carry >> 32 &+ t >> 32
            if carry == 0 { return xNormLen }
            i += 1
        }
        if i < x.size {
            verify(carry != 0)
            x[i] = carry.toLimb()
            i += 1
            carry = carry >> 32
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
            var carry: UInt64 = 0
            var i = 0
            repeat {
                let t = x[i].toDw() &+ y[i].toDw() &+ carry
                x[i] = t.toLimb()
                carry = t >> 32
                i += 1
            } while i < minNormLen
            if carry == 0 { return maxNormLen }
            while i < maxNormLen {
                let t = x[i].toDw() &+ carry
                x[i] = t.toLimb()
                carry = t >> 32
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
        var borrow = w.toDw()
        var i = 0
        while i < xNormLen {
            if borrow == 0 { return xNormLen }
            borrow = x[i].toDw() &- borrow
            x[i] = borrow.toLimb()
            borrow = borrow >> 63
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
        var borrow = dw
        var i = 0
        while i < xNormLen {
            if borrow == 0 { return xNormLen }
            let t = x[i].toDw() &- (borrow & MASK32)
            x[i] = t.toLimb()
            let carryOut = t >> 63        // 1 if borrow-in consumed more than limb
            borrow = borrow >> 32 &+ carryOut
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
            var borrow: UInt64 = 0
            var i = 0
            repeat {
                let t = x[i].toDw() &- y[i].toDw() &- borrow
                x[i] = t.toLimb()
                borrow = t >> 63
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
                let t = x[i].toDw() &- borrow
                x[i] = t.toLimb()
                borrow = t >> 63
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
                var borrow: UInt64 = 0
                var lastNonZeroIndex = -1
                var i = 0
                while i < yNormLen {
                    let t = x[i].toDw() &- y[i].toDw() &- borrow
                    let zi = t.toInt32()
                    z[i] = Limb(bitPattern: zi)
                    let nonZeroMask = Int((zi | (0 &- zi)) >> 31)
                    lastNonZeroIndex = (lastNonZeroIndex & ~nonZeroMask) | (i & nonZeroMask)
                    borrow = t >> 63
                    i += 1
                }
                while i < xNormLen {
                    let t = x[i].toDw() &- borrow
                    let zi = t.toInt32()
                    z[i] = Limb(bitPattern: zi)
                    let nonZeroMask = Int((zi | (0 &- zi)) >> 31)
                    lastNonZeroIndex = (lastNonZeroIndex & ~nonZeroMask) | (i & nonZeroMask)
                    borrow = t >> 63
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

// MARK: - mul
//
// NOTE: dwords are UInt64. A limb*limb product is ≤ (2^32-1)^2 < 2^64 and the
// schoolbook accumulator stays ≤ 2^64-1, so no overflow occurs. WRAPPING
// operators `&*` / `&+` are used per the uniform policy (mirror Kotlin
// two's-complement, never trap); `>> 32` reads the high word (logical on UInt64).

/// `z = x * w`; safe in place (z may === x). Returns normalized length.
func setMul32(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ w: Limb) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size {
        verify(isNormalized(x, xNormLen))
        if xNormLen > 0 && w.nonzeroBitCount > 1 {
            let dws = w.toDw()
            var carry: UInt64 = 0
            var i = 0
            while i < xNormLen {
                let t = x[i].toDw() &* dws &+ carry
                z[i] = t.toLimb()
                carry = t >> 32
                i += 1
            }
            if carry != 0 {
                if i >= z.size { throwMulOverflow() }
                z[i] = carry.toLimb()
                i += 1
            }
            verify(isNormalized(z, i))
            return i
        }
        if xNormLen == 0 || w == 0 { return 0 }
        return setShiftLeft(z, x, xNormLen, Int(w.trailingZeroBitCount))
    }
    throwBoundsCheckViolation()
}

/// `z = x * dw`; does not overwrite x. Returns normalized length.
func setMul64(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ dw: UInt64) -> Int {
    if (dw >> 32) == 0 {
        return setMul32(z, x, xNormLen, Limb(truncatingIfNeeded: dw))
    }
    if xNormLen >= 0 && xNormLen <= x.size {
        verify(isNormalized(x, xNormLen))
        if xNormLen > 0 && dw.nonzeroBitCount > 1 {
            let dws = dw
            let lo = dws & MASK32
            let hi = dws >> 32

            var ppPrevHi: UInt64 = 0

            var i = 0
            while i < xNormLen {
                let xi = x[i].toDw()

                let pp = xi &* lo &+ (ppPrevHi & MASK32)
                z[i] = pp.toLimb()

                ppPrevHi = xi &* hi &+ ppPrevHi >> 32 &+ pp >> 32
                i += 1
            }
            if ppPrevHi != 0 && i < z.size {
                z[i] = ppPrevHi.toLimb()
                ppPrevHi = ppPrevHi >> 32
                i += 1
                if ppPrevHi != 0 && i < z.size {
                    z[i] = ppPrevHi.toLimb()
                    ppPrevHi = ppPrevHi >> 32
                    i += 1
                }
            }
            if ppPrevHi == 0 {
                verify(isNormalized(z, i))
                return i
            }
            throwMulOverflow()
        }
        if xNormLen == 0 { return 0 }
        verify(dw.nonzeroBitCount == 1)
        return setShiftLeft(z, x, xNormLen, Int(dw.trailingZeroBitCount))
    }
    throwBoundsCheckViolation()
}

func setMul(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    setMulSchoolbook(z, x, xNormLen, y, yNormLen)
}

func setMulSchoolbook(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
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
            let cortoLimb = corto[i].toDw()
            var carry: UInt64 = 0
            for j in 0..<largoLen {
                let largoLimb = largo[j].toDw()
                carry = carry &+ cortoLimb &* largoLimb &+ z[i + j].toDw()
                z[i + j] = carry.toLimb()
                carry = carry >> 32
            }
            if i + largoLen < z.size {
                z[i + largoLen] = carry.toLimb()
            } else if carry != 0 {
                throwMulOverflow()
            }
        }
        var lastIndex = cortoLen + largoLen - 1
        // >= instead of == to help bounds check elimination
        if lastIndex >= z.size || z[lastIndex] == 0 { lastIndex -= 1 }
        let zNormLen = lastIndex + 1
        verify(isNormalized(z, zNormLen))
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
func mutateFmaPow10(_ x: Magia, _ xLen: Int, _ pow10: Int, _ a: Limb) {
    if pow10 >= 0 && pow10 <= 9 {
        let m64 = POW10[pow10]
        var carry = UInt64(a)
        for i in 0..<xLen {
            carry = carry &+ x[i].toDw() &* m64
            x[i] = carry.toLimb()
            carry = carry >> 32
        }
    } else {
        fatalError() // IllegalArgumentException
    }
}

// MARK: - shifts

/// `z = x >> bitCount`; safe in place (z may === x). Returns normalized length.
func setShiftRight(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ bitCount: Int) -> Int {
    precondition(bitCount >= 0 && xNormLen >= 0 && xNormLen <= x.size)
    verify(isNormalized(x, xNormLen))
    if xNormLen == 0 { return 0 }
    precondition(x[xNormLen - 1] != 0)
    let newBitLen = normBitLen(x, xNormLen) - bitCount
    if newBitLen <= 0 { return 0 }
    let zNormLen = (newBitLen + 0x1F) >> 5
    precondition(zNormLen <= z.size)
    let wordShift = bitCount >> 5
    let innerShift = bitCount & ((1 << 5) - 1)
    if innerShift != 0 {
        let iLast = zNormLen - 1
        for i in 0..<iLast {
            z[i] = (x[i + wordShift + 1] << (32 - innerShift)) | (x[i + wordShift] >> innerShift)
        }
        let srcIndex = iLast + wordShift + 1
        z[iLast] = (
            srcIndex < xNormLen
                ? (x[iLast + wordShift + 1] << (32 - innerShift))
                : 0
        ) | (x[iLast + wordShift] >> innerShift)
    } else {
        for i in 0..<zNormLen {
            z[i] = x[i + wordShift]
        }
    }
    verify(isNormalized(z, zNormLen))
    return zNormLen
}

/// `z = x << bitCount`; safe in place (z may === x). Returns normalized length.
func setShiftLeft(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ bitCount: Int) -> Int {
    verify(isNormalized(x, xNormLen))

    if xNormLen == 0 { return 0 }

    let xBitLen = normBitLen(x, xNormLen)

    let wordShift = bitCount >> 5
    let innerShift = bitCount & 31

    let zBitLen = xBitLen + bitCount
    let zNormLen = limbLenFromBitLen(zBitLen)

    if zNormLen > z.size { throwShlOverflow() }

    // Fast path: whole-limb shift only
    if innerShift == 0 {
        x.copyInto(z, wordShift, 0, xNormLen)
        z.fill(0, 0, wordShift)

        precondition(isNormalized(z, zNormLen))
        return zNormLen
    }

    // Non-zero inner shift: detect spill from top limb
    let top = x[xNormLen - 1]
    let spill = top >> (32 - innerShift)   // 0 if no spill

    // Write spill limb FIRST (important if z === x)
    if spill != 0 {
        z[zNormLen - 1] = spill
    }

    // Main shift loop: high → low (in-place safe)
    for src in stride(from: xNormLen - 1, through: 1, by: -1) {
        let dst = src + wordShift
        z[dst] = (x[src] << innerShift) | (x[src - 1] >> (32 - innerShift))
    }

    // lowest shifted limb
    z[wordShift] = x[0] << innerShift

    // clear lower limbs
    z.fill(0, 0, wordShift)

    verify(isNormalized(z, zNormLen))
    return zNormLen
}

// MARK: - bit queries

func isPowerOfTwo(_ x: Magia, _ xNormLen: Int) -> Bool {
    verify(isNormalized(x, xNormLen))
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

func bitLen(_ x: Magia) -> Int { bitLen(x, x.size) }

func bitLen(_ x: Magia, _ xLen: Int) -> Int {
    if xLen >= 0 && xLen <= x.size {
        var i = xLen - 1
        while i >= 0 {
            if x[i] != 0 {
                return 32 - Int(x[i].leadingZeroBitCount) + (i * 32)
            }
            i -= 1
        }
        return 0
    }
    throwBoundsCheckViolation()
}

func normBitLen(_ x: Magia, _ xLen: Int) -> Int {
    if xLen > 0 {
        let lastLimb = x[xLen - 1]
        verify(lastLimb != 0)
        return (xLen << 5) - Int(lastLimb.leadingZeroBitCount)
    }
    return 0
}

@inline(__always) func nonZeroNormBitLen(_ x: Magia, _ xLen: Int) -> Int {
    let lastLimb = x[xLen - 1]
    verify(lastLimb != 0)
    return (xLen << 5) - Int(lastLimb.leadingZeroBitCount)
}

/// Bit length using Java BigInteger semantics (two's-complement, minus sign bit).
func bitLengthBigIntegerStyle(_ sign: Bool, _ x: Magia, _ xNormLen: Int) -> Int {
    verify(isNormalized(x, xNormLen))
    if xNormLen >= 0 && xNormLen <= x.size {
        let bitLen = normBitLen(x, xNormLen)
        let isNegPowerOfTwo = sign && isPowerOfTwo(x, xNormLen)
        return bitLen - (isNegPowerOfTwo ? 1 : 0)
    }
    throwBoundsCheckViolation()
}

/// Count of trailing zero bits in the magnitude; -1 if zero.
func ctz(_ x: Magia, _ normLen: Int) -> Int {
    if normLen >= 0 && normLen <= x.size {
        for i in 0..<normLen {
            if x[i] != 0 {
                return (i << 5) + Int(x[i].trailingZeroBitCount)
            }
        }
        return -1
    }
    throwBoundsCheckViolation()
}

// MARK: - bitwise

/// `z = x AND y`; supports aliasing. Returns normalized length.
func setAnd(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size && yNormLen >= 0 && yNormLen <= y.size {
        verify(isNormalized(x, xNormLen))
        verify(isNormalized(y, yNormLen))
        let minLen = min(xNormLen, yNormLen)
        if minLen <= z.size {
            var i = minLen
            repeat {
                i -= 1
                if i < 0 { return 0 }
            } while (x[i] & y[i]) == 0
            let zNormLen = i + 1
            while i >= 0 {
                z[i] = x[i] & y[i]
                i -= 1
            }
            verify(isNormalized(z, zNormLen))
            return zNormLen
        }
    }
    throwBoundsCheckViolation()
}

/// `z = x OR y`; supports aliasing. Returns normalized length.
func setOr(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size && yNormLen >= 0 && yNormLen <= y.size {
        verify(isNormalized(x, xNormLen))
        verify(isNormalized(y, yNormLen))
        let maxLen = max(xNormLen, yNormLen)
        if maxLen <= z.size {
            let minLen = min(xNormLen, yNormLen)
            let zNormLen = maxLen
            for i in 0..<minLen {
                z[i] = x[i] | y[i]
            }
            if minLen < xNormLen {
                x.copyInto(z, minLen, minLen, xNormLen)
            } else if minLen < yNormLen {
                y.copyInto(z, minLen, minLen, yNormLen)
            }
            verify(isNormalized(z, zNormLen))
            return zNormLen
        }
    }
    throwBoundsCheckViolation()
}

/// `z = x XOR y`; supports aliasing. Returns normalized length.
func setXor(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size && yNormLen >= 0 && yNormLen <= y.size {
        verify(isNormalized(x, xNormLen))
        verify(isNormalized(y, yNormLen))
        let maxLen = max(xNormLen, yNormLen)
        if maxLen <= z.size {
            let minLen = min(xNormLen, yNormLen)
            for i in 0..<minLen {
                z[i] = x[i] ^ y[i]
            }
            let zNormLen: Int
            if minLen < xNormLen {
                x.copyInto(z, minLen, minLen, xNormLen)
                zNormLen = xNormLen
            } else if minLen < yNormLen {
                y.copyInto(z, minLen, minLen, yNormLen)
                zNormLen = yNormLen
            } else {
                zNormLen = normLen(z, minLen)
            }
            verify(isNormalized(z, zNormLen))
            return zNormLen
        }
    }
    throwBoundsCheckViolation()
}

// MARK: - bit tests / extraction

func testBit(_ x: Magia, _ xLen: Int, _ bitIndex: Int) -> Bool {
    if xLen >= 0 && xLen <= x.size {
        let wordIndex = bitIndex >> 5
        if wordIndex >= xLen { return false }
        let word = x[wordIndex]
        let bitMask: Limb = 1 << (bitIndex & 0x1F)
        return (word & bitMask) != 0
    }
    throwBoundsCheckViolation()
}

func testAnyBitInLowerN(_ x: Magia, _ xLen: Int, _ bitCount: Int) -> Bool {
    if xLen >= 0 && xLen <= x.size {
        let lastBitIndex = bitCount - 1
        let lastWordIndex = lastBitIndex >> 5
        for i in 0..<lastWordIndex {
            if i == xLen { return false }
            if x[i] != 0 { return true }
        }
        if lastWordIndex == xLen { return false }
        // -1 ushr (31 - r)  →  low (r+1) bits set
        let bitMask: Limb = Limb.max >> (0x1F - (lastBitIndex & 0x1F))
        return (x[lastWordIndex] & bitMask) != 0
    }
    throwBoundsCheckViolation()
}

/// `(x >> bitIndex) mod 2^64`. Reads up to three limbs.
func extractULongAtBitIndex(_ x: Magia, _ xNormLen: Int, _ bitIndex: Int) -> UInt64 {
    if bitIndex >= 0 {
        let loLimb = bitIndex >> 5
        let innerShift = bitIndex & 0x1F
        if bitIndex == 0 { return toRawULong(x, xNormLen) }
        if loLimb >= xNormLen { return 0 }
        let lo = UInt64(x[loLimb])
        if (loLimb + 1) == xNormLen { return lo >> innerShift }
        let mid = UInt64(x[loLimb + 1])
        if (loLimb + 2) == xNormLen || innerShift == 0 { return ((mid << 32) | lo) >> innerShift }
        let hi = UInt64(x[loLimb + 2])
        return (hi << (64 - innerShift)) | (mid << (32 - innerShift)) | (lo >> innerShift)
    }
    throwNegBitIndex()
}

// MARK: - compare / equality

/// `true` if the normalized magnitude `x` equals the single value `y` (bit pattern).
func EQ(_ x: Magia, _ xNormLen: Int, _ y: Int32) -> Bool {
    xNormLen == 1 && x[0] == Limb(bitPattern: y)
}

func EQ(_ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Bool {
    compare(x, xNormLen, y, yNormLen) == 0
}

/// Unsigned compare: -1 if x < y, 0 if equal, 1 if x > y.
func compare(_ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    verify(isNormalized(x, xNormLen))
    verify(isNormalized(y, yNormLen))
    if xNormLen >= 0 && xNormLen <= x.size && yNormLen >= 0 && yNormLen <= y.size {
        if xNormLen != yNormLen {
            return ((xNormLen - yNormLen) >> 31) | 1
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
func compare(_ x: Magia, _ xNormLen: Int, _ dw: UInt64) -> Int {
    verify(isNormalized(x, xNormLen))
    if xNormLen >= 0 && xNormLen <= x.size {
        if xNormLen > 2 { return 1 }
        let xv = toRawULong(x, xNormLen)
        return xv < dw ? -1 : (xv > dw ? 1 : 0)
    }
    throwBoundsCheckViolation()
}

// MARK: - division / remainder
//
// Division uses UInt64 for the quotient ESTIMATE (qhat/rhat — unsigned division,
// native in Swift) and SIGNED Int64 for the multiply-and-subtract BORROW
// propagation, which relies on an arithmetic `t >> 32` of a negative
// intermediate (Kotlin flags this explicitly). The Kotlin setDiv32/calcRem32
// signed-vs-unsigned two-path split was only a JVM unsigned-division workaround;
// here it collapses to one UInt64 path.

/// `z = x / w`; supports in place. Returns normalized length.
func setDiv32(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ w: Limb) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size && z.size >= xNormLen {
        verify(isNormalized(x, xNormLen))
        if w == 0 { throwDivByZero_Int() }
        if xNormLen == 0 { return 0 }
        if w.nonzeroBitCount == 1 {
            return setShiftRight(z, x, xNormLen, Int(w.trailingZeroBitCount))
        }
        let dw = UInt64(w)
        var carry: UInt64 = 0
        var i = xNormLen - 1
        while i >= 0 {
            let t = (carry << 32) | x[i].toDw()
            z[i] = (t / dw).toLimb()
            carry = t % dw
            i -= 1
        }
        let zNormLen = xNormLen - (z[xNormLen - 1] == 0 ? 1 : 0)
        verify(isNormalized(z, zNormLen))
        return zNormLen
    }
    throwBoundsCheckViolation()
}

/// `z = x / dw`; quotient via Knuth-64. Returns normalized length.
func setDivKnuth64(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ unBuf: Magia?, _ dw: UInt64) -> Int {
    if xNormLen >= 0 && xNormLen <= x.size && z.size >= xNormLen - 2 + 1 {
        verify(isNormalized(x, xNormLen))
        let qNormLen = Int(knuthDivide64(z, nil, x, dw, xNormLen, unBuf))
        verify(isNormalized(z, qNormLen))
        return qNormLen
    }
    throwBadKnuthArgument()
}

/// Fast paths for `x / y`. Writes quotient to z and returns its length, or -1.
func trySetDivFastPath(_ zMagia: Magia, _ xMagia: Magia, _ xNormLen: Int, _ yMagia: Magia, _ yNormLen: Int) -> Int {
    if yNormLen == 0 { throwDivByZero_Int() }
    if xNormLen == 0 { return 0 }
    if xNormLen < yNormLen { return 0 }
    if xNormLen <= 2 {
        return setULong(zMagia, toRawULong(xMagia, xNormLen) / toRawULong(yMagia, yNormLen))
    }
    if yNormLen == 1 {
        return setDiv32(zMagia, xMagia, xNormLen, yMagia[0])
    }
    if isPowerOfTwo(yMagia, yNormLen) {
        return setShiftRight(zMagia, xMagia, xNormLen, ctz(yMagia, yNormLen))
    }
    // note that this also handles aliasing when x === y
    if xNormLen == yNormLen {
        let xBitLen = normBitLen(xMagia, xNormLen)
        let yBitLen = normBitLen(yMagia, yNormLen)
        if xBitLen < yBitLen { return 0 }
        if xBitLen == yBitLen {
            let cmp = compare(xMagia, xNormLen, yMagia, yNormLen)
            if cmp < 0 { return 0 }
            zMagia[0] = 1
            return 1
        }
    }
    return -1
}

func trySetDivFastPath64(_ zMagia: Magia, _ xMagia: Magia, _ xNormLen: Int, _ yDw: UInt64) -> Int {
    if (yDw >> 32) == 0 {
        return setDiv32(zMagia, xMagia, xNormLen, Limb(truncatingIfNeeded: yDw))
    }
    if xNormLen < 2 { return 0 }
    if xNormLen == 2 {
        return setULong(zMagia, ((UInt64(xMagia[1]) << 32) | UInt64(xMagia[0])) / yDw)
    }
    if yDw.nonzeroBitCount == 1 {
        return setShiftRight(zMagia, xMagia, xNormLen, Int(yDw.trailingZeroBitCount))
    }
    return -1
}

/// `x mod w` as a single limb.
func calcRem32(_ x: Magia, _ xNormLen: Int, _ w: Limb) -> Limb {
    if xNormLen >= 0 && xNormLen <= x.size {
        verify(isNormalized(x, xNormLen))
        if w == 0 { throwDivByZero() }
        if xNormLen <= 2 {
            switch xNormLen {
            case 2:
                let xDw = (UInt64(x[1]) << 32) | x[0].toDw()
                return Limb(truncatingIfNeeded: xDw % UInt64(w))
            case 1:
                return x[0] % w
            default:
                return 0
            }
        }
        if w.nonzeroBitCount == 1 {
            return x[0] & ((Limb(1) << w.trailingZeroBitCount) - 1)
        }
        let dw = UInt64(w)
        var carry: UInt64 = 0
        var i = xNormLen - 1
        while i >= 0 {
            let t = (carry << 32) | x[i].toDw()
            carry = t % dw
            i -= 1
        }
        return Limb(truncatingIfNeeded: carry)
    }
    throwBoundsCheckViolation()
}

/// `x mod dw` as a 64-bit value.
func calcRem64(_ x: Magia, _ xNormLen: Int, _ unBuf: Magia?, _ dw: UInt64) -> UInt64 {
    if xNormLen >= 0 && xNormLen <= x.size {
        verify(isNormalized(x, xNormLen))
        if (dw >> 32) == 0 {
            return UInt64(calcRem32(x, xNormLen, Limb(truncatingIfNeeded: dw)))
        }
        if xNormLen <= 2 {
            switch xNormLen {
            case 2:
                let xDw = (UInt64(x[1]) << 32) | x[0].toDw()
                return xDw % dw
            case 1:
                return UInt64(x[0])
            default:
                return 0
            }
        }
        if dw.nonzeroBitCount == 1 {
            return ((UInt64(x[1]) << 32) | UInt64(x[0])) & ((UInt64(1) << dw.trailingZeroBitCount) - 1)
        }
        return knuthDivide64(nil, nil, x, dw, xNormLen, unBuf)
    }
    throwBoundsCheckViolation()
}

/// `z = x / y` via Knuth (z is the quotient). xTmp/yTmp optional scratch.
func setDivKnuth(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ xTmp: Magia?,
                 _ y: Magia, _ yNormLen: Int, _ yTmp: Magia?) -> Int {
    verify(isNormalized(x, xNormLen))
    verify(isNormalized(y, yNormLen))
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
    if yNormLen > 2 {
        let qNormLen = knuthDivide(q, r, u, v, m, n, xTmp, yTmp)
        verify(isNormalized(q, qNormLen))
        return qNormLen
    }
    verify(yNormLen == 2)
    let vDw: UInt64 = (UInt64(v[1]) << 32) | v[0].toDw()
    let qNormLen = Int(knuthDivide64(q, r, u, vDw, m, xTmp))
    verify(isNormalized(q, qNormLen))
    return qNormLen
}

func setRem64(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ dw: UInt64) -> Int {
    verify(isNormalized(x, xNormLen))
    if (dw >> 32) == 0 {
        let rem = calcRem32(x, xNormLen, Limb(truncatingIfNeeded: dw))
        let z0 = rem
        z[0] = z0
        return Int((z0 | (0 &- z0)) >> 31)
    }
    if xNormLen == 0 { return 0 }
    if xNormLen <= 2 { return setULong(z, toRawULong(x, xNormLen) % dw) }
    return setRem(z, x, xNormLen, Magia(limbs: [dw.toLimb(), (dw >> 32).toLimb()]), 2)
}

/// `z = x mod y`. Returns normalized length of the remainder.
func setRem(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ y: Magia, _ yNormLen: Int) -> Int {
    verify(isNormalized(x, xNormLen))
    verify(isNormalized(y, yNormLen))
    let rLen0 = trySetRemFastPath(z, x, xNormLen, y, yNormLen)
    if rLen0 >= 0 { return rLen0 }
    let n = yNormLen
    let m = xNormLen
    let u = x
    let v = y
    let q: Magia? = nil
    if z.size < yNormLen { throwBoundsCheckViolation() }
    let r = z
    let rNormLen = knuthDivide(q, r, u, v, m, n)
    verify(rNormLen <= n)
    verify(isNormalized(r, rNormLen))
    return rNormLen
}

func trySetRemFastPath(_ zMagia: Magia, _ xMagia: Magia, _ xNormLen: Int, _ yMagia: Magia, _ yNormLen: Int) -> Int {
    if yNormLen == 0 { throwDivByZero() }
    if xNormLen < yNormLen {
        xMagia.copyInto(zMagia, 0, 0, xNormLen)
        return xNormLen
    }
    if yNormLen == 2 && xNormLen <= 2 {
        return setULong(zMagia, toRawULong(xMagia, xNormLen) % toRawULong(yMagia, yNormLen))
    }
    if yNormLen == 1 {
        return setRem64(zMagia, xMagia, xNormLen, UInt64(yMagia[0]))
    }
    // note that this also handles aliasing when x === y
    if xNormLen == yNormLen {
        let xBitLen = normBitLen(xMagia, xNormLen)
        let yBitLen = normBitLen(yMagia, yNormLen)
        if xBitLen < yBitLen {
            xMagia.copyInto(zMagia, 0, 0, xNormLen)
            verify(isNormalized(zMagia, xNormLen))
            return xNormLen
        }
        if xBitLen == yBitLen {
            let cmp = compare(xMagia, xNormLen, yMagia, yNormLen)
            if cmp < 0 {
                xMagia.copyInto(zMagia, 0, 0, xNormLen)
                verify(isNormalized(zMagia, xNormLen))
                return xNormLen
            }
            if cmp == 0 { return 0 }
            return setSub(zMagia, xMagia, xNormLen, yMagia, yNormLen)
        }
    }
    return -1
}

/// `z = x mod y` via Knuth (z is the remainder). xTmp/yTmp optional scratch.
func setRem(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ xTmp: Magia?,
            _ y: Magia, _ yNormLen: Int, _ yTmp: Magia?) -> Int {
    verify(isNormalized(x, xNormLen))
    verify(isNormalized(y, yNormLen))
    verify(xTmp == nil || xTmp!.size >= xNormLen + 1)
    verify(yTmp == nil || yTmp!.size >= yNormLen)
    if xNormLen < yNormLen || yNormLen < 2 { fatalError() }
    let m = xNormLen
    let n = yNormLen
    let u = x
    let v = y
    if z.size < yNormLen { fatalError() }
    let r = z
    if yNormLen > 2 {
        let rNormLen = knuthDivide(nil, r, u, v, m, n, xTmp, yTmp)
        verify(isNormalized(z, rNormLen))
        return rNormLen
    }
    verify(yNormLen == 2)
    let vDw: UInt64 = (UInt64(v[1]) << 32) | v[0].toDw()
    let rNormLen = Int(knuthDivide64(nil, r, u, vDw, m, xTmp))
    verify(isNormalized(z, rNormLen))
    return rNormLen
}

// MARK: - Knuth Algorithm D (base 2^32)

/// Multi-word division. q (length ≥ m-n+1) or nil; r (length ≥ n) or nil.
/// Returns qNormLen if q != nil, rNormLen if r != nil, else -1.
func knuthDivide(_ q: Magia?, _ r: Magia?, _ u: Magia, _ v: Magia, _ m: Int, _ n: Int,
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
        _ = setShiftLeft(vn, vn, n, shift)
        _ = setShiftLeft(un, un, m, shift)
    }

    knuthDivideNormalizedCore(q, un, vn, m, n)

    var rNormLen = 0
    if let r {
        rNormLen = setShiftRight(r, un, normLen(un, m + 1), shift)
    }

    if let q { return normLen(q, m - n + 1) }
    if r != nil { return rNormLen }
    return -1
}

/// Core of Knuth division; `un` is side-effected and holds the remainder.
func knuthDivideNormalizedCore(_ q: Magia?, _ un: Magia, _ vn: Magia, _ m: Int, _ n: Int) {
    if m < n || n < 2 || vn[n - 1] < 0x8000_0000 { fatalError() }   // top limb must be normalized (hi bit set)

    let vn_1 = dw32(vn[n - 1])
    let vn_2 = dw32(vn[n - 2])

    var j = m - n
    while j >= 0 {
        let jn = j + n
        let jn1 = jn - 1
        let jn2 = jn - 2
        // estimate q̂ = (un[j+n]*B + un[j+n-1]) / vn[n-1]
        let hi = dw32(un[jn])
        let lo = dw32(un[jn1])
        let num = (hi << 32) | lo
        var qhat = num / vn_1
        var rhat = num &- (qhat &* vn_1)

        let un_j = dw32(un[jn2])
        while (qhat >> 32) != 0 || qhat &* vn_2 > (rhat << 32) &+ un_j {
            qhat &-= 1
            rhat = rhat &+ vn_1
            if (rhat >> 32) != 0 { break }
        }

        // multiply & subtract (SIGNED Int64 borrow propagation)
        var carry: Int64 = 0
        var i = 0
        while i < n {
            let prod = qhat &* vn[i].toDw()       // UInt64, < 2^64
            let prodHi = prod >> 32
            let prodLo = prod & MASK32
            let unIJ = un[j + i].toDw()
            let t = Int64(bitPattern: unIJ) &- Int64(bitPattern: prodLo) &- carry
            un[j + i] = Limb(truncatingIfNeeded: t)
            carry = Int64(bitPattern: prodHi) &- (t >> 32)   // arithmetic shift
            i += 1
        }
        let t = Int64(bitPattern: un[jn].toDw()) &- carry
        un[jn] = Limb(truncatingIfNeeded: t)
        if let q {
            let borrow: Int64 = t < 0 ? 1 : 0
            q[j] = Limb(truncatingIfNeeded: Int64(bitPattern: qhat) &- borrow)
        }
        if t < 0 {
            var c2: UInt64 = 0
            var i2 = 0
            while i2 < n {
                let sum = un[j + i2].toDw() &+ vn[i2].toDw() &+ c2
                un[j + i2] = sum.toLimb()
                c2 = sum >> 32
                i2 += 1
            }
            un[j + n] = un[j + n] &+ Limb(truncatingIfNeeded: c2)
        }
        j -= 1
    }
}

/// Divides a multi-limb integer by a 64-bit divisor (wrapper over Knuth).
/// Returns qNormLen if q != nil, rNormLen if r != nil, else the 64-bit remainder.
func knuthDivide64(_ q: Magia?, _ r: Magia?, _ u: Magia, _ vDw: UInt64, _ m: Int, _ unBuf: Magia?) -> UInt64 {
    if m < 2 || (vDw >> 32) == 0 { fatalError() }

    let un: Magia
    if let unBuf {
        if unBuf.size < m + 1 { fatalError() }
        un = unBuf
    } else if let r, r.size >= m + 1 {
        un = r
    } else {
        un = Magia(m + 1)
    }
    u.copyInto(un, 0, 0, m)
    un[m] = 0
    let shift = Int(vDw.leadingZeroBitCount)
    let vnDw = vDw << shift

    if shift > 0 {
        _ = setShiftLeft(un, un, m, shift)
    }

    knuthDivideNormalizedCore64(q, un, vnDw, m)

    var rNormLen = 0
    if let r {
        rNormLen = setShiftRight(r, un, normLen(un, m + 1), shift)
    }

    if let q { return UInt64(normLen(q, m - 2 + 1)) }
    if r != nil { return UInt64(rNormLen) }
    // caller wants the remainder as a UInt64
    let un0 = UInt64(un[0])
    let un1 = UInt64(un[1])
    let un2 = UInt64(un[2])
    if shift > 0 {
        return (un2 << (64 - shift)) | (un1 << (32 - shift)) | (un0 >> shift)
    } else {
        return (un1 << 32) | un0
    }
}

func knuthDivideNormalizedCore64(_ q: Magia?, _ un: Magia, _ vnDw: UInt64, _ m: Int) {
    if m < 2 || (vnDw >> 63) != 1 { fatalError() }

    let vn1 = vnDw >> 32
    let vn0 = vnDw & MASK32

    var j = m - 2
    while j >= 0 {
        let j1 = j + 1
        let j2 = j + 2
        let hi = dw32(un[j2])
        let lo = dw32(un[j1])
        let num = (hi << 32) | lo
        var qhat = num / vn1
        var rhat = num &- (qhat &* vn1)

        let un_j = dw32(un[j])
        while (qhat >> 32) != 0 || qhat &* vn0 > (rhat << 32) &+ un_j {
            qhat &-= 1
            rhat = rhat &+ vn1
            if (rhat >> 32) != 0 { break }
        }

        // multiply & subtract (SIGNED Int64), unrolled for n = 2
        var carry: Int64 = 0
        // i = 0
        do {
            let prod = qhat &* vn0
            let prodHi = prod >> 32
            let prodLo = prod & MASK32
            let t0 = Int64(bitPattern: un_j) &- Int64(bitPattern: prodLo) &- carry
            un[j] = Limb(truncatingIfNeeded: t0)
            carry = Int64(bitPattern: prodHi) &- (t0 >> 32)
        }
        // i = 1
        do {
            let prod = qhat &* vn1
            let prodHi = prod >> 32
            let prodLo = prod & MASK32
            let un1v = un[j1].toDw()
            let t1 = Int64(bitPattern: un1v) &- Int64(bitPattern: prodLo) &- carry
            un[j1] = Limb(truncatingIfNeeded: t1)
            carry = Int64(bitPattern: prodHi) &- (t1 >> 32)
        }
        let t = Int64(bitPattern: un[j2].toDw()) &- carry
        un[j2] = Limb(truncatingIfNeeded: t)
        if let q {
            let borrow: Int64 = t < 0 ? 1 : 0
            q[j] = Limb(truncatingIfNeeded: Int64(bitPattern: qhat) &- borrow)
        }
        if t < 0 {
            var c2: UInt64 = 0
            do {
                let sum0 = un[j].toDw() &+ vn0 &+ c2
                un[j] = sum0.toLimb()
                c2 = sum0 >> 32
            }
            do {
                let sum1 = un[j1].toDw() &+ vn1 &+ c2
                un[j1] = sum1.toLimb()
                c2 = sum1 >> 32
            }
            un[j2] = un[j2] &+ Limb(truncatingIfNeeded: c2)
        }
        j -= 1
    }
}

// ============================================================================
// PHASE 1 REMAINING: MagiaSqr.kt (615 lines) — squaring, used by pow.
// ============================================================================
