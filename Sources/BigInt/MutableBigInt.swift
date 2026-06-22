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
// shadowed by the same-named BigIntNumber instance method inside this file.
// (The magia engine functions no longer need wrappers — they are `magia_`-prefixed.)
private func _validateNormLenAndInjectPoison(_ m: Magia, _ n: Int) -> Bool {
    validateNormLenAndInjectPoison(m, n)
}

public final class MutableBigInt: BigIntNumber {
    public var meta: Meta
    public var magia: Magia
    var limbCapacityHint = 0
    var tmp1: Magia = MAGIA_ZERO
    var tmp2: Magia = MAGIA_ZERO

    private init(_ meta: Meta, _ magia: Magia) {
        self.meta = meta
        self.magia = magia
    }

    // MARK: constructors

    /// Empty (zero) accumulator.
    public convenience init() {
        biStat(.MBI_CONSTRUCT_EMPTY)
        let m = Magia(4)
        verify(_validateNormLenAndInjectPoison(m, 0))
        self.init(Meta(0), m)
    }

    public convenience init(_ n: Int32) { self.init(n < 0, UInt64(n.magnitude)) }
    public convenience init(_ w: UInt32) { self.init(false, UInt64(w)) }
    public convenience init(_ l: Int64) { self.init(l < 0, l.magnitude) }
    public convenience init(_ dw: UInt64) { self.init(false, dw) }

    public convenience init(_ sign: Bool, _ dwMag: UInt64) {
        biStat(.MBI_CONSTRUCT_PRIMITIVE)
        let m = Magia(4)
        m[0] = dwMag                                   // a UInt64 is one 64-bit limb
        let normLen: Int32 = dwMag == 0 ? 0 : 1
        verify(_validateNormLenAndInjectPoison(m, Int(normLen)))
        self.init(Meta(signFlag: sign, normLen: normLen), m)
    }

    public convenience init(_ other: BigIntNumber) {
        biStat(.MBI_CONSTRUCT_BI)
        let n = Int(other.meta.normLen)
        let m = magia_newWithFloorLen(n)
        other.magia.copyInto(m, 0, 0, n)
        verify(_validateNormLenAndInjectPoison(m, n))
        self.init(other.meta, m)
    }

    /// Zero accumulator with limb storage preallocated for ≥ `initialBitCapacity` bits.
    public static func withBitCapacityHint(_ initialBitCapacity: Int) -> MutableBigInt {
        if initialBitCapacity >= 0 {
            let initialLimbCapacity = max(4, magia_limbLenFromBitLen(initialBitCapacity))
            let m = magia_newWithFloorLen(initialLimbCapacity)
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
        magia = magia_newWithFloorLen(targetLimbLen + headroom)
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
        tmp1 = magia_newWithFloorLen(requestedLimbLen + headRoom)
    }

    private func resizeTmp2(_ requestedLimbLen: Int, _ resizeOp: StatsOp) {
        verify(requestedLimbLen > tmp2.size)
        let hintBit = limbCapacityHint > 0 ? 2 : 0
        let repeatBit = magia.size > 5 ? 1 : 0
        BigIntStats.BI_OP_COUNTS[resizeOp.ordinal + hintBit + repeatBit] += 1
        let headRoom = tmp2.size > 0 ? (requestedLimbLen >> 1) : 0
        tmp2 = magia_newWithFloorLen(requestedLimbLen + headRoom)
    }

    public func ensureMagiaCapacityDiscard(_ requestedLimbLen: Int) {
        if magia.size < requestedLimbLen { resizeMagiaDiscard(requestedLimbLen) }
    }
    private func ensureMagiaCapacityCopy(_ minLimbLen: Int) {
        if magia.size < minLimbLen { resizeMagiaCopy(max(limbCapacityHint, minLimbLen)) }
    }
    public func ensureMagiaCapacityCopyZeroExtend(_ newLimbLen: Int) {
        if newLimbLen <= magia.size {
            if newLimbLen > Int(meta.normLen) { magia.fill(0, Int(meta.normLen), newLimbLen) }
        } else {
            resizeMagiaCopy(max(limbCapacityHint, newLimbLen))
        }
    }
    public func ensureMagiaBitCapacityDiscard(_ minBitLen: Int) {
        ensureMagiaCapacityDiscard((minBitLen + 0x3F) >> 6)
    }
    private func ensureMagiaBitCapacityCopy(_ minBitLen: Int) {
        ensureMagiaCapacityCopy((minBitLen + 0x3F) >> 6)
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

    public func hintBitCapacity(_ bitCapacityHint: Int) -> MutableBigInt {
        if bitCapacityHint < 0 { fatalError() }
        limbCapacityHint = max(limbCapacityHint, magia_calcHeapLimbQuantum((bitCapacityHint + 63) >> 6))
        return self
    }
    public func currentLimbCapacityHint() -> Int { limbCapacityHint }
    public func didExceedHint() -> Bool { magia.size > limbCapacityHint }
    public func getHintBitCapacity() -> Int { limbCapacityHint * 64 }

    // MARK: meta / basic setters

    public func updateMeta(_ meta: Meta) {
        self.meta = meta
        verify(validateNormLenAndInjectPoison())   // instance member (intended)
        verify(isNormalized())
    }

    @discardableResult public func setZero() -> MutableBigInt { validate(); updateMeta(Meta(0)); return self }
    @discardableResult public func setOne() -> MutableBigInt {
        validate()
        magia[0] = 1
        updateMeta(Meta(signBit: 0, normLen: 1))
        validate()
        return self
    }
    @discardableResult public func mutAbs() -> MutableBigInt { updateMeta(meta.abs()); return self }
    @discardableResult public func mutNegate() -> MutableBigInt { updateMeta(meta.negate()); return self }
    @discardableResult public func mutWithSign(_ sign: Bool) -> MutableBigInt { updateMeta(meta.withSign(sign)); return self }

    @discardableResult public func set(_ n: Int32) -> MutableBigInt { set(n < 0, UInt64(n.magnitude)) }
    @discardableResult public func set(_ w: UInt32) -> MutableBigInt { set(false, UInt64(w)) }
    @discardableResult public func set(_ l: Int64) -> MutableBigInt { set(l < 0, l.magnitude) }
    @discardableResult public func set(_ dw: UInt64) -> MutableBigInt { set(false, dw) }
    @discardableResult public func set(_ bi: BigIntNumber) -> MutableBigInt { set(bi.meta, bi.magia) }

    @discardableResult public func set(_ sign: Bool, _ dw: UInt64) -> MutableBigInt {
        let normLen: Int32 = dw == 0 ? 0 : 1          // a UInt64 is one 64-bit limb
        magia[0] = dw
        updateMeta(Meta(signFlag: sign, normLen: normLen))
        return self
    }

    @discardableResult public func set(_ sign: Bool, _ dwHi: UInt64, _ dwLo: UInt64) -> MutableBigInt {
        // a 128-bit value is two 64-bit limbs
        let normLen: Int32 = dwHi != 0 ? 2 : (dwLo == 0 ? 0 : 1)
        magia[0] = dwLo
        magia[1] = dwHi
        updateMeta(Meta(signFlag: sign, normLen: normLen))
        return self
    }

    @discardableResult private func set(_ yMeta: Meta, _ y: Magia) -> MutableBigInt {
        ensureMagiaCapacityDiscard(Int(yMeta.normLen))
        if magia !== y { y.copyInto(magia, 0, 0, Int(yMeta.normLen)) }
        updateMeta(yMeta)
        return self
    }

    public func toBigInt() -> BigInt { BigInt.from(self) }

    /// Reference identity vs another operand. A `BigInt` (value type) is never
    /// `this`; only another `MutableBigInt` can alias self.
    private func isSame(_ x: BigIntNumber) -> Bool {
        (x as? MutableBigInt).map { $0 === self } ?? false
    }

    // MARK: add / sub (engine: mutAdd*/mutSub*/setSub)

    @discardableResult public func setAdd(_ x: BigIntNumber, _ n: Int32) -> MutableBigInt { setAddImpl32(x, n < 0, UInt64(n.magnitude)) }
    @discardableResult public func setAdd(_ x: BigIntNumber, _ w: UInt32) -> MutableBigInt { setAddImpl32(x, false, UInt64(w)) }
    @discardableResult public func setAdd(_ x: BigIntNumber, _ l: Int64) -> MutableBigInt { setAddImpl64(x, l < 0, l.magnitude) }
    @discardableResult public func setAdd(_ x: BigIntNumber, _ dw: UInt64) -> MutableBigInt { setAddImpl64(x, false, dw) }
    @discardableResult public func setAdd(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt { setAddImpl(x, y.meta, y.magia) }

    @discardableResult public func setSub(_ x: BigIntNumber, _ n: Int32) -> MutableBigInt { setAddImpl32(x, n >= 0, UInt64(n.magnitude)) }
    @discardableResult public func setSub(_ x: BigIntNumber, _ w: UInt32) -> MutableBigInt { setAddImpl32(x, true, UInt64(w)) }
    @discardableResult public func setSub(_ x: BigIntNumber, _ l: Int64) -> MutableBigInt { setAddImpl64(x, l >= 0, l.magnitude) }
    @discardableResult public func setSub(_ x: BigIntNumber, _ dw: UInt64) -> MutableBigInt { setAddImpl64(x, true, dw) }
    @discardableResult public func setSub(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt { setAddImpl(x, y.meta.negate(), y.magia) }

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
            updateMeta(Meta(signBit: meta.signBit, normLen: Int32(magia_mutAddLimb(magia, normLen, yW))))
        } else {
            let cmp = magnitudeCompareTo(yW)
            if cmp > 0 {
                updateMeta(Meta(signBit: meta.signBit, normLen: Int32(magia_mutSubLimb(magia, normLen, yW))))
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
            updateMeta(Meta(signBit: meta.signBit, normLen: Int32(magia_mutAddLimb(magia, normLen, yDw))))
        } else {
            let cmp = magnitudeCompareTo(yDw)
            if cmp > 0 {
                updateMeta(Meta(signBit: meta.signBit, normLen: Int32(magia_mutSubLimb(magia, normLen, yDw))))
            } else if cmp < 0 {
                set(ySign, yDw &- magia_toRawULong(magia, normLen))
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
        verify(magia_isNormalized(yMagia, Int(yMeta.normLen)))
        let normLen = Int(meta.normLen)
        if yMeta.isZero { return self }
        if isZero() {
            set(yMeta, yMagia)
        } else if meta.signFlag == yMeta.signFlag {
            ensureMagiaCapacityCopy(max(normLen, Int(yMeta.normLen)) + 1)
            updateMeta(Meta(signBit: meta.signBit, normLen: Int32(magia_mutAdd(magia, normLen, yMagia, Int(yMeta.normLen)))))
        } else {
            let cmp = magnitudeCompareTo(yMeta, yMagia)
            if cmp > 0 {
                updateMeta(Meta(signBit: meta.signBit, normLen: Int32(magia_mutSub(magia, normLen, yMagia, Int(yMeta.normLen)))))
            } else if cmp < 0 {
                let originalMagia = magia
                ensureMagiaCapacityDiscard(Int(yMeta.normLen))
                updateMeta(Meta(signBit: yMeta.signBit, normLen: Int32(magia_setSub(magia, yMagia, Int(yMeta.normLen), originalMagia, normLen))))
            } else {
                setZero()
            }
        }
        biStat(.MBI_SET_ADD_SUB_BI)
        return self
    }

    // MARK: mul (engine: setMulLimb/setMul)

    @discardableResult public func setMul(_ x: BigIntNumber, _ n: Int32) -> MutableBigInt { setMulImpl(x, n < 0, UInt64(n.magnitude)) }
    @discardableResult public func setMul(_ x: BigIntNumber, _ w: UInt32) -> MutableBigInt { setMulImpl(x, false, UInt64(w)) }
    @discardableResult public func setMul(_ x: BigIntNumber, _ l: Int64) -> MutableBigInt { setMulImpl(x, l < 0, l.magnitude) }
    @discardableResult public func setMul(_ x: BigIntNumber, _ dw: UInt64) -> MutableBigInt { setMulImpl(x, false, dw) }

    @discardableResult public func setMul(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt {
        let xNormLen = Int(x.meta.normLen)
        let yNormLen = Int(y.meta.normLen)
        if yNormLen <= 1 { return setMulImpl(x, y.meta.signFlag, y.toULongMagnitude()) }
        if y.isMagnitudePowerOfTwo() { return setShl(x, y.countTrailingZeroBits()) }
        let xMagia = x.magia
        let yMagia = y.magia
        ensureTmp1Capacity(xNormLen + yNormLen, .MBI_RESIZE_TMP1_MUL)
        swapTmp1()
        updateMeta(Meta(signBit: x.meta.signBit ^ y.meta.signBit,
                        normLen: Int32(magia_setMul(magia, xMagia, xNormLen, yMagia, yNormLen))))
        biStat(.MBI_SET_MUL_BI)
        return self
    }

    // single-limb (UInt64) multiplier — at 64-bit limbs the old *32/*64 pair is one impl
    @discardableResult private func setMulImpl(_ x: BigIntNumber, _ wSign: Bool, _ w: Limb) -> MutableBigInt {
        let xMagia = x.magia
        ensureMagiaCapacityDiscard(Int(x.meta.normLen) + 1)
        updateMeta(Meta(signFlag: x.meta.signFlag != wSign,
                        normLen: Int32(magia_setMulLimb(magia, xMagia, Int(x.meta.normLen), w))))
        biStat(.MBI_SET_MUL_PRIMITIVE)
        return self
    }

    // MARK: shifts (engine: setShiftLeft/setShiftRight)

    @discardableResult public func mutShl(_ bitCount: Int) -> MutableBigInt { setShl(self, bitCount) }

    @discardableResult public func setShl(_ x: BigIntNumber, _ bitCount: Int) -> MutableBigInt {
        if bitCount < 0 {
            throwNegBitCount()
        } else if bitCount == 0 || x.isZero() {
            set(x)
        } else {
            let xMagia = x.magia
            ensureMagiaBitCapacityDiscard(x.magnitudeBitLen() + bitCount)
            updateMeta(Meta(signBit: x.meta.signBit,
                            normLen: Int32(magia_setShiftLeft(magia, xMagia, Int(x.meta.normLen), bitCount))))
        }
        biStat(.MBI_SET_BITWISE_OP)
        return self
    }

    @discardableResult public func mutUshr(_ bitCount: Int) -> MutableBigInt { setUshr(self, bitCount) }

    @discardableResult public func setUshr(_ x: BigIntNumber, _ bitCount: Int) -> MutableBigInt {
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
                            normLen: Int32(magia_setShiftRight(magia, x.magia, Int(x.meta.normLen), bitCount))))
        }
        biStat(.MBI_SET_BITWISE_OP)
        return self
    }

    @discardableResult public func mutShr(_ bitCount: Int) -> MutableBigInt { setShr(self, bitCount) }

    @discardableResult public func setShr(_ x: BigIntNumber, _ bitCount: Int) -> MutableBigInt {
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
                && magia_testAnyBitInLowerN(x.magia, Int(x.meta.normLen), bitCount)
            ensureMagiaBitCapacityDiscard(zBitLen)
            var normLen = magia_setShiftRight(magia, x.magia, Int(x.meta.normLen), bitCount)
            verify(normLen > 0)
            if needsIncrement {
                ensureMagiaBitCapacityCopy(zBitLen + 1)
                normLen = magia_mutAddLimb(magia, normLen, 1)
            }
            updateMeta(Meta(signFlag: x.meta.signFlag, normLen: Int32(normLen)))
        }
        biStat(.MBI_SET_BITWISE_OP)
        return self
    }
    // MARK: div (engine: setDivLimb/setDivKnuth/trySetDivFastPath)

    @discardableResult public func setDiv(_ x: MutableBigInt, _ n: Int32) -> MutableBigInt { setDivImpl32(x, n < 0, UInt64(n.magnitude)) }
    @discardableResult public func setDiv(_ x: MutableBigInt, _ w: UInt32) -> MutableBigInt { setDivImpl32(x, false, UInt64(w)) }
    @discardableResult public func setDiv(_ x: MutableBigInt, _ l: Int64) -> MutableBigInt { setDivImpl64(x, l < 0, l.magnitude) }
    @discardableResult public func setDiv(_ x: MutableBigInt, _ dw: UInt64) -> MutableBigInt { setDivImpl64(x, false, dw) }

    @discardableResult public func setDiv(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt {
        let xNormLen = Int(x.meta.normLen)
        let yNormLen = Int(y.meta.normLen)
        ensureMagiaCapacityDiscard(xNormLen - yNormLen + 1)
        if !trySetDivFastPath(x, y) {
            // At 64-bit limbs every multi-limb divisor (yNormLen >= 2) uses the
            // general Knuth path; the UInt64-divisor special case is gone.
            ensureTmp1Capacity(xNormLen + 1, .MBI_RESIZE_TMP1_KNUTH_DIVIDEND)
            biStat(.MBI_SET_DIV_BI_KNUTH)
            ensureTmp2Capacity(yNormLen, .MBI_RESIZE_TMP2_KNUTH_DIVISOR)
            updateMeta(Meta(signBit: x.meta.signBit ^ y.meta.signBit,
                            normLen: Int32(magia_setDivKnuth(magia, x.magia, xNormLen, tmp1, y.magia, yNormLen, tmp2))))
        }
        return self
    }

    @discardableResult private func setDivImpl32(_ x: BigIntNumber, _ ySign: Bool, _ yW: Limb) -> MutableBigInt {
        biStat(.MBI_SET_DIV_PRIMITIVE)
        ensureMagiaCapacityDiscard(Int(x.meta.normLen))
        let normLen = magia_setDivLimb(magia, x.magia, Int(x.meta.normLen), yW)
        updateMeta(Meta(signFlag: x.meta.signFlag != ySign, normLen: Int32(normLen)))
        return self
    }

    @discardableResult private func setDivImpl64(_ x: BigIntNumber, _ ySign: Bool, _ yDw: UInt64) -> MutableBigInt {
        // At 64-bit limbs a UInt64 divisor is a single limb — identical to setDivImpl32.
        return setDivImpl32(x, ySign, yDw)
    }

    @discardableResult private func trySetDivFastPath(_ x: BigIntNumber, _ y: BigIntNumber) -> Bool {
        let qSignFlag = x.meta.signFlag != y.meta.signFlag
        let qNormLen = magia_trySetDivFastPath(magia, x.magia, Int(x.meta.normLen), y.magia, Int(y.meta.normLen))
        if qNormLen < 0 { return false }
        updateMeta(Meta(signFlag: qSignFlag, normLen: Int32(qNormLen)))
        biStat(.MBI_SET_DIV_BI_FASTPATH)
        return true
    }

    // MARK: rem (engine: calcRemLimb/setRem/trySetRemFastPath)

    @discardableResult private func trySetRemFastPath(_ x: BigIntNumber, _ y: BigIntNumber) -> Bool {
        let rSignFlag = x.meta.signFlag
        let rNormLen = magia_trySetRemFastPath(magia, x.magia, Int(x.meta.normLen), y.magia, Int(y.meta.normLen))
        if rNormLen < 0 { return false }
        updateMeta(Meta(signFlag: rSignFlag, normLen: Int32(rNormLen)))
        biStat(.MBI_SET_REM_BI_FASTPATH)
        return true
    }

    @discardableResult public func setRem(_ x: BigIntNumber, _ n: Int32) -> MutableBigInt { setRemImpl(x, UInt64(n.magnitude)) }
    @discardableResult public func setRem(_ x: BigIntNumber, _ w: UInt32) -> MutableBigInt { setRemImpl(x, UInt64(w)) }
    @discardableResult public func setRem(_ x: BigIntNumber, _ l: Int64) -> MutableBigInt { setRemImpl(x, l.magnitude) }
    @discardableResult public func setRem(_ x: BigIntNumber, _ dw: UInt64) -> MutableBigInt { setRemImpl(x, dw) }

    @discardableResult public func setRem(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt {
        ensureMagiaCapacityCopy(min(Int(x.meta.normLen), Int(y.meta.normLen)))
        if trySetRemFastPath(x, y) { return self }
        ensureTmp1Capacity(Int(x.meta.normLen) + 1, .MBI_RESIZE_TMP1_KNUTH_DIVIDEND)
        ensureTmp2Capacity(Int(y.meta.normLen), .MBI_RESIZE_TMP2_KNUTH_DIVISOR)
        let rNormLen = magia_setRem(magia, x.magia, Int(x.meta.normLen), tmp1, y.magia, Int(y.meta.normLen), tmp2)
        updateMeta(Meta(signBit: x.meta.signBit, normLen: Int32(rNormLen)))
        biStat(.MBI_SET_REM_BI_KNUTH)
        return self
    }

    @discardableResult private func setRemImpl(_ x: BigIntNumber, _ yDw: UInt64) -> MutableBigInt {
        biStat(.MBI_SET_REM_PRIMITIVE)
        // single-limb divisor at 64-bit limbs — no Knuth scratch needed
        let rem = magia_calcRemLimb(x.magia, Int(x.meta.normLen), yDw)
        return set(x.meta.signFlag, rem)
    }

    // MARK: mod (non-negative result; rejects negative modulus)

    @discardableResult public func setMod(_ x: BigIntNumber, _ n: Int32) -> MutableBigInt { setModImpl(x, n < 0, UInt64(n.magnitude)) }
    @discardableResult public func setMod(_ x: BigIntNumber, _ w: UInt32) -> MutableBigInt { setModImpl(x, false, UInt64(w)) }
    @discardableResult public func setMod(_ x: BigIntNumber, _ l: Int64) -> MutableBigInt { setModImpl(x, l < 0, l.magnitude) }
    @discardableResult public func setMod(_ x: BigIntNumber, _ dw: UInt64) -> MutableBigInt { setModImpl(x, false, dw) }

    @discardableResult public func setMod(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt {
        if y.meta.isNegative { throwModNegDivisor() }
        setRem(x, y)
        if isNegative() { setAdd(self, y) }
        biStat(.MBI_SET_MOD_BI_KNUTH)
        return self
    }

    @discardableResult private func setModImpl(_ x: BigIntNumber, _ ySign: Bool, _ yDw: UInt64) -> MutableBigInt {
        if ySign { throwModNegDivisor() }
        setRem(x, yDw)
        if isNegative() { setAdd(self, yDw) }
        BigIntStats.BI_OP_COUNTS[StatsOp.MBI_SET_REM_PRIMITIVE.ordinal] -= 1
        biStat(.MBI_SET_MOD_PRIMITIVE)
        return self
    }

    // MARK: square (engine: setSqr/setSqrKaratsuba)

    @discardableResult public func setSqr(_ n: Int32) -> MutableBigInt { setSqr(UInt32(n.magnitude)) }

    @discardableResult public func setSqr(_ w: UInt32) -> MutableBigInt {
        let abs = UInt64(w)
        biStat(.MBI_SET_SQR_PRIMITIVE)
        return set(abs &* abs)
    }

    @discardableResult public func setSqr(_ l: Int64) -> MutableBigInt { setSqr(l.magnitude) }

    @discardableResult public func setSqr(_ dw: UInt64) -> MutableBigInt {
        biStat(.MBI_SET_SQR_PRIMITIVE)
        let lo = dw &* dw
        let hi = unsignedMulHi(dw, dw)
        return set(false, hi, lo)
    }

    @discardableResult public func setSqr(_ x: BigIntNumber) -> MutableBigInt {
        verify(x.isNormalized())
        let xNormLen = Int(x.meta.normLen)
        if xNormLen == 0 { return setZero() }
        if xNormLen < KARATSUBA_SQR_THRESHOLD {
            let xMagia = x.magia
            ensureTmp1CapacityZeroed(xNormLen + xNormLen, .MBI_RESIZE_TMP1_SQR)
            swapTmp1()
            updateMeta(Meta(signBit: 0, normLen: Int32(magia_setSqr(magia, xMagia, xNormLen))))
            biStat(.MBI_SET_SQR_SCHOOLBOOK)
            return self
        } else {
            return karatsubaSetSqr(x)
        }
    }

    @discardableResult public func karatsubaSetSqr(_ a: BigIntNumber) -> MutableBigInt {
        let n = Int(a.meta.normLen)
        if n <= 1 { return setSqr(a) }
        let k1 = (n + 1) / 2
        let zLen = 2 * n
        ensureTmp1CapacityZeroed(zLen + 1, .MBI_RESIZE_TMP1_KARATSUBA_SQR)
        ensureTmp2Capacity(3 * k1 + 3, .MBI_RESIZE_TMP2_KARATSUBA_Z1)
        let zNormLen = magia_setSqrKaratsuba(tmp1, a.magia, Int(a.meta.normLen), tmp2)
        swapTmp1()
        updateMeta(Meta(Int32(zNormLen)))
        biStat(.MBI_SET_SQR_KARATSUBA)
        return self
    }

    // MARK: bit set/clear/mask

    @discardableResult public func setBit(_ bitIndex: Int) -> MutableBigInt {
        if bitIndex >= 0 {
            biStat(.MBI_SET_BITWISE_OP)
            let wordIndex = bitIndex >> 6
            let isolatedBit: Limb = 1 << (bitIndex & 0x3F)
            if wordIndex < Int(meta.normLen) {
                magia[wordIndex] = magia[wordIndex] | isolatedBit
                return self
            }
            ensureMagiaCapacityCopyZeroExtend(wordIndex + 1)
            magia[wordIndex] = isolatedBit
            updateMeta(Meta(signBit: meta.signBit, normLen: Int32(wordIndex + 1)))
            return self
        }
        throwBoundsCheckViolation()
    }

    @discardableResult public func clearBit(_ bitIndex: Int) -> MutableBigInt {
        if bitIndex >= 0 {
            biStat(.MBI_SET_BITWISE_OP)
            let wordIndex = bitIndex >> 6
            if wordIndex < Int(meta.normLen) {
                let isolatedBitMask: Limb = ~(1 << (bitIndex & 0x3F))
                magia[wordIndex] = magia[wordIndex] & isolatedBitMask
                updateMeta(Meta(signBit: meta.signBit, normLen: Int32(magia_normLen(magia, Int(meta.normLen)))))
            }
            return self
        }
        throwBoundsCheckViolation()
    }

    /// `this = abs(this) & ((2^bitWidth - 1) << bitIndex)`.
    @discardableResult public func applyBitMask(_ bitWidth: Int, _ bitIndex: Int = 0) -> MutableBigInt {
        verify(isNormalized())
        biStat(.MBI_SET_BITWISE_OP)
        let myBitLen = magnitudeBitLen()
        if bitIndex < 0 || bitWidth < 0 { throwInvalidBitLenRange() }
        if bitWidth == 0 || bitIndex >= myBitLen { return setZero() }
        if bitWidth == 1 && !testBit(bitIndex) { return setZero() }
        if bitWidth == 1 {
            let limbIndex = bitIndex >> 6
            magia.fill(0, 0, limbIndex)
            magia[limbIndex] = Limb(1) << (bitIndex & 0x3F)
            updateMeta(Meta(Int32(limbIndex + 1)))
            verify(isNormalized())
            return self
        }
        // more than 1 bit wide and some overlap
        let clampedBitLen = min(bitWidth + bitIndex, myBitLen)
        let normLen0 = (clampedBitLen + 0x3F) >> 6
        let nlz = (normLen0 << 6) - clampedBitLen
        magia[normLen0 - 1] = magia[normLen0 - 1] & (Limb.max >> nlz)
        let loIndex = bitIndex >> 6
        magia.fill(0, 0, loIndex)
        let ctz = bitIndex & 0x3F
        magia[loIndex] = magia[loIndex] & (Limb.max << ctz)
        let normLenV = magia_normLen(magia, normLen0)
        updateMeta(Meta(Int32(normLenV)))
        verify(isNormalized())
        return self
    }

    // MARK: bitwise and/or/xor (engine: setAnd/setOr/setXor; aliasing-safe)

    // NOTE: setAnd/setOr/setXor/setNot delegate to the BigInt two's-complement
    // combiner rather than mutating the accumulator buffer in place. This is the
    // simple, correct form and guarantees Mbi and BigInt give identical results,
    // but unlike the other set* ops it ALLOCATES (a snapshot of any aliased
    // operand plus the result) instead of being zero-alloc/in-place. Acceptable
    // because bitwise ops are not on a hot path in the consumers (the recipmul
    // oracle uses div/mul/shift; xor is rare mask reconstruction). If Mbi bitwise
    // ever lands on a hot path, reimplement in-place with a sign-aware engine
    // kernel (the old magnitude-only magia_setAnd/Or/Xor were removed in this change).

    @discardableResult public func setAnd(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt {
        // Two's-complement AND (matches java.math.BigInteger). Computed into a
        // fresh BigInt before writing self, so aliasing (x or y === self) is safe.
        set(x.toBigInt().and(y.toBigInt()))
    }

    @discardableResult public func mutAnd(_ y: BigIntNumber) -> MutableBigInt { setAnd(self, y) }

    @discardableResult public func setOr(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt {
        set(x.toBigInt().or(y.toBigInt()))   // two's-complement OR; aliasing-safe
    }

    @discardableResult public func mutOr(_ y: BigIntNumber) -> MutableBigInt { setOr(self, y) }

    @discardableResult public func setXor(_ x: BigIntNumber, _ y: BigIntNumber) -> MutableBigInt {
        set(x.toBigInt().xor(y.toBigInt()))  // two's-complement XOR; aliasing-safe
    }

    @discardableResult public func mutXor(_ y: BigIntNumber) -> MutableBigInt { setXor(self, y) }

    /// Sets self to the two's-complement NOT of `x` (`~x == -x - 1`).
    @discardableResult public func setNot(_ x: BigIntNumber) -> MutableBigInt { set(x.toBigInt().not()) }

    /// In-place two's-complement NOT (`self = ~self`).
    @discardableResult public func mutNot() -> MutableBigInt { setNot(self) }

    // MARK: addSquareOf / addAbsValueOf (accumulators)

    public func addSquareOf(_ n: Int32) {
        biStat(.MBI_ADD_SQR_PRIMITIVE)
        BigIntStats.BI_OP_COUNTS[StatsOp.MBI_SET_ADD_SUB_PRIMITIVE.ordinal] -= 1
        setAdd(self, UInt64(bitPattern: Int64(n) &* Int64(n)))
    }
    @discardableResult public func addSquareOf(_ w: UInt32) -> MutableBigInt {
        BigIntStats.BI_OP_COUNTS[StatsOp.MBI_SET_ADD_SUB_PRIMITIVE.ordinal] -= 1
        biStat(.MBI_ADD_SQR_PRIMITIVE)
        return setAdd(self, UInt64(w) &* UInt64(w))
    }
    public func addSquareOf(_ l: Int64) { _ = addSquareOf(l.magnitude) }
    @discardableResult public func addSquareOf(_ dw: UInt64) -> MutableBigInt {
        biStat(.MBI_ADD_SQR_PRIMITIVE)
        let lo64 = dw &* dw
        if (dw >> 32) == 0 {
            BigIntStats.BI_OP_COUNTS[StatsOp.MBI_SET_ADD_SUB_PRIMITIVE.ordinal] -= 1
            return setAdd(self, lo64)
        }
        let hi64 = unsignedMulHi(dw, dw)        // hi64 != 0 here ⇒ 128-bit = two limbs
        if tmp1.size < 4 { tmp1 = Magia(4) }
        tmp1[0] = lo64
        tmp1[1] = hi64
        let normLen = magia_normLen(tmp1, 2)
        BigIntStats.BI_OP_COUNTS[StatsOp.MBI_SET_ADD_SUB_BI.ordinal] -= 1
        return setAddImpl(self, Meta(signBit: 0, normLen: Int32(normLen)), tmp1)
    }
    public func addSquareOf(_ bi: BigIntNumber) {
        ensureTmp1CapacityZeroed(Int(bi.meta.normLen) * 2, .MBI_RESIZE_TMP1_SQR)
        let normLenSqr = magia_setSqr(tmp1, bi.magia, Int(bi.meta.normLen))
        setAddImpl(self, Meta(signBit: 0, normLen: Int32(normLenSqr)), tmp1)
        validate()
        BigIntStats.BI_OP_COUNTS[StatsOp.MBI_SET_ADD_SUB_BI.ordinal] -= 1
        biStat(.MBI_ADD_SQR_BI)
    }

    public func addAbsValueOf(_ n: Int32) { mutAddImpl32(false, UInt64(n.magnitude)) }
    public func addAbsValueOf(_ l: Int64) { mutAddImpl64(false, l.magnitude) }
    public func addAbsValueOf(_ bi: BigIntNumber) { setAddImpl(self, bi.meta.abs(), bi.magia) }

    // MARK: compound-assignment operators (mutate the lhs accumulator)

    public static func += (lhs: MutableBigInt, n: Int32) { lhs.mutAddImpl32(n < 0, UInt64(n.magnitude)) }
    public static func += (lhs: MutableBigInt, w: UInt32) { lhs.mutAddImpl32(false, UInt64(w)) }
    public static func += (lhs: MutableBigInt, l: Int64) { lhs.mutAddImpl64(l < 0, l.magnitude) }
    public static func += (lhs: MutableBigInt, dw: UInt64) { lhs.mutAddImpl64(false, dw) }
    public static func += (lhs: MutableBigInt, bi: BigIntNumber) { lhs.mutAddImpl(bi.meta, bi.magia) }

    public static func -= (lhs: MutableBigInt, n: Int32) { lhs.mutAddImpl32(n > 0, UInt64(n.magnitude)) }
    public static func -= (lhs: MutableBigInt, w: UInt32) { lhs.mutAddImpl32(true, UInt64(w)) }
    public static func -= (lhs: MutableBigInt, l: Int64) { lhs.mutAddImpl64(l > 0, l.magnitude) }
    public static func -= (lhs: MutableBigInt, dw: UInt64) { lhs.mutAddImpl64(true, dw) }
    public static func -= (lhs: MutableBigInt, bi: BigIntNumber) { lhs.mutAddImpl(bi.meta.negate(), bi.magia) }

    public static func *= (lhs: MutableBigInt, n: Int32) { lhs.setMul(lhs, n) }
    public static func *= (lhs: MutableBigInt, w: UInt32) { lhs.setMul(lhs, w) }
    public static func *= (lhs: MutableBigInt, l: Int64) { lhs.setMul(lhs, l) }
    public static func *= (lhs: MutableBigInt, dw: UInt64) { lhs.setMul(lhs, dw) }
    public static func *= (lhs: MutableBigInt, bi: BigIntNumber) { lhs.setMul(lhs, bi) }

    public static func /= (lhs: MutableBigInt, n: Int32) { lhs.setDiv(lhs, n) }
    public static func /= (lhs: MutableBigInt, w: UInt32) { lhs.setDiv(lhs, w) }
    public static func /= (lhs: MutableBigInt, l: Int64) { lhs.setDiv(lhs, l) }
    public static func /= (lhs: MutableBigInt, dw: UInt64) { lhs.setDiv(lhs, dw) }
    public static func /= (lhs: MutableBigInt, bi: BigIntNumber) { lhs.setDiv(lhs, bi) }

    public static func %= (lhs: MutableBigInt, n: Int32) { lhs.setRem(lhs, n) }
    public static func %= (lhs: MutableBigInt, w: UInt32) { lhs.setRem(lhs, w) }
    public static func %= (lhs: MutableBigInt, l: Int64) { lhs.setRem(lhs, l) }
    public static func %= (lhs: MutableBigInt, dw: UInt64) { lhs.setRem(lhs, dw) }
    public static func %= (lhs: MutableBigInt, bi: BigIntNumber) { lhs.setRem(lhs, bi) }

    // MARK: pow / montgomeryRedc (Phase 3 BigIntAlgorithms)

    @discardableResult public func setPow(_ x: BigIntNumber, _ exp: Int) -> MutableBigInt {
        if BigIntAlgorithms.tryPowFastPath(x, exp, self) { return self }
        let base: BigIntNumber = isSame(x) ? x.toBigInt() : x   // ret must not alias base
        BigIntAlgorithms.powLeftToRight(base, exp, self)
        biStat(.MBI_SET_POW)
        return self
    }
    @discardableResult public func mutPow(_ exp: Int) -> MutableBigInt { setPow(self, exp) }

    @discardableResult public func montgomeryRedc(_ modulus: BigInt, _ np: Limb) -> MutableBigInt {
        precondition(modulus.isOdd())
        let k = Int(modulus.meta.normLen)
        precondition(Int(meta.normLen) <= 2 * k + 1)
        ensureMagiaCapacityCopy(2 * k + 1)
        let normLen = BigIntAlgorithms.montgomeryRedc(magia, Int(meta.normLen), modulus.magia, k, np)
        updateMeta(Meta(Int32(normLen)))
        biStat(.MBI_MONTGOMERY_REDC)
        return self
    }
}

// MutableBigInt: equals/hashCode intentionally omitted (non-hashable by design;
// EQ/NE on BigIntNumber provide numeric comparison).
