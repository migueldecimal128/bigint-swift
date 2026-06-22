// SPDX-License-Identifier: MIT
//
// Port of MagiaSqr.kt — squaring kernels (schoolbook, Karatsuba). Limb products
// use `multipliedFullWidth(by:)` → (high, low) UInt64, and carries/borrows are
// single-bit `Limb`s threaded via addingReportingOverflow/subtractingReportingOverflow
// (likewise the Karatsuba add/sub helpers ksetAdd/kmutSub/kmutAddShifted). The
// cross-term doubling step (z = z·2) is a native single-bit-carry left shift.
//
// 64-bit limb note (BigIntSwift64BitLimbWorkOrder.md §4 Phase 4): the
// hand-unrolled setSqr2/3/4Limbs were bit-for-bit derived for 32-bit limbs and
// are dropped here (de-risk option); those sizes fall back to the general
// multiply/squaring path. Re-add 128-bit-diagonal unrolls later if measured.

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
        let ai = x[xOff + i]
        var carry: Limb = 0
        for j in (i + 1)..<xNormLen {
            let k = i + j
            let (hi, lo) = ai.multipliedFullWidth(by: x[xOff + j])
            let (s0, c0) = lo.addingReportingOverflow(z[zOff + k])
            let (s1, c1) = s0.addingReportingOverflow(carry)
            z[zOff + k] = s1
            carry = hi &+ (c0 ? 1 : 0) &+ (c1 ? 1 : 0)
        }
        z[zOff + i + xNormLen] = carry
    }

    // 2) Double the cross terms: z = z * 2 (linear scan, native shift)
    var shiftCarry: Limb = 0
    for i in 0..<zLen {
        let zi = z[zOff + i]
        z[zOff + i] = (zi << 1) | shiftCarry
        shiftCarry = zi >> 63
    }

    // 3) Diagonals: add a[i]^2 into column 2*i
    for i in 0..<xNormLen {
        var k = 2 * i
        let ai = x[xOff + i]
        let (sqHi, sqLo) = ai.multipliedFullWidth(by: ai)
        let (lo, cLo) = sqLo.addingReportingOverflow(z[zOff + k])
        z[zOff + k] = lo
        // high word of ai^2 + z[k]; sqHi ≤ 2^64-2 so this never wraps
        let sqaHi = sqHi &+ (cLo ? 1 : 0)
        k += 1

        let (s, c) = z[zOff + k].addingReportingOverflow(sqaHi)
        z[zOff + k] = s
        var carry: Limb = c ? 1 : 0
        k += 1

        while carry != 0 && k < zLen {
            let (s2, c2) = z[zOff + k].addingReportingOverflow(carry)
            z[zOff + k] = s2
            carry = c2 ? 1 : 0
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
    let (hi, lo) = a[0].multipliedFullWidth(by: a[0])
    z[1] = hi
    z[0] = lo
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

    var carry: Limb = 0
    for i in 0..<k0 {
        let (s0, c0) = a[aOff + i].addingReportingOverflow(a[a1Off + i])
        let (s1, c1) = s0.addingReportingOverflow(carry)
        t[i] = s1
        carry = (c0 ? 1 : 0) &+ (c1 ? 1 : 0)
    }
    if k0 < k1 {
        let (s, c) = a[a1Off + k0].addingReportingOverflow(carry)
        t[k0] = s
        carry = c ? 1 : 0
    }
    t[k1] = carry
}

func magia_kmutSub(_ t: Magia, _ s2Off: Int, _ z: Magia, _ xOff: Int, _ xLen: Int) {
    let start = s2Off
    let end = start + xLen

    if start < 0 || end > t.size || xOff < 0 || xOff + xLen > z.size {
        fatalError("kmutSub OOB")
    }

    var borrow: Limb = 0
    for i in 0..<xLen {
        let tIdx = start + i
        let zIdx = xOff + i
        let (d0, b0) = t[tIdx].subtractingReportingOverflow(z[zIdx])
        let (d1, b1) = d0.subtractingReportingOverflow(borrow)
        t[tIdx] = d1
        borrow = (b0 ? 1 : 0) &+ (b1 ? 1 : 0)
    }

    var k = end
    while borrow != 0 {
        if k >= t.size {
            // Borrow escaping t means (a0+a1)^2 < a0^2 + a1^2 — impossible.
            fatalError("Borrow escaped t.size in Karatsuba squaring")
        }
        let (d, b) = t[k].subtractingReportingOverflow(borrow)
        t[k] = d
        borrow = b ? 1 : 0
        k += 1
    }
}

func magia_kmutAddShifted(_ z: Magia, _ zOff: Int, _ t: Magia, _ z1Off: Int, _ z1Len: Int, _ k0Shift: Int) {
    let start = zOff + k0Shift
    let end = start + z1Len

    if start < 0 || end > z.size || z1Off < 0 || z1Off + z1Len > t.size {
        fatalError()
    }

    var carry: Limb = 0
    for i in 0..<z1Len {
        let (s0, c0) = z[start + i].addingReportingOverflow(t[z1Off + i])
        let (s1, c1) = s0.addingReportingOverflow(carry)
        z[start + i] = s1
        carry = (c0 ? 1 : 0) &+ (c1 ? 1 : 0)
    }

    var k = end
    while carry != 0 && k < z.size {
        let (s, c) = z[k].addingReportingOverflow(carry)
        z[k] = s
        carry = c ? 1 : 0
        k += 1
    }
}
