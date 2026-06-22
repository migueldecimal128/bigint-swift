// SPDX-License-Identifier: MIT
//
// Port of BigIntParsePrint.kt — decimal/hex parse and print. Kotlin `object` →
// Swift caseless `enum`. ByteArray → [UInt8]; print buffers are mutated via
// `inout [UInt8]`. Both decimal PARSE and PRINT chunk base 1e19 (19 digits/chunk
// — the most that fit a 64-bit limb); the per-limb print division by 1e19 uses
// the Granlund-Montgomery reciprocal-multiply (udivRecipMul, no real
// divide). Hex uses 16 nybbles per 64-bit limb.

// ASCII byte codes for the byte-oriented parser (Latin1Iterator returns Int).
private let ASCII_MINUS = 0x2D, ASCII_PLUS = 0x2B, ASCII_UNDER = 0x5F
private let ASCII_ZERO = 0x30, ASCII_NINE = 0x39
private let ASCII_x = 0x78, ASCII_X = 0x58
private let ASCII_A = 0x41, ASCII_F = 0x46, ASCII_a = 0x61, ASCII_f = 0x66

enum BigIntParsePrint {

    // MARK: constants
    private static let ONE_E_9: UInt64 = 1_000_000_000
    private static let ONE_E_19: UInt64 = 10_000_000_000_000_000_000   // 10^19 (< 2^64)
    /// Granlund-Montgomery reciprocal of 1e19: floor((2^128-1)/1e19) - 2^64.
    /// 1e19 is already normalized (0x8AC7230489E80000, bit 63 set). Computed once.
    private static let RECIP_1E19: UInt64 =
        UInt64(truncatingIfNeeded: (UInt128.max / UInt128(ONE_E_19)) - (UInt128(1) << 64))

    private static let M_U32_DIV_1E1: UInt64 = 0xCCCC_CCCD
    private static let S_U32_DIV_1E1 = 35
    private static let M_U32_DIV_1E2: UInt64 = 0x51EB_851F
    private static let S_U32_DIV_1E2 = 37
    private static let M_U64_DIV_1E4: UInt64 = 0x346D_C5D6_3886_594B
    private static let S_U64_DIV_1E4 = 11
    private static let M_1E9_DIV_1E4: UInt64 = 879_609_303
    private static let S_1E9_DIV_1E4 = 43
    private static let LOG2_10_CEIL_32: UInt64 = 14_267_572_565

    private static let HEX_PREFIX_UTF8_0x: [UInt8] = [0x30, 0x78]   // "0x"
    private static let MINUS: UInt8 = 0x2D                          // '-'
    private static let ZERO_BYTE: UInt8 = 0x30                      // '0'

    @inline(__always) private static func digitByte(_ d: UInt64) -> UInt8 {
        UInt8(truncatingIfNeeded: 0x30 &+ d)
    }

    // MARK: toString (decimal)

    static func toString(_ x: Magia, _ xNormLen: Int) -> String { toString(false, x, xNormLen) }
    static func toString(_ meta: Meta, _ magia: Magia) -> String {
        toString(meta.isNegative, magia, Int(meta.normLen))
    }
    static func toString(_ isNegative: Bool, _ magia: Magia) -> String {
        toString(isNegative, magia, magia_normLen(magia))
    }

    static func toString(_ isNegative: Bool, _ x: Magia, _ xNormLen: Int) -> String {
        if xNormLen >= 0 && xNormLen <= x.size {
            if !magia_isNormalized(x, xNormLen) { return "[not-normalized]" }
            let bitLen = magia_normBitLen(x, xNormLen)
            if bitLen < 2 {
                if bitLen == 0 { return "0" }
                return isNegative ? "-1" : "1"
            }
            let maxSignedLen = maxDigitLenFromBitLen(bitLen) + (isNegative ? 1 : 0)
            var utf8 = [UInt8](repeating: 0, count: maxSignedLen)
            let limbLen = magia_normLen(x, xNormLen)
            let t = magia_newCopyWithExactLimbLen(x, xNormLen, limbLen)
            let len = destructiveToUtf8BeforeIndex(&utf8, utf8.count, isNegative, t, limbLen)
            let startingIndex = utf8.count - len
            verify(startingIndex <= 1)
            return String(decoding: utf8[startingIndex..<utf8.count], as: UTF8.self)
        }
        fatalError()
    }

    static func maxDigitLenFromBitLen(_ bitLen: Int) -> Int {
        Int((UInt64(bitLen) &* 1_292_913_987) >> 32) + 1
    }

    static func destructiveToUtf8BeforeIndex(_ utf8: inout [UInt8], _ ibMaxx: Int,
                                             _ isNegative: Bool, _ tmp: Magia, _ tmpLen: Int) -> Int {
        if tmpLen > 0 && tmpLen <= tmp.size && tmp[tmpLen - 1] != 0 && ibMaxx > 0 && ibMaxx <= utf8.count {
            var ib = ibMaxx
            var limbsRemaining = tmpLen
            while limbsRemaining > 1 {
                let (newLen, rem) = mutateDivBy1e19(tmp, limbsRemaining)
                render19DigitsBeforeIndex(rem, &utf8, ib)
                limbsRemaining = newLen
                ib -= 19
            }
            ib -= renderTailDigitsBeforeIndex(tmp[0], &utf8, ib)
            if isNegative {
                ib -= 1
                utf8[ib] = MINUS
            }
            return utf8.count - ib
        }
        fatalError()
    }

    static func renderTailDigitsBeforeIndex(_ w: Limb, _ utf8: inout [UInt8], _ offMaxx: Int) -> Int {
        var t = UInt64(w)
        var ib = offMaxx
        while t >= 1000 {
            let t0 = unsignedMulHi(t, M_U64_DIV_1E4) >> S_U64_DIV_1E4
            let abcd = t &- (t0 &* 10000)
            t = t0
            let ab = (abcd &* M_U32_DIV_1E2) >> S_U32_DIV_1E2
            let cd = abcd &- (ab &* 100)
            let a = (ab &* M_U32_DIV_1E1) >> S_U32_DIV_1E1
            let b = ab &- (a &* 10)
            let c = (cd &* M_U32_DIV_1E1) >> S_U32_DIV_1E1
            let d = cd &- (c &* 10)
            if ib - 4 >= 0 && ib <= utf8.count {
                utf8[ib - 4] = digitByte(a)
                utf8[ib - 3] = digitByte(b)
                utf8[ib - 2] = digitByte(c)
                utf8[ib - 1] = digitByte(d)
                ib -= 4
            }
        }
        if t != 0 || w == 0 {
            repeat {
                let divTen = (t &* 0xCCCC_CCCD) >> 35
                let digit = t &- (divTen &* 10)
                ib -= 1
                utf8[ib] = digitByte(digit)
                t = divTen
            } while t != 0
        }
        return offMaxx - ib
    }

    static func render9DigitsBeforeIndex(_ dw: UInt64, _ utf8: inout [UInt8], _ offMaxx: Int) {
        verify(dw < 1_000_000_000)
        let abcde = (dw &* M_1E9_DIV_1E4) >> S_1E9_DIV_1E4
        let fghi = dw &- (abcde &* 10000)
        let abc = (abcde &* M_U32_DIV_1E2) >> S_U32_DIV_1E2
        let de = abcde &- (abc &* 100)
        let fg = (fghi &* M_U32_DIV_1E2) >> S_U32_DIV_1E2
        let hi = fghi &- (fg &* 100)
        let a = (abc &* M_U32_DIV_1E2) >> S_U32_DIV_1E2
        let bc = abc &- (a &* 100)
        let b = (bc &* M_U32_DIV_1E1) >> S_U32_DIV_1E1
        let c = bc &- (b &* 10)
        let d = (de &* M_U32_DIV_1E1) >> S_U32_DIV_1E1
        let e = de &- (d &* 10)
        let f = (fg &* M_U32_DIV_1E1) >> S_U32_DIV_1E1
        let g = fg &- (f &* 10)
        let h = (hi &* M_U32_DIV_1E1) >> S_U32_DIV_1E1
        let i = hi &- (h &* 10)
        let offMin = offMaxx - 9
        if offMin >= 0 && offMaxx <= utf8.count {
            utf8[offMaxx - 9] = digitByte(a)
            utf8[offMaxx - 8] = digitByte(b)
            utf8[offMaxx - 7] = digitByte(c)
            utf8[offMaxx - 6] = digitByte(d)
            utf8[offMaxx - 5] = digitByte(e)
            utf8[offMaxx - 4] = digitByte(f)
            utf8[offMaxx - 3] = digitByte(g)
            utf8[offMaxx - 2] = digitByte(h)
            utf8[offMaxx - 1] = digitByte(i)
        } else {
            fatalError()
        }
    }

    /// Renders `dw` (< 1e19) as exactly 19 zero-padded decimal bytes ending at
    /// `offMaxx`, composed from the 9-digit renderer plus one leading digit
    /// (top + mid + lo = 1 + 9 + 9). The constant divisors lower to magic-multiplies.
    static func render19DigitsBeforeIndex(_ dw: UInt64, _ utf8: inout [UInt8], _ offMaxx: Int) {
        verify(dw < ONE_E_19)
        let lo  = dw % 1_000_000_000
        let mid = (dw / 1_000_000_000) % 1_000_000_000
        let top = dw / 1_000_000_000_000_000_000          // single digit 0...9
        render9DigitsBeforeIndex(lo, &utf8, offMaxx)
        render9DigitsBeforeIndex(mid, &utf8, offMaxx - 9)
        if offMaxx - 19 >= 0 {
            utf8[offMaxx - 19] = digitByte(top)
        } else {
            fatalError()
        }
    }

    /// Granlund-Montgomery / Moller 2-by-1 division: divides `(high: u1, low: u0)`
    /// by the normalized invariant `d` using its precomputed reciprocal
    /// `v = floor((2^128-1)/d) - 2^64`. Requires `u1 < d`. ~2 multiplies, no divide
    /// -- far cheaper than an emulated 128/64 divide on arm64.
    /// Differential-tested against `UInt64.dividingFullWidth` (see TestUdivPreinv).
    @inline(__always)
    static func udivRecipMul(_ u1: UInt64, _ u0: UInt64, _ d: UInt64, _ v: UInt64) -> (q: UInt64, r: UInt64) {
        var (qh, ql) = u1.multipliedFullWidth(by: v)          // (qh:ql) = u1 * v
        let (sumLo, carry) = ql.addingReportingOverflow(u0)   // (qh:ql) += (u1:u0)
        ql = sumLo
        qh = qh &+ (u1 &+ 1) &+ (carry ? 1 : 0)
        var r = u0 &- qh &* d                                  // r = u0 - qh*d
        let mask: UInt64 = r > ql ? ~0 : 0                     // correction 1
        qh = qh &+ mask                                        // mask == ~0 (-1) -> qh -= 1
        r = r &+ (mask & d)
        if r >= d { r = r &- d; qh = qh &+ 1 }                // correction 2 (rare)
        return (qh, r)
    }

    /// In-place division by 1e19. Returns (newLen, remainder); `remainder` is the
    /// low 19 decimal digits (up to 1e19-1, needs the full UInt64 — hence a tuple
    /// rather than the old `(newLen<<32)|rem32` packing of the base-1e9 version).
    ///
    /// Each per-limb 2-by-1 step `(high: rem, low: limb) / 1e19` (rem < 1e19) uses
    /// the Granlund-Montgomery reciprocal-multiply (`udivRecipMul`) instead of a
    /// hardware/emulated divide. Base 1e19 (largest power of ten in a 64-bit limb)
    /// also halves the divide passes vs base 1e9.
    static func mutateDivBy1e19(_ magia: Magia, _ len: Int) -> (newLen: Int, rem: UInt64) {
        var rem: UInt64 = 0
        precondition(magia[len - 1] != 0)
        let d = ONE_E_19, v = RECIP_1E19
        var i = len - 1
        while i >= 0 {
            let (q, r) = udivRecipMul(rem, magia[i], d, v)
            magia[i] = q
            rem = r
            i -= 1
        }
        let mostSignificantLimbNonZero = magia[len - 1] != 0 ? 1 : 0
        return (len - 1 + mostSignificantLimbNonZero, rem)
    }

    // MARK: toHexString

    static func toHexString(_ bi: BigIntNumber) -> String {
        toHexString(bi, HEX_PREFIX_UTF8_0x, true, 1, [])
    }

    private static func toHexString(_ bi: BigIntNumber, _ prefixUtf8: [UInt8], _ useUpperCase: Bool,
                                    _ minPrintLength: Int, _ suffixUtf8: [UInt8]) -> String {
        let signCount = Int(bi.meta.signBit)
        let prefixCount = prefixUtf8.count
        let nybbleCount = max((magia_normBitLen(bi.magia, Int(bi.meta.normLen)) + 3) / 4, minPrintLength)
        let suffixCount = suffixUtf8.count
        let totalLen = signCount + prefixCount + nybbleCount + suffixCount
        var utf8 = [UInt8](repeating: 0, count: totalLen)
        utf8[0] = MINUS
        var ich = signCount
        for b in prefixUtf8 { utf8[ich] = b; ich += 1 }
        toHexUtf8(bi, &utf8, signCount + prefixCount, nybbleCount, useUpperCase)
        ich += nybbleCount
        for b in suffixUtf8 { utf8[ich] = b; ich += 1 }
        return String(decoding: utf8, as: UTF8.self)
    }

    static func toHexUtf8(_ bi: BigIntNumber, _ utf8: inout [UInt8], _ off: Int,
                          _ digitCount: Int, _ useUpperCase: Bool) {
        verify(bi.isNormalized())
        let alfaBase = useUpperCase ? Character("A").code : Character("a").code
        var ichMax = off + digitCount
        var limbIndex = 0
        var nybblesRemaining = 0
        var w: Limb = 0
        while ichMax > off {
            if nybblesRemaining == 0 {
                if limbIndex == Int(bi.meta.normLen) {
                    nybblesRemaining = Int.max
                    verify(w == 0)
                } else {
                    w = bi.magia[limbIndex]
                    limbIndex += 1
                    nybblesRemaining = 16
                }
            }
            let nybble = Int(w & 0x0F)
            nybblesRemaining -= 1
            w = w >> 4
            let ch = nybble < 10 ? (0x30 + nybble) : (alfaBase + (nybble - 10))
            ichMax -= 1
            utf8[ichMax] = UInt8(truncatingIfNeeded: ch)
        }
    }

    // MARK: parse (decimal / hex)

    static func from(_ src: Latin1Iterator) -> Magia {
        let bitLen = prefixDetermineBitLen(src)
        if bitLen >= 0 {
            if bitLen == 0 { return MAGIA_ZERO }
            if bitLen == Int.max { return fromHex(src.reset()) }
            let z = magia_newWithBitLen(bitLen)
            if parseHelper(src, z, z.size) { return z }
        }
        fatalError("integer parse error:\(src.stringValue)")
    }

    static func tryParseText(_ src: Latin1Iterator, _ mbi: MutableBigInt) -> Bool {
        let isNeg = src.peek() == ASCII_MINUS
        let bitLen = prefixDetermineBitLen(src)
        if bitLen < 0 { return false }
        if bitLen == 0 { mbi.setZero(); return true }
        if bitLen == Int.max { return tryParseHexText(src, mbi) }
        let limbLen = magia_limbLenFromBitLen(bitLen)
        mbi.updateMeta(Meta(0))
        mbi.ensureMagiaCapacityCopyZeroExtend(limbLen)
        if !parseHelper(src, mbi.magia, limbLen) { return false }
        let normLen = magia_normLen(mbi.magia, limbLen)
        mbi.updateMeta(Meta(signFlag: isNeg, normLen: Int32(normLen)))
        return true
    }

    static func tryParseHexText(_ src: Latin1Iterator, _ mbi: MutableBigInt) -> Bool {
        let sign = src.peek() == ASCII_MINUS
        let nybbleCount = hexNybbleCount(src)
        if nybbleCount >= 0 {
            if nybbleCount == 0 { mbi.setZero(); return true }
            mbi.updateMeta(Meta(0))
            let limbLen = (nybbleCount + 15) >> 4
            mbi.ensureMagiaCapacityDiscard(limbLen)
            parseHexHelper(src, nybbleCount, mbi.magia, limbLen)
            mbi.updateMeta(Meta(signFlag: sign, normLen: Int32(limbLen)))
            return true
        }
        return false
    }

    private static func prefixDetermineBitLen(_ src: Latin1Iterator) -> Int {
        var leadingZeroSeen = false
        var ch = src.nextChar()
        if ch == ASCII_MINUS || ch == ASCII_PLUS { ch = src.nextChar() }
        if ch == ASCII_ZERO {
            ch = src.nextChar()
            if ch == ASCII_x || ch == ASCII_X { return Int.max }
            leadingZeroSeen = true
        }
        while ch == ASCII_ZERO || ch == ASCII_UNDER {
            if ch == ASCII_UNDER && !leadingZeroSeen { return -1 }
            leadingZeroSeen = leadingZeroSeen || (ch == ASCII_ZERO)
            ch = src.nextChar()
        }
        let remainingLen = src.remainingLen() + (ch == CH_EOF ? 0 : 1)
        let roundUp32 = (UInt64(1) << 32) - 1
        let bitLen = Int((UInt64(remainingLen) &* LOG2_10_CEIL_32 &+ roundUp32) >> 32)
        if bitLen == 0 {
            if leadingZeroSeen { return 0 }
            return -1
        }
        src.prevChar()
        return bitLen
    }

    private static func parseHelper(_ src: Latin1Iterator, _ z: Magia, _ zLen: Int) -> Bool {
        var accumulator: Limb = 0
        var accumulatorDigitCount = 0
        var ch = CH_EOF
        var chLast = CH_EOF
        while true {
            chLast = ch
            ch = src.nextChar()
            if ch == ASCII_UNDER { continue }
            if ch < ASCII_ZERO || ch > ASCII_NINE { break }
            let n = ch - ASCII_ZERO
            accumulator = accumulator &* 10 &+ Limb(n)
            accumulatorDigitCount += 1
            // 19 digits is the most that fit a 64-bit accumulator (10^19 < 2^64),
            // halving the per-chunk bignum multiply-add passes vs the old base-1e9.
            if accumulatorDigitCount < 19 { continue }
            magia_mutateFmaPow10(z, zLen, 19, accumulator)
            accumulator = 0
            accumulatorDigitCount = 0
        }
        if ch == CH_EOF && chLast != ASCII_UNDER {
            if accumulatorDigitCount > 0 {
                magia_mutateFmaPow10(z, zLen, accumulatorDigitCount, accumulator)
            }
            return true
        }
        return false
    }

    static func fromHex(_ src: Latin1Iterator) -> Magia {
        let nybbleCount = hexNybbleCount(src)
        if nybbleCount >= 0 {
            if nybbleCount == 0 { return MAGIA_ZERO }
            let z = magia_newWithBitLen(nybbleCount << 2)
            parseHexHelper(src, nybbleCount, z, z.size)
            return z
        }
        fatalError("hex integer parse error")
    }

    static func hexNybbleCount(_ src: Latin1Iterator) -> Int {
        var leadingZeroSeen = false
        var ch = src.nextChar()
        if ch == ASCII_PLUS || ch == ASCII_MINUS { ch = src.nextChar() }
        if ch == ASCII_ZERO {
            ch = src.nextChar()
            if ch == ASCII_x || ch == ASCII_X { ch = src.nextChar() }
            else { leadingZeroSeen = true }
        }
        while ch == ASCII_ZERO || ch == ASCII_UNDER {
            if ch == ASCII_UNDER && !leadingZeroSeen { return -1 }
            leadingZeroSeen = leadingZeroSeen || (ch == ASCII_ZERO)
            ch = src.nextChar()
        }
        if ch != CH_EOF { src.prevChar() }
        var nybbleCount = 0
        while src.hasNext() {
            ch = src.nextChar()
            if !isHexAsciiCharOrUnderscore(ch) { return -1 }
            nybbleCount += (ch == ASCII_UNDER) ? 0 : 1
        }
        if ch == ASCII_UNDER { return -1 }
        if nybbleCount == 0 {
            if leadingZeroSeen { return 0 }
            return -1
        }
        return nybbleCount
    }

    private static func parseHexHelper(_ src: Latin1Iterator, _ nybbleCount: Int, _ z: Magia, _ zNormLen: Int) {
        var nybblesLeft = nybbleCount
        for k in 0..<z.size {
            var w = 0
            let stepCount = min(nybblesLeft, 16)
            for n in 0..<stepCount {
                var ch: Int
                repeat { ch = src.prevChar() } while ch == ASCII_UNDER
                let nybble: Int
                if ch >= ASCII_ZERO && ch <= ASCII_NINE { nybble = ch - ASCII_ZERO }
                else if ch >= ASCII_A && ch <= ASCII_F { nybble = ch - ASCII_A + 10 }
                else if ch >= ASCII_a && ch <= ASCII_f { nybble = ch - ASCII_a + 10 }
                else { fatalError() }
                w = w | (nybble << (n << 2))
            }
            z[k] = Limb(truncatingIfNeeded: w)
            nybblesLeft -= stepCount
        }
    }

    private static func isHexAsciiCharOrUnderscore(_ c: Int) -> Bool {
        // bit set per valid char: [0-9A-Fa-f_]
        let hexDigitAndUnderscoreMask: Int64 = 0x007E_8000_007E_03FF
        let idx = c - ASCII_ZERO
        return idx >= 0 && idx <= (ASCII_f - ASCII_ZERO)
            && ((hexDigitAndUnderscoreMask >> idx) & 1) != 0
    }
}
