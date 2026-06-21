// SPDX-License-Identifier: MIT
//
// Port of MutableBigInt.kt — the mutable, allocation-reusing accumulator.
// Kotlin `class MutableBigInt : BigIntNumber` → `final class MutableBigInt:
// BigIntNumber` (work order §6.1): reference type with growable `magia` plus two
// reusable scratch buffers (tmp1/tmp2). Kotlin's base `_meta`/`_magia` become
// stored `var meta`/`var magia` here (the protocol requires only `{ get }`;
// a settable var satisfies it and lets this class mutate in place).
//
// This file currently covers: fields, constructors, the storage-management
// layer (resize/ensure/swap/hint), updateMeta, and the basic setters. The
// arithmetic set*/mut* operations are DEFERRED (marker at end).

// File-scope wrapper: the global `validateNormLenAndInjectPoison(_:_:)` is
// shadowed by the same-named BigIntNumber instance method inside this scope.
private func _validateNormLenAndInjectPoison(_ m: Magia, _ n: Int) -> Bool {
    validateNormLenAndInjectPoison(m, n)
}

final class MutableBigInt: BigIntNumber {
    var meta: Meta
    var magia: Magia
    var limbCapacityHint = 0
    var tmp1: Magia = MAGIA_ZERO
    var tmp2: Magia = MAGIA_ZERO

    private init(_ meta: Meta, _ magia: Magia) {
        self.meta = meta
        self.magia = magia
    }

    // MARK: constructors

    /// Empty (zero) accumulator.
    convenience init() {
        biStat(.MBI_CONSTRUCT_EMPTY)
        let m = Magia(4)
        verify(_validateNormLenAndInjectPoison(m, 0))
        self.init(Meta(0), m)
    }

    convenience init(_ n: Int32) { self.init(n < 0, UInt64(n.magnitude)) }
    convenience init(_ w: UInt32) { self.init(false, UInt64(w)) }
    convenience init(_ l: Int64) { self.init(l < 0, l.magnitude) }
    convenience init(_ dw: UInt64) { self.init(false, dw) }

    convenience init(_ sign: Bool, _ dwMag: UInt64) {
        biStat(.MBI_CONSTRUCT_PRIMITIVE)
        let m = Magia(4)
        m[0] = dwMag.toLimb()
        m[1] = (dwMag >> 32).toLimb()
        let normLen: Int32 = dwMag == 0 ? 0 : ((dwMag >> 32) == 0 ? 1 : 2)
        verify(_validateNormLenAndInjectPoison(m, Int(normLen)))
        self.init(Meta(signFlag: sign, normLen: normLen), m)
    }

    convenience init(_ other: BigIntNumber) {
        biStat(.MBI_CONSTRUCT_BI)
        let n = Int(other.meta.normLen)
        let m = newWithFloorLen(n)
        other.magia.copyInto(m, 0, 0, n)
        verify(_validateNormLenAndInjectPoison(m, n))
        self.init(other.meta, m)
    }

    /// Zero accumulator with limb storage preallocated for ≥ `initialBitCapacity` bits.
    static func withBitCapacityHint(_ initialBitCapacity: Int) -> MutableBigInt {
        if initialBitCapacity >= 0 {
            let initialLimbCapacity = max(4, limbLenFromBitLen(initialBitCapacity))
            let m = newWithFloorLen(initialLimbCapacity)
            verify(_validateNormLenAndInjectPoison(m, 0))
            let mbi = MutableBigInt(Meta(0), m)
            verify(mbi.magia.size >= 4)
            mbi.limbCapacityHint = mbi.magia.size
            biStat(.MBI_CONSTRUCT_CAPACITY_HINT)
            return mbi
        }
        fatalError()
    }

    private func validate() {
        precondition(
            Int(meta.normLen) <= magia.size &&
            magia.size >= 4 &&
            (meta.normLen == 0 || magia[Int(meta.normLen) - 1] != 0)
        )
    }

    // MARK: storage management
    //
    // The stat-bucket index math is replicated as readable equivalents:
    //   hintBit   = (-limbCapacityHint ushr 30) and 2   →  hint>0 ? 2 : 0
    //   repeatBit = (5 - magia.size) ushr 31            →  magia.size>5 ? 1 : 0

    private func resizeMagiaDiscard(_ requestedLimbLen: Int) {
        verify(requestedLimbLen > 4 && requestedLimbLen > magia.size)
        let hintBit = limbCapacityHint > 0 ? 2 : 0
        let repeatBit = magia.size > 5 ? 1 : 0
        BigIntStats.BI_OP_COUNTS[StatsOp.MBI_RESIZE_MAGIA.ordinal + (hintBit | repeatBit)] += 1
        let targetLimbLen = max(limbCapacityHint, requestedLimbLen)
        let headroom = (magia.size <= 4 || requestedLimbLen <= limbCapacityHint) ? 0 : (targetLimbLen >> 1)
        magia = newWithFloorLen(targetLimbLen + headroom)
    }

    private func resizeMagiaCopy(_ requestedLimbLen: Int) {
        let t = magia
        resizeMagiaDiscard(requestedLimbLen)
        t.copyInto(magia, 0, 0, Int(meta.normLen))
    }

    private func resizeTmp1(_ requestedLimbLen: Int, _ resizeOp: StatsOp) {
        verify(requestedLimbLen > tmp1.size)
        let hintBit = limbCapacityHint > 0 ? 2 : 0
        let repeatBit = magia.size > 5 ? 1 : 0
        BigIntStats.BI_OP_COUNTS[resizeOp.ordinal + hintBit + repeatBit] += 1
        let headRoom = tmp1.size > 5 ? (requestedLimbLen >> 1) : 0
        tmp1 = newWithFloorLen(requestedLimbLen + headRoom)
    }

    private func resizeTmp2(_ requestedLimbLen: Int, _ resizeOp: StatsOp) {
        verify(requestedLimbLen > tmp2.size)
        let hintBit = limbCapacityHint > 0 ? 2 : 0
        let repeatBit = magia.size > 5 ? 1 : 0
        BigIntStats.BI_OP_COUNTS[resizeOp.ordinal + hintBit + repeatBit] += 1
        let headRoom = tmp2.size > 0 ? (requestedLimbLen >> 1) : 0
        tmp2 = newWithFloorLen(requestedLimbLen + headRoom)
    }

    func ensureMagiaCapacityDiscard(_ requestedLimbLen: Int) {
        if magia.size < requestedLimbLen { resizeMagiaDiscard(requestedLimbLen) }
    }
    private func ensureMagiaCapacityCopy(_ minLimbLen: Int) {
        if magia.size < minLimbLen { resizeMagiaCopy(max(limbCapacityHint, minLimbLen)) }
    }
    func ensureMagiaCapacityCopyZeroExtend(_ newLimbLen: Int) {
        if newLimbLen <= magia.size {
            if newLimbLen > Int(meta.normLen) { magia.fill(0, Int(meta.normLen), newLimbLen) }
        } else {
            resizeMagiaCopy(max(limbCapacityHint, newLimbLen))
        }
    }
    func ensureMagiaBitCapacityDiscard(_ minBitLen: Int) {
        ensureMagiaCapacityDiscard((minBitLen + 0x1F) >> 5)
    }
    private func ensureMagiaBitCapacityCopy(_ minBitLen: Int) {
        ensureMagiaCapacityCopy((minBitLen + 0x1F) >> 5)
    }
    private func ensureTmp1Capacity(_ requestedLimbLen: Int, _ resizeOp: StatsOp) {
        if requestedLimbLen > tmp1.size { resizeTmp1(max(limbCapacityHint, requestedLimbLen), resizeOp) }
    }
    private func ensureTmp2Capacity(_ requestedLimbLen: Int, _ resizeOp: StatsOp) {
        if requestedLimbLen > tmp2.size { resizeTmp2(max(limbCapacityHint, requestedLimbLen), resizeOp) }
    }
    private func ensureTmp1CapacityZeroed(_ zeroedLimbLen: Int, _ resizeOp: StatsOp) {
        if zeroedLimbLen <= tmp1.size { tmp1.fill(0, 0, zeroedLimbLen) }
        else { resizeTmp1(zeroedLimbLen, resizeOp) }
    }
    private func swapTmp1() {
        verify(tmp1.size >= 4)
        let t = tmp1; tmp1 = magia; magia = t
    }
    private func swapTmp1Copy() {
        let t = tmp1; tmp1 = magia; magia = t
        tmp1.copyInto(magia, 0, 0, Int(meta.normLen))
    }

    func hintBitCapacity(_ bitCapacityHint: Int) -> MutableBigInt {
        if bitCapacityHint < 0 { fatalError() }
        limbCapacityHint = max(limbCapacityHint, calcHeapLimbQuantum((bitCapacityHint + 31) >> 5))
        return self
    }
    func currentLimbCapacityHint() -> Int { limbCapacityHint }
    func didExceedHint() -> Bool { magia.size > limbCapacityHint }
    func getHintBitCapacity() -> Int { limbCapacityHint * 32 }

    // MARK: meta / basic setters

    func updateMeta(_ meta: Meta) {
        self.meta = meta
        verify(validateNormLenAndInjectPoison())   // instance member (intended)
        verify(isNormalized())
    }

    @discardableResult func setZero() -> MutableBigInt { validate(); updateMeta(Meta(0)); return self }
    @discardableResult func setOne() -> MutableBigInt {
        validate()
        magia[0] = 1
        updateMeta(Meta(signBit: 0, normLen: 1))
        validate()
        return self
    }
    @discardableResult func mutAbs() -> MutableBigInt { updateMeta(meta.abs()); return self }
    @discardableResult func mutNegate() -> MutableBigInt { updateMeta(meta.negate()); return self }
    @discardableResult func mutWithSign(_ sign: Bool) -> MutableBigInt { updateMeta(meta.withSign(sign)); return self }

    @discardableResult func set(_ n: Int32) -> MutableBigInt { set(n < 0, UInt64(n.magnitude)) }
    @discardableResult func set(_ w: UInt32) -> MutableBigInt { set(false, UInt64(w)) }
    @discardableResult func set(_ l: Int64) -> MutableBigInt { set(l < 0, l.magnitude) }
    @discardableResult func set(_ dw: UInt64) -> MutableBigInt { set(false, dw) }
    @discardableResult func set(_ bi: BigIntNumber) -> MutableBigInt { set(bi.meta, bi.magia) }

    @discardableResult func set(_ sign: Bool, _ dw: UInt64) -> MutableBigInt {
        let normLen = (64 - Int(dw.leadingZeroBitCount) + 31) >> 5
        magia[0] = dw.toLimb()
        magia[1] = (dw >> 32).toLimb()
        updateMeta(Meta(signFlag: sign, normLen: Int32(normLen)))
        return self
    }

    @discardableResult func set(_ sign: Bool, _ dwHi: UInt64, _ dwLo: UInt64) -> MutableBigInt {
        let bitLen = dwHi == 0
            ? 64 - Int(dwLo.leadingZeroBitCount)
            : 128 - Int(dwHi.leadingZeroBitCount)
        let normLen = (bitLen + 0x1F) >> 5
        magia[0] = dwLo.toLimb()
        magia[1] = (dwLo >> 32).toLimb()
        magia[2] = dwHi.toLimb()
        magia[3] = (dwHi >> 32).toLimb()
        updateMeta(Meta(signFlag: sign, normLen: Int32(normLen)))
        return self
    }

    @discardableResult private func set(_ yMeta: Meta, _ y: Magia) -> MutableBigInt {
        ensureMagiaCapacityDiscard(Int(yMeta.normLen))
        if magia !== y { y.copyInto(magia, 0, 0, Int(yMeta.normLen)) }
        updateMeta(yMeta)
        return self
    }

    func toBigInt() -> BigInt { BigInt.from(self) }
}

// ============================================================================
// PHASE 2 REMAINING — MutableBigInt arithmetic (MutableBigInt.kt 712-1976):
//   setAdd/setSub (+ Impl32/64/Impl, mutAddImpl*), setMul (+Impl), setSqr,
//   karatsubaSetSqr, setPow/mutPow, setDiv (+Impl32/64, trySetDivFastPath*),
//   setRem (+Impl, trySetRemFastPath), setMod (+Impl), addSquareOf,
//   addAbsValueOf, setShl/setUshr/setShr, setBit/clearBit/applyBitMask,
//   setAnd/setOr/setXor, montgomeryRedc, and the +=/-=/*=/... operators.
// ============================================================================
