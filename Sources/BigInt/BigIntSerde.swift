// SPDX-License-Identifier: MIT
//
// Port of BigIntSerde.kt — binary (two's-complement / magnitude, big/little
// endian) byte-array I/O. Kotlin signed `Byte` → Swift `[UInt8]`; the same bit
// patterns. The partial-limb tail uses signed Int64 so two's-complement sign
// extension fills the high bytes with 0xFF for negatives.

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
            let offB2 = offB1 << 1
            let offB3 = offB1 + offB2
            let step1LoToHi = offB1
            let step4LoToHi = offB1 << 2

            let ibLast = offset + actualLen - 1
            let ibLsb = isBigEndian ? ibLast : offset
            let ibMsb = isBigEndian ? offset : ibLast

            let negMask: UInt32 = bi.meta.isNegative ? 0xFFFF_FFFF : 0
            let negByte = UInt8(truncatingIfNeeded: negMask)

            var remaining = actualLen
            var ib = ibLsb
            var iw = 0
            var carry: UInt64 = bi.meta.isNegative ? 1 : 0

            while remaining >= 4 && iw < normLen {
                let v = bi.magia[iw]; iw += 1
                carry = carry &+ UInt64(v ^ negMask)
                let w = carry.toLimb()
                carry = carry >> 32
                bytes[ib + offB3] = UInt8(truncatingIfNeeded: w >> 24)
                bytes[ib + offB2] = UInt8(truncatingIfNeeded: w >> 16)
                bytes[ib + offB1] = UInt8(truncatingIfNeeded: w >> 8)
                bytes[ib] = UInt8(truncatingIfNeeded: w)
                ib += step4LoToHi
                remaining -= 4
            }
            if remaining > 0 {
                let v: Limb = iw < normLen ? { let r = bi.magia[iw]; iw += 1; return r }() : 0
                // signed: arithmetic >> sign-extends the final partial limb
                var w = Int64(Int32(bitPattern: v ^ negMask)) &+ Int64(carry)
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
        let offB2 = offB1 << 1
        let offB3 = offB1 + offB2
        let step1HiToLo = -offB1
        let step4LoToHi = offB1 << 2

        let ibLast = off + len - 1
        let ibLsb = isBigEndian ? ibLast : off
        var ibMsb = isBigEndian ? off : ibLast

        let negMask: UInt32 = isNegative ? 0xFFFF_FFFF : 0
        let leadingFlushByte: UInt8 = isNegative ? 0xFF : 0x00

        var remaining = len
        while bytes[ibMsb] == leadingFlushByte {
            ibMsb += step1HiToLo
            remaining -= 1
            if remaining == 0 { return isNegative ? MAGIA_ONE : MAGIA_ZERO }
        }

        let magia = Magia((remaining + 3) >> 2)
        var ib = ibLsb
        var iw = 0
        var carry: UInt64 = isNegative ? 1 : 0

        while remaining >= 4 {
            let w = (UInt32(bytes[ib + offB3]) << 24) | (UInt32(bytes[ib + offB2]) << 16)
                  | (UInt32(bytes[ib + offB1]) << 8) | UInt32(bytes[ib])
            carry = carry &+ UInt64(w ^ negMask)
            magia[iw] = carry.toLimb(); iw += 1
            carry = carry >> 32
            verify((carry >> 1) == 0)
            ib += step4LoToHi
            remaining -= 4
        }
        if remaining > 0 {
            let nb = UInt8(truncatingIfNeeded: negMask)
            let b3 = nb
            let b2 = remaining == 3 ? bytes[ib + offB2] : nb
            let b1 = remaining >= 2 ? bytes[ib + offB1] : nb
            let b0 = bytes[ib]
            let w = (UInt32(b3) << 24) | (UInt32(b2) << 16) | (UInt32(b1) << 8) | UInt32(b0)
            magia[iw] = (w ^ negMask) &+ carry.toLimb(); iw += 1
        }
        verify(iw == magia.size)
        return magia
    }

    static func magnitudeToLittleEndianIntArray(_ bi: BigIntNumber) -> [Limb] {
        Array(bi.magia.a[0..<Int(bi.meta.normLen)])
    }

    static func magnitudeToLittleEndianLongArray(_ bi: BigIntNumber) -> [UInt64] {
        let intLen = Int(bi.meta.normLen)
        let longLen = (intLen + 1) >> 1
        var z = [UInt64](repeating: 0, count: longLen)
        var iw = 0
        var il = 0
        while intLen - iw >= 2 {
            let lo = UInt64(bi.magia[iw])
            let hi = UInt64(bi.magia[iw + 1]) << 32
            z[il] = hi | lo
            il += 1
            iw += 2
        }
        if iw < intLen { z[il] = UInt64(bi.magia[iw]) }
        return z
    }
}
