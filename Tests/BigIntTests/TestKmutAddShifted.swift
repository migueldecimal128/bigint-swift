import Testing
@testable import BigInt

// Faithful transliteration of TestKmutAddShifted.kt — exercises the Magia-level
// free function `magia_kmutAddShifted`. Kotlin `intArrayOf(...)` (signed) →
// `Magia(limbs:)` over `Limb` (UInt32); -1 → 0xFFFF_FFFF.

@Suite struct TestKmutAddShifted {

    /* ---------- helpers ---------- */

    private func magia(_ limbs: [Int64]) -> Magia {
        Magia(limbs: ContiguousArray(limbs.map { Limb(truncatingIfNeeded: $0) }))
    }

    private func assertContentEquals(_ expected: [Int64], _ actual: Magia) {
        #expect(actual.size == expected.count)
        for i in 0..<expected.count {
            #expect(actual[i] == Limb(truncatingIfNeeded: expected[i]), "limb \(i)")
        }
    }

    @Test func testShiftedAdditionWithRipple() {
        // z represents the result array, currently holding some values
        // Imagine z = [0, 0, 0, 0xFFFFFFFF, 0, 0]
        let z = magia([0, 0, 0, -1, 0, 0])

        // t represents the middle term to be added: [1, 1]
        let t = magia([1, 1])

        // Shift by 2: start adding t at z[2]
        // z[2] += t[0] -> 0 + 1 = 1
        // z[3] += t[1] -> 0xFFFFFFFF + 1 = 0 (carry 1)
        // z[4] (ripple) -> 0 + 1 = 1
        magia_kmutAddShifted(z, 0, t, 0, 2, 2)

        // Expected: [0, 0, 1, 0, 1, 0]
        assertContentEquals([0, 0, 1, 0, 1, 0], z)
    }

    @Test func testSimpleShiftNoRipple() {
        let z = magia([1, 1, 1, 1])
        let t = magia([2, 2])

        // Add t starting at index 1
        magia_kmutAddShifted(z, 0, t, 0, 2, 1)

        // z[1] = 1+2=3, z[2] = 1+2=3
        assertContentEquals([1, 3, 3, 1], z)
    }

    @Test func testLongDistanceRipple() {
        // z = [0, 0, -1, -1, -1, 0]
        let z = magia([0, 0, -1, -1, -1, 0])
        let t = magia([1])

        // Add t[0] at z[2].
        // z[2] becomes 0, carries to z[3]
        // z[3] becomes 0, carries to z[4]
        // z[4] becomes 0, carries to z[5]
        // z[5] becomes 1
        magia_kmutAddShifted(z, 0, t, 0, 1, 2)

        assertContentEquals([0, 0, 0, 0, 0, 1], z)
    }
}
