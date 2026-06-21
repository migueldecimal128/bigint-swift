// SPDX-License-Identifier: MIT
//
// Port of MagiaSqr.kt — squaring kernels (unrolled small cases, schoolbook,
// Karatsuba). All dword math is UInt64 with wrapping operators per policy. The
// only borrow (kmutSub) uses the UInt64 wrapped-borrow `>> 63` pattern.
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
    case 2: return setSqr2Limbs(z, x)
    case 3: return setSqr3Limbs(z, x)
    case 4: return setSqr4Limbs(z, x)
    case ..<SCHOOLBOOK_SQR_THRESHOLD:
        // doubling overhead overwhelms simple multiply for a while
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
        var carry: UInt64 = 0
        for j in (i + 1)..<xNormLen {
            let k = i + j
            let t = ai &* magia_dw32(x[xOff + j]) &+ magia_dw32(z[zOff + k]) &+ carry
            z[zOff + k] = t.toLimb()
            carry = t >> 32
        }
        z[zOff + i + xNormLen] = carry.toLimb()
    }

    // 2) Double the cross terms: z = z * 2 (linear scan)
    var shiftCarry: UInt64 = 0
    for i in 0..<zLen {
        let zi = magia_dw32(z[zOff + i])
        let t = (zi << 1) | shiftCarry
        z[zOff + i] = t.toLimb()
        shiftCarry = t >> 32
    }

    // 3) Diagonals: add a[i]^2 into column 2*i
    for i in 0..<xNormLen {
        var k = 2 * i
        let zk = magia_dw32(z[zOff + k])
        let ai = magia_dw32(x[xOff + i])
        let sqa = ai &* ai &+ zk

        z[zOff + k] = sqa.toLimb()
        k += 1
        var carry = magia_dw32(z[zOff + k]) &+ (sqa >> 32)
        z[zOff + k] = carry.toLimb()
        carry = carry >> 32
        k += 1

        while carry != 0 && k < zLen {
            carry = magia_dw32(z[zOff + k]) &+ carry
            z[zOff + k] = carry.toLimb()
            carry = carry >> 32
            k += 1
        }
    }

    let lastIndex = zLen - 1
    let lastLimb = z[zOff + lastIndex]
    let zNormLen = lastIndex + Int((lastLimb | (0 &- lastLimb)) >> 31)
    return zNormLen
}

private func setSqr1Limb(_ z: Magia, _ a: Magia) -> Int {
    let dw = UInt64(a[0])
    let sq = dw &* dw
    let hi = sq >> 32
    z[1] = hi.toLimb()
    z[0] = sq.toLimb()
    return hi == 0 ? 1 : 2
}

private func setSqr2Limbs(_ z: Magia, _ a: Magia) -> Int {
    let dw = (UInt64(a[1]) << 32) | UInt64(a[0])
    let sqLo = dw &* dw
    let sqHi = unsignedMulHi(dw, dw)
    let hiLimb = (sqHi >> 32).toLimb()
    z[3] = hiLimb
    z[2] = sqHi.toLimb()
    z[1] = (sqLo >> 32).toLimb()
    z[0] = sqLo.toLimb()
    return hiLimb == 0 ? 3 : 4
}

private func setSqr3Limbs(_ z: Magia, _ a: Magia) -> Int {
    let a0 = magia_dw32(a[0]), a1 = magia_dw32(a[1]), a2 = magia_dw32(a[2])

    let s0 = a0 &* a0
    let s1 = a1 &* a1
    let s2 = a2 &* a2
    let c01 = a0 &* a1
    let c02 = a0 &* a2
    let c12 = a1 &* a2

    var carry = s0 >> 32
    z[0] = s0.toLimb()

    // column 1: 2*c01 + carry
    do {
        var lo = carry
        var hi: UInt64 = 0
        let dLo = c01 << 1
        let dHi = c01 >> 63
        let old = lo; lo = lo &+ dLo
        if lo < old { hi = hi &+ 1 }
        hi = hi &+ dHi
        z[1] = lo.toLimb()
        carry = (lo >> 32) &+ (hi << 32)
    }
    // column 2: s1 + 2*c02 + carry
    do {
        var lo = carry
        var hi: UInt64 = 0
        var old = lo; lo = lo &+ s1
        if lo < old { hi = hi &+ 1 }
        let dLo = c02 << 1
        let dHi = c02 >> 63
        old = lo; lo = lo &+ dLo
        if lo < old { hi = hi &+ 1 }
        hi = hi &+ dHi
        z[2] = lo.toLimb()
        carry = (lo >> 32) &+ (hi << 32)
    }
    // column 3: 2*c12 + carry
    do {
        var lo = carry
        var hi: UInt64 = 0
        let dLo = c12 << 1
        let dHi = c12 >> 63
        let old = lo; lo = lo &+ dLo
        if lo < old { hi = hi &+ 1 }
        hi = hi &+ dHi
        z[3] = lo.toLimb()
        carry = (lo >> 32) &+ (hi << 32)
    }
    // column 4: s2 + carry
    do {
        let t = carry &+ s2
        z[4] = t.toLimb()
        z[5] = (t >> 32).toLimb()
    }

    return z[5] == 0 ? 5 : 6
}

private func setSqr4Limbs(_ z: Magia, _ a: Magia) -> Int {
    let a0 = magia_dw32(a[0]), a1 = magia_dw32(a[1])
    let a2 = magia_dw32(a[2]), a3 = magia_dw32(a[3])

    let s0 = a0 &* a0, s1 = a1 &* a1, s2 = a2 &* a2, s3 = a3 &* a3
    let c01 = a0 &* a1, c02 = a0 &* a2, c03 = a0 &* a3
    let c12 = a1 &* a2, c13 = a1 &* a3, c23 = a2 &* a3

    z[0] = s0.toLimb()
    var carry = s0 >> 32

    // column 1: 2*c01 + carry
    do {
        var lo = carry; var hi: UInt64 = 0
        let dLo = c01 << 1; let dHi = c01 >> 63
        let old = lo; lo = lo &+ dLo
        if lo < old { hi = hi &+ 1 }; hi = hi &+ dHi
        z[1] = lo.toLimb(); carry = (lo >> 32) &+ (hi << 32)
    }
    // column 2: s1 + 2*c02 + carry
    do {
        var lo = carry; var hi: UInt64 = 0
        var old = lo; lo = lo &+ s1
        if lo < old { hi = hi &+ 1 }
        let dLo = c02 << 1; let dHi = c02 >> 63
        old = lo; lo = lo &+ dLo
        if lo < old { hi = hi &+ 1 }; hi = hi &+ dHi
        z[2] = lo.toLimb(); carry = (lo >> 32) &+ (hi << 32)
    }
    // column 3: 2*c03 + 2*c12 + carry
    do {
        var lo = carry; var hi: UInt64 = 0
        var dLo = c03 << 1; var dHi = c03 >> 63
        var old = lo; lo = lo &+ dLo
        if lo < old { hi = hi &+ 1 }; hi = hi &+ dHi
        dLo = c12 << 1; dHi = c12 >> 63
        old = lo; lo = lo &+ dLo
        if lo < old { hi = hi &+ 1 }; hi = hi &+ dHi
        z[3] = lo.toLimb(); carry = (lo >> 32) &+ (hi << 32)
    }
    // column 4: s2 + 2*c13 + carry
    do {
        var lo = carry; var hi: UInt64 = 0
        var old = lo; lo = lo &+ s2
        if lo < old { hi = hi &+ 1 }
        let dLo = c13 << 1; let dHi = c13 >> 63
        old = lo; lo = lo &+ dLo
        if lo < old { hi = hi &+ 1 }; hi = hi &+ dHi
        z[4] = lo.toLimb(); carry = (lo >> 32) &+ (hi << 32)
    }
    // column 5: 2*c23 + carry
    do {
        var lo = carry; var hi: UInt64 = 0
        let dLo = c23 << 1; let dHi = c23 >> 63
        let old = lo; lo = lo &+ dLo
        if lo < old { hi = hi &+ 1 }; hi = hi &+ dHi
        z[5] = lo.toLimb(); carry = (lo >> 32) &+ (hi << 32)
    }
    // columns 6 & 7: s3 + carry
    let t = carry &+ s3
    z[6] = t.toLimb()
    let z7 = (t >> 32).toLimb()
    z[7] = z7
    return z7 == 0 ? 7 : 8
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
    let zNormLen = zLastIndex + Int((zLastLimb | (0 &- zLastLimb)) >> 31)
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

    var carry: UInt64 = 0
    for i in 0..<k0 {
        let tmp = magia_dw32(a[aOff + i]) &+ magia_dw32(a[a1Off + i]) &+ carry
        t[i] = tmp.toLimb()
        carry = tmp >> 32
    }
    if k0 < k1 {
        let tmp = magia_dw32(a[a1Off + k0]) &+ carry
        t[k0] = tmp.toLimb()
        carry = tmp >> 32
    }
    t[k1] = carry.toLimb()
}

func magia_kmutSub(_ t: Magia, _ s2Off: Int, _ z: Magia, _ xOff: Int, _ xLen: Int) {
    let start = s2Off
    let end = start + xLen

    if start < 0 || end > t.size || xOff < 0 || xOff + xLen > z.size {
        fatalError("kmutSub OOB")
    }

    var borrow: UInt64 = 0
    for i in 0..<xLen {
        let tIdx = start + i
        let zIdx = xOff + i
        let tmp = magia_dw32(t[tIdx]) &- magia_dw32(z[zIdx]) &- borrow
        t[tIdx] = tmp.toLimb()
        borrow = tmp >> 63
    }

    var k = end
    while borrow != 0 {
        if k >= t.size {
            // Borrow escaping t means (a0+a1)^2 < a0^2 + a1^2 — impossible.
            fatalError("Borrow escaped t.size in Karatsuba squaring")
        }
        let tmp = magia_dw32(t[k]) &- borrow
        t[k] = tmp.toLimb()
        borrow = tmp >> 63
        k += 1
    }
}

func magia_kmutAddShifted(_ z: Magia, _ zOff: Int, _ t: Magia, _ z1Off: Int, _ z1Len: Int, _ k0Shift: Int) {
    let start = zOff + k0Shift
    let end = start + z1Len

    if start < 0 || end > z.size || z1Off < 0 || z1Off + z1Len > t.size {
        fatalError()
    }

    var carry: UInt64 = 0
    for i in 0..<z1Len {
        let tmp = magia_dw32(z[start + i]) &+ magia_dw32(t[z1Off + i]) &+ carry
        z[start + i] = tmp.toLimb()
        carry = tmp >> 32
    }

    var k = end
    while carry != 0 && k < z.size {
        let tmp = magia_dw32(z[k]) &+ carry
        z[k] = tmp.toLimb()
        carry = tmp >> 32
        k += 1
    }
}
