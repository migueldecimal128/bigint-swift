import Testing
@testable import BigInt

@Suite struct TestMbiMontgomeryRedc {

    @Test func testMontgomeryRedc_smallModulus() {
        // Modulus n = 3
        let n = BigInt.from(Int32(3))
        let np: Limb = (0xAAAAAAAB as Limb)  // -3^{-1} mod 2^32

        // Construct T = 2^32 + 2
        // i.e. [ low = 2 , high = 1 ]
        let t = BigInt.from((0x1_0000_0002 as UInt64)).toMutableBigInt()

        // Perform REDC(T)
        t.montgomeryRedc(n, np)

        // Now t should equal (2^32 + 2) * R^{-1} mod 3 = 2 mod 3 = 2
        #expect(t.toBigInt() == BigInt.from(Int32(2)))

        // And should be normalized
        #expect(t.isNormalized())
    }

    @Test func montgomeryRedc_roundTrip_smallX() {
        let n  = BigInt.from((0xFFFF_FFFF_FFFF_FFC5 as UInt64))
        let np = ModContext.Montgomery.computeNp(n.toUInt())

        let x  = BigInt.from(Int32(12345))

        // R = 2^(32*k), k = n.meta.normLen (here 2)
        let k  = Int(n.meta.normLen)
        let R  = BigInt.ONE.shl(32 * k)

        // x in Montgomery domain: x̄ = x * R mod n
        let t  = ((x * R) % n).toMutableBigInt()

        t.montgomeryRedc(n, np)

        // Now REDC(x̄) == x mod n
        #expect(t.toBigInt() == x)
        #expect(t.isNormalized())
    }

    @Test func testMontgomeryRedc_anotherCase() {
        let modulus = BigInt.from(Int32(3))
        let np = ModContext.Montgomery.computeNp((3 as Limb))

        let t = BigInt.from((0x1_0000_0005 as UInt64)).toMutableBigInt()

        t.montgomeryRedc(modulus, np)

        #expect(t.toBigInt() == BigInt.from(Int32(0)))
    }

    @Test func testMontgomeryRedc_twoLimbModulus() {
        let n  = BigInt.from((0xFFFF_FFFF_FFFF_FFC5 as UInt64))  // 2 limbs
        let np = ModContext.Montgomery.computeNp(n.toUInt())
        let k  = Int(n.meta.normLen)

        let x = BigInt.from(Int32(12345))

        // Construct T = x * R mod n
        let R = BigInt.ONE.shl(32 * k)
        let T = ((x * R) % n).toMutableBigInt()

        T.montgomeryRedc(n, np)

        #expect(T.toBigInt() == x)
        #expect(T.isNormalized())
    }
}
