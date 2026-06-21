// SPDX-License-Identifier: MIT
//
// Port of BigIntParsePrint.kt — decimal/hex parse and print. Kotlin `object` →
// Swift caseless `enum`. ByteArray → [UInt8]; print buffers are mutated via
// `inout [UInt8]`. Decimal chunking stays base 1e9 (9 digits/chunk); the per-limb
// 1e9 long-division uses DWord (UInt128). Hex uses 16 nybbles per 64-bit limb.

enum BigIntParsePrint {

    // MARK: constants
    private static let ONE_E_9: UInt64 = 1_000_000_000

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
                let newLenAndRemainder = mutateDivBy1e9(tmp, limbsRemaining)
                let chunk = newLenAndRemainder & MASK32
                render9DigitsBeforeIndex(chunk, &utf8, ib)
                limbsRemaining = Int(newLenAndRemainder >> 32)
                ib -= 9
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

    /// In-place division by 1e9. Returns (newLen<<32) | remainder.
    ///
    /// At 64-bit limbs the per-limb partial dividend `combined = rem*2^64 + limb`
    /// is a 128-bit value (rem < 1e9, so combined < 2^94), divided by 1e9 with
    /// native UInt128 `/` and `%`. (The old 2^64-reciprocal Barrett trick only
    /// applied when `combined` fit in 64 bits, i.e. 32-bit limbs.)
    static func mutateDivBy1e9(_ magia: Magia, _ len: Int) -> UInt64 {
        var rem: UInt64 = 0
        precondition(magia[len - 1] != 0)
        let divisor = DWord(ONE_E_9)
        var i = len - 1
        while i >= 0 {
            let combined = (DWord(rem) << 64) | magia[i].toDw()
            magia[i] = (combined / divisor).toLimb()
            rem = (combined % divisor).toLimb()
            i -= 1
        }
        let mostSignificantLimbNonZero = magia[len - 1] != 0 ? 1 : 0
        let newLen = len - 1 + mostSignificantLimbNonZero
        return (UInt64(newLen) << 32) | (rem & MASK32)
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
        let isNeg = src.peek() == "-"
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
        let sign = src.peek() == "-"
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
        if ch == "-" || ch == "+" { ch = src.nextChar() }
        if ch == "0" {
            ch = src.nextChar()
            if ch == "x" || ch == "X" { return Int.max }
            leadingZeroSeen = true
        }
        while ch == "0" || ch == "_" {
            if ch == "_" && !leadingZeroSeen { return -1 }
            leadingZeroSeen = leadingZeroSeen || (ch == "0")
            ch = src.nextChar()
        }
        let remainingLen = src.remainingLen() + (ch == NUL ? 0 : 1)
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
        var ch: Character = NUL
        var chLast: Character = NUL
        while true {
            chLast = ch
            ch = src.nextChar()
            if ch == "_" { continue }
            if !("0"..."9").contains(ch) { break }
            let n = ch.code - 0x30
            accumulator = accumulator &* 10 &+ Limb(n)
            accumulatorDigitCount += 1
            if accumulatorDigitCount < 9 { continue }
            magia_mutateFmaPow10(z, zLen, 9, accumulator)
            accumulator = 0
            accumulatorDigitCount = 0
        }
        if ch == NUL && chLast != "_" {
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
        if ch == "+" || ch == "-" { ch = src.nextChar() }
        if ch == "0" {
            ch = src.nextChar()
            if ch == "x" || ch == "X" { ch = src.nextChar() }
            else { leadingZeroSeen = true }
        }
        while ch == "0" || ch == "_" {
            if ch == "_" && !leadingZeroSeen { return -1 }
            leadingZeroSeen = leadingZeroSeen || (ch == "0")
            ch = src.nextChar()
        }
        if ch != NUL { src.prevChar() }
        var nybbleCount = 0
        while src.hasNext() {
            ch = src.nextChar()
            if !isHexAsciiCharOrUnderscore(ch) { return -1 }
            nybbleCount += (ch == "_") ? 0 : 1
        }
        if ch == "_" { return -1 }
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
                var ch: Character
                repeat { ch = src.prevChar() } while ch == "_"
                let nybble: Int
                if ("0"..."9").contains(ch) { nybble = ch.code - 0x30 }
                else if ("A"..."F").contains(ch) { nybble = ch.code - Character("A").code + 10 }
                else if ("a"..."f").contains(ch) { nybble = ch.code - Character("a").code + 10 }
                else { fatalError() }
                w = w | (nybble << (n << 2))
            }
            z[k] = Limb(truncatingIfNeeded: w)
            nybblesLeft -= stepCount
        }
    }

    private static func isHexAsciiCharOrUnderscore(_ c: Character) -> Bool {
        // bit set per valid char: [0-9A-Fa-f_]
        let hexDigitAndUnderscoreMask: Int64 = 0x007E_8000_007E_03FF
        let idx = c.code - 0x30
        return idx >= 0 && idx <= (Character("f").code - 0x30)
            && ((hexDigitAndUnderscoreMask >> idx) & 1) != 0
    }
}
