import Testing
@testable import BigInt

@Suite struct TestKaratsubaSquare1 {

    private func mag(_ limbs: [Int32]) -> Magia {
        var a = ContiguousArray<Limb>()
        for v in limbs { a.append(Limb(bitPattern: v)) }
        return Magia(limbs: a)
    }

    private func checkKaratsubaSquare(_ a: BigInt) {
        let n = Int(a.meta.normLen)
        precondition(n >= 2)

        let z = Magia(2 * n + 2)
        let k0 = n / 2
        let k1 = n - k0
        let t = Magia(3 * k1 + 3)

        magia_karatsubaSqr(
            z, 0,
            a.magia, 0, n,
            t
        )

        let zLen = magia_normLen(z, z.size)

        let got = BigInt.fromLittleEndianIntArray(
            false,   // non-negative
            Array(z.a),
            zLen
        )
        let expect = a * a

        #expect(got == expect, "karatsubaSquare1 failed for a=\(a)")
    }

    @Test func karatsubaSquare1_len2() {
        let a = BigInt.fromLittleEndianIntArray(
            false,
            [
                Limb(0x1234_5678),
                Limb(0x9ABC_DEF0)
            ],
            2
        )
        checkKaratsubaSquare(a)
    }

    @Test func karatsubaSquare1_oddLen() {
        let a = BigInt.fromLittleEndianIntArray(
            false,
            [
                Limb(0xAAAA_AAAA),
                Limb(0xBBBB_BBBB),
                Limb(0xCCCC_CCCC)
            ],
            3
        )
        checkKaratsubaSquare(a)
    }

    @Test func karatsubaSquare1_sumCarry() {
        let a = BigInt.fromLittleEndianIntArray(
            false,
            [
                Limb(bitPattern: -1), Limb(bitPattern: -1), Limb(1)
            ],
            3
        )
        checkKaratsubaSquare(a)
    }

    @Test func karatsubaSquare1_randomWithBitLen() {
        for it in 0..<300 {
            let bitLen = 64 + it % 256   // always >= 2 limbs
            let a = BigInt.randomWithBitLen(bitLen)

            // Ensure we stay in-domain
            if a.meta.normLen >= 2 {
                checkKaratsubaSquare(a)
            }
        }
    }

    @Test func karatsubaSquare1_randomWithMaxBitLen() {
        for _ in 0..<500 {
            let a = BigInt.randomWithMaxBitLen(512)

            if a.meta.normLen >= 2 {
                checkKaratsubaSquare(a)
            }
        }
    }
}
