import Testing
@testable import BigInt

@Suite struct TestKaratsubaSetSqr {

    // Builds a Magia from signed limb literals (Kotlin's `intArrayOf` over Int).
    private func mag(_ limbs: [Int32]) -> Magia {
        var a = ContiguousArray<Limb>()
        for v in limbs { a.append(Limb(bitPattern: Int64(v))) }
        return Magia(limbs: a)
    }

    private func contentEquals(_ a: Magia, _ b: Magia) -> Bool {
        if a.size != b.size { return false }
        for i in 0..<a.size where a[i] != b[i] { return false }
        return true
    }

    // Helper to verify results against a simpler schoolbook implementation.
    private func verifySquare(_ a: Magia) {
        let n = a.size
        let zKaratsuba = Magia(2 * n + 1)
        let zSchoolbook = Magia(2 * n + 1)

        // Workspace size based on the formula: 3 * k1 + 3
        let k1 = n - (n / 2)
        let t = Magia(3 * k1 + 3)

        // 1. Run Karatsuba
        magia_karatsubaSqr(zKaratsuba, 0, a, 0, n, t)

        // 2. Run Schoolbook (Reference)
        _ = magia_setSqrSchoolbook(zSchoolbook, 0, a, 0, n)

        #expect(contentEquals(zKaratsuba, zSchoolbook), "Karatsuba squaring failed for size \(n)")
    }

    @Test func testSmallSquare() {
        verifySquare(mag([0x1234_5678]))
    }

    @Test func testMiddleSquare() {
        verifySquare(mag([1, 2]))
        verifySquare(mag([-2, -3]))
    }

    @Test func test3Limbs() {
        verifySquare(mag([1, 2, 3]))
    }

    @Test func test3LimbsHi() {
        verifySquare(mag([1, 1, Int32(bitPattern: 0x7FFF_FFFF)]))
        verifySquare(mag([1, 1, Int32(bitPattern: 0x8000_0000)]))
    }

    @Test func testLargeSquarePowerOfTwo() {
        verifySquare(mag([0x7FFF_FFFF, 0x7FFF_FFFF, 0x7FFF_FFFF, 0x7FFF_FFFF]))
    }

    @Test func testLargeSquareOddSize() {
        verifySquare(mag([1, 2, 3, 4, 5]))
    }

    @Test func testCarryPropagation() {
        for i in 2..<20 {
            let a = Magia(i)
            for j in 0..<i { a[j] = Limb(bitPattern: -1) }
            verifySquare(a)
        }
    }

    @Test func testCarryPropagationX() {
        let a = Magia(4)
        for j in 0..<4 { a[j] = Limb(bitPattern: -1) }
        verifySquare(a)
    }

    @Test func testZeroValues() {
        verifySquare(Magia(2))
    }

    @Test func testTwo() {
        verifySquare(mag([2, 3]))
    }

    @Test func testOffsetHandling() {
        let a = mag([0, 0, 1, 2, 3, 4, 0])
        let z = Magia(12)
        let t = Magia(3 * 2 + 3)

        // Square the middle 4 elements [1, 2, 3, 4] into z starting at index 2
        magia_karatsubaSqr(z, 2, a, 2, 4, t)

        let expectedResult = Magia(8)
        _ = magia_setSqrSchoolbook(expectedResult, 0, mag([1, 2, 3, 4]), 0, 4)

        // Verify z[2..9] matches the expected square
        for i in 0..<8 {
            #expect(z[i + 2] == expectedResult[i], "Mismatch at index \(i + 2)")
        }
    }
}
