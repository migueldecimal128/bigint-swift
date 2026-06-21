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

// File-scope wrappers: these engine free functions share names with members of
// MutableBigInt / BigIntNumber, so inside this file the member shadows the
// global. At file scope there is no shadow.
private func _validateNormLenAndInjectPoison(_ m: Magia, _ n: Int) -> Bool {
    validateNormLenAndInjectPoison(m, n)
}
private func _isNormalized(_ x: Magia, _ n: Int) -> Bool { isNormalized(x, n) }
private func _setSub(_ z: Magia, _ x: Magia, _ xn: Int, _ y: Magia, _ yn: Int) -> Int {
    setSub(z, x, xn, y, yn)
}
private func _setMul(_ z: Magia, _ x: Magia, _ xn: Int, _ y: Magia, _ yn: Int) -> Int {
    setMul(z, x, xn, y, yn)
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

    /// Reference identity vs another operand. A `BigInt` (value type) is never
    /// `this`; only another `MutableBigInt` can alias self.
    private func isSame(_ x: BigIntNumber) -> Bool {
        (x as? MutableBigInt).map { $0 === self } ?? false
    }

    // MARK: add / sub (engine: mutAdd*/mutSub*/setSub)

    @discardableResult func setAdd(_ x: BigIntNumber, _ n: Int32) -> MutableBigInt { setAddImpl32(x, n < 0, UInt32(n.magnitude)) }
    @discardableResult func setAdd(_ x: BigIntNumber, _ w: UInt32) -> MutableBigInt { setAddImpl32(x, false, w) }
    @discardableResult func setAdd(_ x: BigIntNumber, _ l: Int64) -> MutableBigInt { setAddImpl64(x, l < 0, l.magnitude) }
    @discardableResult func setAdd(_ x: BigIntNumber, _ dw: UInt64) -> MutableBigInt { setAddImpl64(x, false, dw) }
    @discardableResult func setAdd(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt { setAddImpl(x, y.meta, y.magia) }

    @discardableResult func setSub(_ x: BigIntNumber, _ n: Int32) -> MutableBigInt { setAddImpl32(x, n >= 0, UInt32(n.magnitude)) }
    @discardableResult func setSub(_ x: BigIntNumber, _ w: UInt32) -> MutableBigInt { setAddImpl32(x, true, w) }
    @discardableResult func setSub(_ x: BigIntNumber, _ l: Int64) -> MutableBigInt { setAddImpl64(x, l >= 0, l.magnitude) }
    @discardableResult func setSub(_ x: BigIntNumber, _ dw: UInt64) -> MutableBigInt { setAddImpl64(x, true, dw) }
    @discardableResult func setSub(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt { setAddImpl(x, y.meta.negate(), y.magia) }

    @discardableResult private func setAddImpl32(_ x: BigIntNumber, _ ySign: Bool, _ yW: Limb) -> MutableBigInt {
        if !isSame(x) {
            updateMeta(Meta(0))
            ensureMagiaCapacityDiscard(Int(x.meta.normLen) + 1)
            x.magia.copyInto(magia, 0, 0, Int(x.meta.normLen))
            updateMeta(x.meta)
        }
        return mutAddImpl32(ySign, yW)
    }

    @discardableResult private func mutAddImpl32(_ ySign: Bool, _ yW: Limb) -> MutableBigInt {
        biStat(.MBI_SET_ADD_SUB_PRIMITIVE)
        verify(isNormalized())
        let normLen = Int(meta.normLen)
        if yW == 0 { return self }
        if isZero() {
            set(ySign, UInt64(yW))
        } else if meta.signFlag == ySign {
            ensureMagiaCapacityCopy(normLen + 1)
            updateMeta(Meta(signBit: meta.signBit, normLen: Int32(mutAdd32(magia, normLen, yW))))
        } else {
            let cmp = magnitudeCompareTo(yW)
            if cmp > 0 {
                updateMeta(Meta(signBit: meta.signBit, normLen: Int32(mutSub32(magia, normLen, yW))))
            } else if cmp < 0 {
                set(ySign, UInt64(yW &- magia[0]))
            } else {
                setZero()
            }
        }
        return self
    }

    @discardableResult private func setAddImpl64(_ x: BigIntNumber, _ ySign: Bool, _ yDw: UInt64) -> MutableBigInt {
        if !isSame(x) {
            updateMeta(Meta(0))
            ensureMagiaCapacityDiscard(Int(x.meta.normLen) + 2)
            x.magia.copyInto(magia, 0, 0, Int(x.meta.normLen))
            updateMeta(x.meta)
        }
        return mutAddImpl64(ySign, yDw)
    }

    @discardableResult private func mutAddImpl64(_ ySign: Bool, _ yDw: UInt64) -> MutableBigInt {
        biStat(.MBI_SET_ADD_SUB_PRIMITIVE)
        verify(isNormalized())
        let normLen = Int(meta.normLen)
        if yDw == 0 { return self }
        if isZero() {
            set(ySign, yDw)
        } else if meta.signFlag == ySign {
            ensureMagiaCapacityCopy(normLen + 2)
            updateMeta(Meta(signBit: meta.signBit, normLen: Int32(mutAdd64(magia, normLen, yDw))))
        } else {
            let cmp = magnitudeCompareTo(yDw)
            if cmp > 0 {
                updateMeta(Meta(signBit: meta.signBit, normLen: Int32(mutSub64(magia, normLen, yDw))))
            } else if cmp < 0 {
                set(ySign, yDw &- toRawULong(magia, normLen))
            } else {
                setZero()
            }
        }
        return self
    }

    @discardableResult private func setAddImpl(_ x: BigIntNumber, _ yMeta: Meta, _ yMagia: Magia) -> MutableBigInt {
        if isSame(x) {
            return mutAddImpl(yMeta, yMagia)
        }
        // if y aliases this.magia, we must use x
        if magia === yMagia {
            updateMeta(yMeta)
            return mutAddImpl(x.meta, x.magia)
        }
        // No aliasing: copy the longer operand to minimize reallocation
        updateMeta(Meta(0))
        ensureMagiaCapacityDiscard(max(Int(x.meta.normLen), Int(yMeta.normLen)) + 1)
        if Int(x.meta.normLen) >= Int(yMeta.normLen) {
            x.magia.copyInto(magia, 0, 0, Int(x.meta.normLen))
            updateMeta(x.meta)
            return mutAddImpl(yMeta, yMagia)
        } else {
            yMagia.copyInto(magia, 0, 0, Int(yMeta.normLen))
            updateMeta(yMeta)
            return mutAddImpl(x.meta, x.magia)
        }
    }

    @discardableResult private func mutAddImpl(_ yMeta: Meta, _ yMagia: Magia) -> MutableBigInt {
        verify(isNormalized())
        verify(_isNormalized(yMagia, Int(yMeta.normLen)))
        let normLen = Int(meta.normLen)
        if yMeta.isZero { return self }
        if isZero() {
            set(yMeta, yMagia)
        } else if meta.signFlag == yMeta.signFlag {
            ensureMagiaCapacityCopy(max(normLen, Int(yMeta.normLen)) + 1)
            updateMeta(Meta(signBit: meta.signBit, normLen: Int32(mutAdd(magia, normLen, yMagia, Int(yMeta.normLen)))))
        } else {
            let cmp = magnitudeCompareTo(yMeta, yMagia)
            if cmp > 0 {
                updateMeta(Meta(signBit: meta.signBit, normLen: Int32(mutSub(magia, normLen, yMagia, Int(yMeta.normLen)))))
            } else if cmp < 0 {
                let originalMagia = magia
                ensureMagiaCapacityDiscard(Int(yMeta.normLen))
                updateMeta(Meta(signBit: yMeta.signBit, normLen: Int32(_setSub(magia, yMagia, Int(yMeta.normLen), originalMagia, normLen))))
            } else {
                setZero()
            }
        }
        biStat(.MBI_SET_ADD_SUB_BI)
        return self
    }

    // MARK: mul (engine: setMul32/64/setMul)

    @discardableResult func setMul(_ x: BigIntNumber, _ n: Int32) -> MutableBigInt { setMulImpl(x, n < 0, UInt32(n.magnitude)) }
    @discardableResult func setMul(_ x: BigIntNumber, _ w: UInt32) -> MutableBigInt { setMulImpl(x, false, w) }
    @discardableResult func setMul(_ x: BigIntNumber, _ l: Int64) -> MutableBigInt { setMulImpl(x, l < 0, l.magnitude) }
    @discardableResult func setMul(_ x: BigIntNumber, _ dw: UInt64) -> MutableBigInt { setMulImpl(x, false, dw) }

    @discardableResult func setMul(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt {
        let xNormLen = Int(x.meta.normLen)
        let yNormLen = Int(y.meta.normLen)
        if yNormLen <= 2 { return setMulImpl(x, y.meta.signFlag, y.toULongMagnitude()) }
        if y.isMagnitudePowerOfTwo() { return setShl(x, y.countTrailingZeroBits()) }
        let xMagia = x.magia
        let yMagia = y.magia
        ensureTmp1Capacity(xNormLen + yNormLen, .MBI_RESIZE_TMP1_MUL)
        swapTmp1()
        updateMeta(Meta(signBit: x.meta.signBit ^ y.meta.signBit,
                        normLen: Int32(_setMul(magia, xMagia, xNormLen, yMagia, yNormLen))))
        biStat(.MBI_SET_MUL_BI)
        return self
    }

    @discardableResult private func setMulImpl(_ x: BigIntNumber, _ wSign: Bool, _ w: Limb) -> MutableBigInt {
        let xMagia = x.magia
        ensureMagiaCapacityDiscard(Int(x.meta.normLen) + 1)
        updateMeta(Meta(signFlag: x.meta.signFlag != wSign,
                        normLen: Int32(setMul32(magia, xMagia, Int(x.meta.normLen), w))))
        biStat(.MBI_SET_MUL_PRIMITIVE)
        return self
    }

    @discardableResult private func setMulImpl(_ x: BigIntNumber, _ dwSign: Bool, _ dw: UInt64) -> MutableBigInt {
        let xMagia = x.magia
        ensureMagiaCapacityDiscard(Int(x.meta.normLen) + 2)
        updateMeta(Meta(signFlag: x.meta.signFlag != dwSign,
                        normLen: Int32(setMul64(magia, xMagia, Int(x.meta.normLen), dw))))
        biStat(.MBI_SET_MUL_PRIMITIVE)
        return self
    }

    // MARK: shifts (engine: setShiftLeft/setShiftRight)

    @discardableResult func mutShl(_ bitCount: Int) -> MutableBigInt { setShl(self, bitCount) }

    @discardableResult func setShl(_ x: BigIntNumber, _ bitCount: Int) -> MutableBigInt {
        if bitCount < 0 {
            throwNegBitCount()
        } else if bitCount == 0 || x.isZero() {
            set(x)
        } else {
            let xMagia = x.magia
            ensureMagiaBitCapacityDiscard(x.magnitudeBitLen() + bitCount)
            updateMeta(Meta(signBit: x.meta.signBit,
                            normLen: Int32(setShiftLeft(magia, xMagia, Int(x.meta.normLen), bitCount))))
        }
        biStat(.MBI_SET_BITWISE_OP)
        return self
    }

    @discardableResult func mutUshr(_ bitCount: Int) -> MutableBigInt { setUshr(self, bitCount) }

    @discardableResult func setUshr(_ x: BigIntNumber, _ bitCount: Int) -> MutableBigInt {
        let zBitLen = x.magnitudeBitLen() - bitCount
        if bitCount < 0 {
            throwNegBitCount()
        } else if bitCount == 0 {
            set(x).mutAbs()   // ushr discards sign -> non-negative magnitude
        } else if zBitLen <= 0 {
            setZero()
        } else {
            ensureMagiaBitCapacityDiscard(zBitLen)
            updateMeta(Meta(signBit: 0,
                            normLen: Int32(setShiftRight(magia, x.magia, Int(x.meta.normLen), bitCount))))
        }
        biStat(.MBI_SET_BITWISE_OP)
        return self
    }

    @discardableResult func mutShr(_ bitCount: Int) -> MutableBigInt { setShr(self, bitCount) }

    @discardableResult func setShr(_ x: BigIntNumber, _ bitCount: Int) -> MutableBigInt {
        let zBitLen = x.magnitudeBitLen() - bitCount
        if bitCount < 0 {
            throwNegBitCount()
        } else if bitCount == 0 {
            set(x)
        } else if zBitLen <= 0 && x.meta.isNegative {
            set(Int32(-1))
        } else if zBitLen <= 0 {
            setZero()
        } else {
            let needsIncrement = x.meta.isNegative
                && testAnyBitInLowerN(x.magia, Int(x.meta.normLen), bitCount)
            ensureMagiaBitCapacityDiscard(zBitLen)
            var normLen = setShiftRight(magia, x.magia, Int(x.meta.normLen), bitCount)
            verify(normLen > 0)
            if needsIncrement {
                ensureMagiaBitCapacityCopy(zBitLen + 1)
                normLen = mutAdd32(magia, normLen, 1)
            }
            updateMeta(Meta(signFlag: x.meta.signFlag, normLen: Int32(normLen)))
        }
        biStat(.MBI_SET_BITWISE_OP)
        return self
    }
}

// ============================================================================
// PHASE 2 REMAINING — MutableBigInt (MutableBigInt.kt):
//   setSqr, karatsubaSetSqr, setPow/mutPow, setDiv (+Impl32/64,
//   trySetDivFastPath*), setRem (+Impl, trySetRemFastPath), setMod (+Impl),
//   addSquareOf, addAbsValueOf, setBit/clearBit/applyBitMask,
//   setAnd/setOr/setXor, montgomeryRedc, and the +=/-=/*=/... operators.
// ============================================================================
