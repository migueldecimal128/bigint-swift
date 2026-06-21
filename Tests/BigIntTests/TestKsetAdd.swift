import Testing
@testable import BigInt

/// Tests for:
///   func magia_ksetAdd(_ t: Magia, _ a: Magia, _ aOff: Int, _ k0: Int, _ k1: Int)
///
/// Assumptions:
/// - Limbs are 32-bit, little-endian (limb 0 is least significant), unsigned.
/// - k0 limbs are added pairwise; if k1>k0 then one extra limb from a1 is added
///   with carry; final carry stored at t[k1].
@Suite struct TestKsetAdd {

    // Build a Magia from signed Int literals (Kotlin intArrayOf), reinterpreting
    // each as an unsigned 32-bit limb (-1 -> 0xFFFFFFFF).
    private func magia(_ vals: [Int32]) -> Magia {
        var limbs = ContiguousArray<Limb>()
        for v in vals { limbs.append(Limb(bitPattern: Int64(v))) }
        return Magia(limbs: limbs)
    }

    // Compare a Magia's limbs (over its full size) against expected signed Ints.
    private func contentEquals(_ expected: [Int32], _ t: Magia) -> Bool {
        guard t.size == expected.count else { return false }
        for i in 0..<expected.count where t[i] != Limb(bitPattern: Int64(expected[i])) {
            return false
        }
        return true
    }

    @Test func testStandardAdditionNoCarry() {
        let a = magia([1, 2, 3, 4]) // x0=[1,2], x1=[3,4]
        let t = Magia(3)

        // k0=2, k1=2 (even split)
        magia_ksetAdd(t, a, 0, 2, 2)

        // Expected: t[0]=1+3=4, t[1]=2+4=6, t[2]=carry=0
        #expect(contentEquals([4, 6, 0], t))
    }

    @Test func testAdditionWithCarryPropagatingToEnd() {
        let a = magia([-1, -1, 1, 0]) // -1 is 0xFFFFFFFF in bits
        let t = Magia(3)

        magia_ksetAdd(t, a, 0, 2, 2)

        // 0xFFFFFFFF + 1 = 0x100000000 (Result 0, carry 1)
        // 0xFFFFFFFF + 0 + carry(1) = 0x100000000 (Result 0, carry 1)
        #expect(contentEquals([0, 0, 1], t))
    }

    @Test func testUnevenSplitExtraLimb() {
        // a = [1, 2, 10, 20, 30]
        // x0 = [1, 2] (k0=2)
        // x1 = [10, 20, 30] (k1=3)
        let a = magia([1, 2, 10, 20, 30])
        let t = Magia(4)

        magia_ksetAdd(t, a, 0, 2, 3)

        // t[0] = 1 + 10 = 11
        // t[1] = 2 + 20 = 22
        // t[2] = 30 + carry(0) = 30
        // t[3] = carry = 0
        #expect(contentEquals([11, 22, 30, 0], t))
    }

    @Test func testOffsetAddition() {
        let a = magia([0, 0, 5, 5, 10, 10, 0])
        let t = Magia(3)

        // Start at index 2
        magia_ksetAdd(t, a, 2, 2, 2)

        // x0=[5,5], x1=[10,10]
        #expect(contentEquals([15, 15, 0], t))
    }

    // PORT-NOTE: testBoundsChecking — Kotlin asserts assertFailsWith<
    // IllegalArgumentException> for magia_ksetAdd(t, a, 0, 1, 2) with t.size too
    // small. In Swift the bounds violation calls fatalError(), which
    // swift-testing cannot catch; this case is dropped.
}
