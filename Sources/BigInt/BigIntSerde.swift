// SPDX-License-Identifier: MIT
//
// Port of BigIntSerde.kt — binary (two's-complement / magnitude, big/little
// endian) byte-array I/O. Kotlin signed `Byte` → Swift `[UInt8]`; the same bit
// patterns. 64-bit limbs ⇒ 8 bytes per limb; the two's-complement carry is a
// DWord (UInt128). The partial-limb tail uses signed Int64 so two's-complement
// sign extension fills the high bytes with 0xFF for negatives.

enum BigIntSerde {

    static func toTwosComplementBigEndianByteArray(_ bi: BigIntNumber) -> [UInt8] {
        toBinaryByteArray(bi, isTwosComplement: true, isBigEndian: true)
    }

    static func toBinaryByteArray(_ bi: BigIntNumber, isTwosComplement: Bool, isBigEndian: Bool) -> [UInt8] {
        verify(bi.isNormalized())
        let n = Int(bi.meta.normLen)
        if n >= 0 && n <= bi.magia.size {
            let bitLen = isTwosComplement
                ? bi.bitLengthBigIntegerStyle() + 1
                : max(bi.magnitudeBitLen(), 1)
            let byteLen = (bitLen + 7) >> 3
            var bytes = [UInt8](repeating: 0, count: byteLen)
            _ = toBinaryBytes(bi, isTwosComplement, isBigEndian, &bytes, 0, byteLen)
            return bytes
        }
        fatalError()
    }

    @discardableResult
    static func toBinaryBytes(_ bi: BigIntNumber, _ isTwosComplement: Bool, _ isBigEndian: Bool,
                              _ bytes: inout [UInt8], _ offset: Int = 0, _ requestedLen: Int = -1) -> Int {
        verify(bi.isNormalized())
        let normLen = Int(bi.meta.normLen)
        if normLen >= 0 && normLen <= bi.magia.size && offset >= 0
            && (requestedLen <= 0 || requestedLen <= bytes.count - offset) {

            let actualLen: Int
            if requestedLen > 0 {
                actualLen = requestedLen
            } else {
                let bitLen = isTwosComplement
                    ? bi.bitLengthBigIntegerStyle() + 1
                    : max(bi.magnitudeBitLen(), 1)
                actualLen = (bitLen + 7) >> 3
            }

            let offB1 = isBigEndian ? -1 : 1
            let step1LoToHi = offB1
            let step8LoToHi = offB1 << 3        // advance one 64-bit limb (8 bytes)

            let ibLast = offset + actualLen - 1
            let ibLsb = isBigEndian ? ibLast : offset
            let ibMsb = isBigEndian ? offset : ibLast

            let negMask: UInt64 = bi.meta.isNegative ? 0xFFFF_FFFF_FFFF_FFFF : 0

            var remaining = actualLen
            var ib = ibLsb
            var iw = 0
            var carry: DWord = bi.meta.isNegative ? 1 : 0

            while remaining >= 8 && iw < normLen {
                let v = bi.magia[iw]; iw += 1
                carry = carry &+ DWord(v ^ negMask)
                let w = carry.toLimb()
                carry = carry >> 64
                var sh = 0
                for k in 0..<8 {
                    bytes[ib + k * offB1] = UInt8(truncatingIfNeeded: w >> sh)
                    sh += 8
                }
                ib += step8LoToHi
                remaining -= 8
            }
            if remaining > 0 {
                let v: Limb = iw < normLen ? { let r = bi.magia[iw]; iw += 1; return r }() : 0
                // signed: arithmetic >> sign-extends the final partial limb
                var w = Int64(bitPattern: v ^ negMask) &+ Int64(carry)
                repeat {
                    bytes[ib] = UInt8(truncatingIfNeeded: w)
                    ib += step1LoToHi
                    w = w >> 8
                    remaining -= 1
                } while remaining > 0
            }
            verify(iw == normLen)
            verify(ib - step1LoToHi == ibMsb)
            return actualLen
        }
        fatalError()
    }

    static func fromBinaryBytes(_ isNegative: Bool, _ isBigEndian: Bool,
                                _ bytes: [UInt8], _ off: Int, _ len: Int) -> Magia {
        if off < 0 || len < 0 || len > bytes.count - off { fatalError() }
        if len == 0 { return MAGIA_ZERO }

        let offB1 = isBigEndian ? -1 : 1
        let step1HiToLo = -offB1
        let step8LoToHi = offB1 << 3        // advance one 64-bit limb (8 bytes)

        let ibLast = off + len - 1
        let ibLsb = isBigEndian ? ibLast : off
        var ibMsb = isBigEndian ? off : ibLast

        let negMask: UInt64 = isNegative ? 0xFFFF_FFFF_FFFF_FFFF : 0
        let leadingFlushByte: UInt8 = isNegative ? 0xFF : 0x00

        var remaining = len
        while bytes[ibMsb] == leadingFlushByte {
            ibMsb += step1HiToLo
            remaining -= 1
            if remaining == 0 { return isNegative ? MAGIA_ONE : MAGIA_ZERO }
        }

        let magia = Magia((remaining + 7) >> 3)
        var ib = ibLsb
        var iw = 0
        var carry: DWord = isNegative ? 1 : 0

        while remaining >= 8 {
            var w: UInt64 = 0
            var sh: UInt64 = 0
            for k in 0..<8 {
                w |= UInt64(bytes[ib + k * offB1]) << sh
                sh += 8
            }
            carry = carry &+ DWord(w ^ negMask)
            magia[iw] = carry.toLimb(); iw += 1
            carry = carry >> 64
            verify((carry >> 1) == 0)
            ib += step8LoToHi
            remaining -= 8
        }
        if remaining > 0 {
            let nb = UInt8(truncatingIfNeeded: negMask)
            var w: UInt64 = 0
            for k in 0..<8 {
                // bytes present for k < remaining; sign-fill the rest with nb
                let byte: UInt8 = k < remaining ? bytes[ib + k * offB1] : nb
                w |= UInt64(byte) << (8 * k)
            }
            magia[iw] = (w ^ negMask) &+ carry.toLimb(); iw += 1
        }
        verify(iw == magia.size)
        return magia
    }

    static func magnitudeToLittleEndianIntArray(_ bi: BigIntNumber) -> [Limb] {
        Array(bi.magia.a[0..<Int(bi.meta.normLen)])
    }

    static func magnitudeToLittleEndianLongArray(_ bi: BigIntNumber) -> [UInt64] {
        // At 64-bit limbs a limb IS a UInt64, so the old pair-join (two 32-bit
        // limbs per UInt64) collapses to a straight copy of the magnitude limbs.
        Array(bi.magia.a[0..<Int(bi.meta.normLen)])
    }
}
