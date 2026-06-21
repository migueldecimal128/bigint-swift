// SPDX-License-Identifier: MIT
//
// Port of MagiaSqr.kt — squaring kernels (schoolbook, Karatsuba). All dword math
// is DWord (UInt128) with wrapping operators per policy. The only borrow
// (kmutSub) uses the DWord wrapped-borrow `>> 127` (sign-bit) pattern.
//
// 64-bit limb note (BigIntSwift64BitLimbWorkOrder.md §4 Phase 4): the
// hand-unrolled setSqr2/3/4Limbs were bit-for-bit derived for 32-bit limbs and
// are dropped here (de-risk option); those sizes fall back to the general
// multiply/squaring path. Re-add 128-bit-diagonal unrolls later if measured.
//
// Kotlin's file-private `dw32(n: Int)` is the same as Magia.swift's global
// `magia_dw32(_: Limb)`, so we reuse the global.

let KARATSUBA_SQR_THRESHOLD = 84
let SCHOOLBOOK_SQR_THRESHOLD = 12

/// Squares `x[0..<xNormLen)` into `z` (requires z.size ≥ 2*xNormLen).
func magia_setSqr(_ z: Magia, _ x: Magia, _ xNormLen: Int) -> Int {
    switch xNormLen {
    case 0: return 0
    case 1: return setSqr1Limb(z, x)
    case ..<SCHOOLBOOK_SQR_THRESHOLD:
        // doubling overhead overwhelms simple multiply for a while; also covers
        // the small sizes whose 32-bit unrolls were dropped in the 64-bit port
        return magia_setMulSchoolbook(z, x, xNormLen, x, xNormLen)
    default:
        return magia_setSqrSchoolbook(z, 0, x, 0, xNormLen)
    }
}

func magia_setSqrSchoolbook(_ z: Magia, _ x: Magia, _ xNormLen: Int) -> Int {
    magia_setSqrSchoolbook(z, 0, x, 0, xNormLen)
}

/// Squares `x[xOff..<xOff+xNormLen)` into `z[zOff..<zOff+2*xNormLen)`.
func magia_setSqrSchoolbook(_ z: Magia, _ zOff: Int, _ x: Magia, _ xOff: Int, _ xNormLen: Int) -> Int {
    if xNormLen == 0 { return 0 }
    let zLen = 2 * xNormLen
    precondition(zOff >= 0 && zOff + zLen <= z.size)
    z.fill(0, zOff, zOff + zLen)

    precondition(xOff >= 0 && xOff + xNormLen <= x.size)
    // 1) Cross terms i < j
    for i in 0..<(xNormLen - 1) {
        let ai = magia_dw32(x[xOff + i])
        var carry: DWord = 0
        for j in (i + 1)..<xNormLen {
            let k = i + j
            let t = ai &* magia_dw32(x[xOff + j]) &+ magia_dw32(z[zOff + k]) &+ carry
            z[zOff + k] = t.toLimb()
            carry = t >> 64
        }
        z[zOff + i + xNormLen] = carry.toLimb()
    }

    // 2) Double the cross terms: z = z * 2 (linear scan)
    var shiftCarry: DWord = 0
    for i in 0..<zLen {
        let zi = magia_dw32(z[zOff + i])
        let t = (zi << 1) | shiftCarry
        z[zOff + i] = t.toLimb()
        shiftCarry = t >> 64
    }

    // 3) Diagonals: add a[i]^2 into column 2*i
    for i in 0..<xNormLen {
        var k = 2 * i
        let zk = magia_dw32(z[zOff + k])
        let ai = magia_dw32(x[xOff + i])
        let sqa = ai &* ai &+ zk

        z[zOff + k] = sqa.toLimb()
        k += 1
        var carry = magia_dw32(z[zOff + k]) &+ (sqa >> 64)
        z[zOff + k] = carry.toLimb()
        carry = carry >> 64
        k += 1

        while carry != 0 && k < zLen {
            carry = magia_dw32(z[zOff + k]) &+ carry
            z[zOff + k] = carry.toLimb()
            carry = carry >> 64
            k += 1
        }
    }

    let lastIndex = zLen - 1
    let lastLimb = z[zOff + lastIndex]
    let zNormLen = lastIndex + Int((lastLimb | (0 &- lastLimb)) >> 63)
    return zNormLen
}

private func setSqr1Limb(_ z: Magia, _ a: Magia) -> Int {
    // One 64-bit limb squared is a 128-bit (2-limb) result.
    let p = a[0].toDw() &* a[0].toDw()
    let hi = (p >> 64).toLimb()
    z[1] = hi
    z[0] = p.toLimb()
    return hi == 0 ? 1 : 2
}

/// Squares `x[0..<xNormLen)` with Karatsuba (requires z.size ≥ 2*xNormLen+1).
func magia_setSqrKaratsuba(_ z: Magia, _ x: Magia, _ xNormLen: Int, _ tmp: Magia? = nil) -> Int {
    let k1 = (xNormLen + 1) / 2
    let tmpSize = 3 * k1 + 3
    verify(z.size >= 2 * xNormLen + 1)
    verify(tmp == nil || tmp!.size >= tmpSize)
    let t = tmp ?? Magia(tmpSize)
    magia_karatsubaSqr(z, 0, x, 0, xNormLen, t)
    let zLastIndex = 2 * xNormLen - 1
    let zLastLimb = z[zLastIndex]
    let zNormLen = zLastIndex + Int((zLastLimb | (0 &- zLastLimb)) >> 63)
    return zNormLen
}

func magia_karatsubaSqr(_ z: Magia, _ zOff: Int, _ a: Magia, _ aOff: Int, _ aLen: Int, _ t: Magia) {
    if aLen < KARATSUBA_SQR_THRESHOLD {
        _ = magia_setSqrSchoolbook(z, zOff, a, aOff, aLen)
        return
    }

    let n = aLen
    let k0 = n / 2
    let k1 = n - k0
    precondition(zOff >= 0 && zOff + 2 * n <= z.size)
    precondition(t.size >= (3 * k1 + 3))

    // square lo half of a into z as z0
    magia_karatsubaSqr(z, zOff, a, aOff, k0, t)
    // square hi half of a into z as z1
    magia_karatsubaSqr(z, zOff + 2 * k0, a, aOff + k0, k1, t)
    // add a0 and a1 as s into t
    magia_ksetAdd(t, a, aOff, k0, k1)
    // square s to s2 higher in t
    _ = magia_setSqrSchoolbook(t, k1 + 1, t, 0, k1 + 1)
    // subtract z0 from s2
    let z1Off = k1 + 1
    magia_kmutSub(t, z1Off, z, zOff, 2 * k0)
    // subtract z2 from s2
    magia_kmutSub(t, z1Off, z, zOff + 2 * k0, 2 * k1)
    // add shifted s2 as z1 into z
    let z1FullLen = 2 * (k1 + 1)
    magia_kmutAddShifted(z, zOff, t, z1Off, z1FullLen, k0)
}

func magia_ksetAdd(_ t: Magia, _ a: Magia, _ aOff: Int, _ k0: Int, _ k1: Int) {
    let a1Off = aOff + k0
    let a1End = aOff + k0 + k1

    if k0 < 0 || k1 < k0 || aOff < 0 || a1Off > a.size || a1End > a.size || k1 >= t.size {
        fatalError()
    }

    var carry: DWord = 0
    for i in 0..<k0 {
        let tmp = magia_dw32(a[aOff + i]) &+ magia_dw32(a[a1Off + i]) &+ carry
        t[i] = tmp.toLimb()
        carry = tmp >> 64
    }
    if k0 < k1 {
        let tmp = magia_dw32(a[a1Off + k0]) &+ carry
        t[k0] = tmp.toLimb()
        carry = tmp >> 64
    }
    t[k1] = carry.toLimb()
}

func magia_kmutSub(_ t: Magia, _ s2Off: Int, _ z: Magia, _ xOff: Int, _ xLen: Int) {
    let start = s2Off
    let end = start + xLen

    if start < 0 || end > t.size || xOff < 0 || xOff + xLen > z.size {
        fatalError("kmutSub OOB")
    }

    var borrow: DWord = 0
    for i in 0..<xLen {
        let tIdx = start + i
        let zIdx = xOff + i
        let tmp = magia_dw32(t[tIdx]) &- magia_dw32(z[zIdx]) &- borrow
        t[tIdx] = tmp.toLimb()
        borrow = tmp >> 127
    }

    var k = end
    while borrow != 0 {
        if k >= t.size {
            // Borrow escaping t means (a0+a1)^2 < a0^2 + a1^2 — impossible.
            fatalError("Borrow escaped t.size in Karatsuba squaring")
        }
        let tmp = magia_dw32(t[k]) &- borrow
        t[k] = tmp.toLimb()
        borrow = tmp >> 127
        k += 1
    }
}

func magia_kmutAddShifted(_ z: Magia, _ zOff: Int, _ t: Magia, _ z1Off: Int, _ z1Len: Int, _ k0Shift: Int) {
    let start = zOff + k0Shift
    let end = start + z1Len

    if start < 0 || end > z.size || z1Off < 0 || z1Off + z1Len > t.size {
        fatalError()
    }

    var carry: DWord = 0
    for i in 0..<z1Len {
        let tmp = magia_dw32(z[start + i]) &+ magia_dw32(t[z1Off + i]) &+ carry
        z[start + i] = tmp.toLimb()
        carry = tmp >> 64
    }

    var k = end
    while carry != 0 && k < z.size {
        let tmp = magia_dw32(z[k]) &+ carry
        z[k] = tmp.toLimb()
        carry = tmp >> 64
        k += 1
    }
}
