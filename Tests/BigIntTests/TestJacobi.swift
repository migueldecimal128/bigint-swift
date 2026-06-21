import Testing
@testable import BigInt

@Suite struct TestJacobi {

    @Test func jacobi_basic() {
        #expect(BigIntPrime.jacobi(Int32(1), BigInt.from(Int32(7))) == 1)
        #expect(BigIntPrime.jacobi(Int32(0), BigInt.from(Int32(7))) == 0)
    }

    @Test func jacobi_quadraticResidues() {
        #expect(BigIntPrime.jacobi(Int32(1), Int32(7)) == 1)
        #expect(BigIntPrime.jacobi(Int32(2), Int32(7)) == 1) // 2 is a residue mod 7
        #expect(BigIntPrime.jacobi(Int32(3), Int32(7)) == -1)
    }

    @Test func jacobi_negativeA() {
        let n = BigInt.from(Int32(11))
        #expect(BigIntPrime.jacobi(Int32(-8), n) == BigIntPrime.jacobi(Int32(3), n))
    }

    @Test func jacobi_knownValues() {
        #expect(BigIntPrime.jacobi(Int32(5), Int32(11)) == 1)
        #expect(BigIntPrime.jacobi(Int32(5), Int32(13)) == -1)
        #expect(BigIntPrime.jacobi(Int32(9), Int32(15)) == 0)
        #expect(BigIntPrime.jacobi(Int32(2), Int32(7)) == 1)
        #expect(BigIntPrime.jacobi(Int32(3), Int32(7)) == -1)
    }
}
