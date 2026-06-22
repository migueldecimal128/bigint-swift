import Testing
@testable import BigInt

/// Validates the two's-complement bitwise ops (and/or/xor/not) against Swift's
/// native signed integers (Int64 / Int128 are two's-complement), the analogue of
/// the java.math.BigInteger oracle used by bigint-kotlin. Exercises NEGATIVE
/// operands — the case the previous magnitude-only implementation got wrong.
@Suite struct TestBigIntTwosComplementBitwise {

    @Test func andOrXorVsInt64() {
        var rng = BigIntRandom(UInt64(0xBADC0DE))
        for _ in 0..<5000 {
            let a = rng.nextLong(); let b = rng.nextLong()
            let ba = BigInt.from(a); let bb = BigInt.from(b)
            #expect(ba.and(bb) == BigInt.from(a & b))
            #expect(ba.or(bb)  == BigInt.from(a | b))
            #expect(ba.xor(bb) == BigInt.from(a ^ b))
            #expect(ba.not()   == BigInt.from(~a))
        }
    }

    @Test func andOrXorVsInt128() {
        var rng = BigIntRandom(UInt64(0xFEED))
        for _ in 0..<5000 {
            let a = Int128(bitPattern: (UInt128(rng.next()) << 64) | UInt128(rng.next()))
            let b = Int128(bitPattern: (UInt128(rng.next()) << 64) | UInt128(rng.next()))
            let ba = BigInt(a); let bb = BigInt(b)
            #expect(ba.and(bb) == BigInt(a & b))
            #expect(ba.or(bb)  == BigInt(a | b))
            #expect(ba.xor(bb) == BigInt(a ^ b))
            #expect(ba.not()   == BigInt(~a))
        }
    }

    @Test func edgeBoundariesVsInt128() {
        // top-limb sign-bit boundaries the magnitude-only impl mishandled
        let vals: [Int128] = [
            Int128(1) << 63, Int128(UInt64.max), Int128(1) << 64,
            Int128(Int64.min), -(Int128(1) << 64), 1, -1, 0,
            (Int128(1) << 64) | 1, -((Int128(1) << 64) | 1)
        ]
        for a in vals { for b in vals {
            #expect(BigInt(a).and(BigInt(b)) == BigInt(a & b), "AND \(a) & \(b)")
            #expect(BigInt(a).or(BigInt(b))  == BigInt(a | b), "OR \(a) | \(b)")
            #expect(BigInt(a).xor(BigInt(b)) == BigInt(a ^ b), "XOR \(a) ^ \(b)")
            #expect(BigInt(a).not() == BigInt(~a), "NOT \(a)")
        } }
    }

    @Test func identities() {
        var rng = BigIntRandom(UInt64(0x1234))
        for _ in 0..<1000 {
            let x = BigInt.from(rng.nextLong())
            #expect(BigInt.NEG_ONE.and(x) == x)              // -1 & x == x
            #expect(BigInt.NEG_ONE.or(x) == BigInt.NEG_ONE)  // -1 | x == -1
            #expect(x.not() == x.xor(BigInt.NEG_ONE))        // ~x == x ^ -1
            #expect(x.not().not() == x)                      // ~~x == x
            #expect(x.xor(x) == BigInt.ZERO)                 // x ^ x == 0
        }
        #expect(BigInt.ZERO.not() == BigInt.NEG_ONE)         // ~0 == -1
    }

    @Test func mutableMatchesBigInt() {
        var rng = BigIntRandom(UInt64(0x77777))
        let m = MutableBigInt()
        for _ in 0..<3000 {
            let a = BigInt.from(rng.nextLong()); let b = BigInt.from(rng.nextLong())
            #expect(m.setAnd(a, b).toBigInt() == a.and(b))
            #expect(m.setOr(a, b).toBigInt()  == a.or(b))
            #expect(m.setXor(a, b).toBigInt() == a.xor(b))
            #expect(m.setNot(a).toBigInt()    == a.not())
        }
    }

    @Test func mutableAliasing() {
        var rng = BigIntRandom(UInt64(0xABCD))
        for _ in 0..<1000 {
            let a = BigInt.from(rng.nextLong()); let b = BigInt.from(rng.nextLong())
            let m = MutableBigInt(); m.set(a); m.mutAnd(b)
            #expect(m.toBigInt() == a.and(b))
            let m2 = MutableBigInt(); m2.set(a); m2.mutNot()
            #expect(m2.toBigInt() == a.not())
            let m3 = MutableBigInt(); m3.set(a); m3.setXor(m3, m3)   // self-aliasing → 0
            #expect(m3.toBigInt() == BigInt.ZERO)
        }
    }
}
