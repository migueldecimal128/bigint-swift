import Testing
@testable import BigInt
@testable import BigIntMath

@Suite struct TestGoogolSqrt {

    @Test func testGoogolSqrt() {
        let googol = BigInt.from(Int32(10)).pow(100)
        do {
            let sqrt = googol.isqrt()
            let squared = sqrt.sqr()
            #expect(squared == googol)
        }

        let googolPlus1 = googol + Int32(1)
        do {
            let sqrt = googolPlus1.isqrt()
            let squared = sqrt.sqr()
            let diff = googolPlus1 - squared
            #expect(diff.compareTo(Int32(1)) == 0)   // diff EQ 1
        }

        let googolMinus1 = googol - Int32(1)
        do {
            let sqrt = googolMinus1.isqrt()
            let squared = sqrt.sqr()
            #expect(googolMinus1 > squared)
            let plus1Squared = (sqrt + Int32(1)).sqr()
            #expect(googolMinus1 < plus1Squared)
        }
    }
}
