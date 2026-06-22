import Testing
@testable import BigInt

@Suite struct BigIntBitSerdeTests {

    private func big(_ v: Int128) -> BigInt {
        if v == 0 { return BigInt.ZERO }
        let neg = v < 0
        let mag = v.magnitude
        let m = Magia.make(5)
        for i in 0..<2 { m[i] = Limb(truncatingIfNeeded: mag >> (i * 64)) }
        return BigInt.fromNonNormalizedOrZero(neg, m)
    }
    private func u128mag(_ x: BigIntNumber) -> UInt128 {
        var mag: UInt128 = 0
        var i = Int(x.meta.normLen) - 1
        while i >= 0 { mag = (mag << 64) | UInt128(x.magia[i]); i -= 1 }
        return mag
    }
    private func i128(_ x: BigIntNumber) -> Int128 {
        let s = Int128(u128mag(x)); return x.isNegative() ? -s : s
    }
    private final class Rng {
        var s: UInt64 = 0xBADD_CAFE_F00D_1234
        func next() -> UInt64 {
            s = s &+ 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        func u128(_ bits: Int) -> UInt128 {
            var v: UInt128 = 0
            for i in 0..<2 { v |= UInt128(next()) << (i * 64) }
            if bits < 128 { v &= (UInt128(1) << bits) - 1 }
            return v
        }
        func i128(_ bits: Int) -> Int128 {
            let mag = u128(bits)
            return (next() & 1 == 1) ? -Int128(mag) : Int128(mag)
        }
    }

    @Test func serdeKnownAndRoundTrip() {
        #expect(BigInt.from(Int32(0)).toTwosComplementBigEndianByteArray() == [0x00])
        #expect(BigInt.from(Int32(-1)).toTwosComplementBigEndianByteArray() == [0xFF])
        #expect(BigInt.from(Int32(255)).toTwosComplementBigEndianByteArray() == [0x00, 0xFF])
        #expect(BigInt.from(Int32(-256)).toTwosComplementBigEndianByteArray() == [0xFF, 0x00])
        #expect(BigInt.from(Int32(127)).toTwosComplementBigEndianByteArray() == [0x7F])

        let rng = Rng()
        for _ in 0..<8000 {
            let a = rng.i128(127)
            let bi = big(a)
            #expect(BigInt.fromTwosComplementBigEndianBytes(bi.toTwosComplementBigEndianByteArray()) == bi)
            #expect(BigInt.fromBinaryBytes(true, false, bi.toBinaryByteArray(true, false)) == bi)   // 2C, LE
            let mag = bi.abs()
            #expect(BigInt.fromBinaryBytes(false, true, mag.toBinaryByteArray(false, true)) == mag) // magnitude, BE
            #expect(BigInt.fromBinaryBytes(false, false, mag.toBinaryByteArray(false, false)) == mag)
        }
    }

    @Test func bitwiseAndShifts() {
        let rng = Rng()
        for _ in 0..<6000 {
            let a = rng.i128(120), b = rng.i128(120)
            // and/or/xor are two's-complement (vs signed Int128)
            #expect(i128(big(a).and(big(b))) == (a & b))
            #expect(i128(big(a).or(big(b))) == (a | b))
            #expect(i128(big(a).xor(big(b))) == (a ^ b))

            let small = rng.i128(60)
            let k = Int(rng.next() % 60) + 1     // 1..60
            #expect(i128(big(small).shl(k)) == small << k)                  // value, sign kept
            #expect(i128(big(small).shr(k)) == small >> k)                  // arithmetic (toward -inf)
            #expect(u128mag(big(small).ushr(k)) == (small.magnitude >> UInt128(k)))  // magnitude
        }
    }

    @Test func setClearBitMask() {
        let rng = Rng()
        for _ in 0..<4000 {
            let a = rng.u128(110)
            let k = Int(rng.next() % 126)
            #expect(u128mag(big(Int128(a)).withSetBit(k)) == (a | (UInt128(1) << k)))
            #expect(u128mag(big(Int128(a)).withClearBit(k)) == (a & ~(UInt128(1) << k)))
            let width = Int(rng.next() % 40)
            let index = Int(rng.next() % 100)
            let mask: UInt128 = width == 0 ? 0 : (((UInt128(1) << width) - 1) << index)
            #expect(u128mag(big(Int128(a)).withBitMask(width, index)) == (a & mask))
        }
    }

    @Test func hashable() {
        let a = BigInt.from("123456789012345678901234567890")
        let b = BigInt.from("123456789012345678901234567890")
        #expect(a == b && a.hashValue == b.hashValue)
        var set: Set<BigInt> = [a, b, BigInt.from(Int32(1)), BigInt.from(Int32(-1)), BigInt.ONE]
        #expect(set.count == 3)   // {a, 1, -1}
        set.insert(BigInt.from("-123456789012345678901234567890"))
        #expect(set.count == 4)
    }
}
