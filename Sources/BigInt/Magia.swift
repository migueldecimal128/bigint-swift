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

// ============================================================================
// PHASE 1 REMAINING (port in source order from Magia.kt):
//   setAnd/setOr/setXor, testBit, testAnyBitInLowerN, extractULongAtBitIndex,
//   EQ×2, compare×2, setDiv32, setDivKnuth64, trySetDivFastPath(64),
//   calcRem32/64, setDivKnuth, setRem64, setRem, trySetRemFastPath, …
//   (Magia.kt lines 1138-2075). Then MagiaSqr.kt.
// ============================================================================
