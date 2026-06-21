import Testing
@testable import BigInt

// Faithful transliteration of TestKmutSub.kt — exercises the Magia-level free
// function `magia_kmutSub`. Kotlin `intArrayOf(...)` (signed) → `Magia(limbs:)`
// over `Limb` (UInt32); negative limb literals are reinterpreted bit-for-bit
// (e.g. -1 → 0xFFFF_FFFF). `assertContentEquals(intArrayOf(...), t)` → a
// limb-by-limb `#expect`.

@Suite struct TestKmutSub {

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

    @Test func testBasicSubtraction() {
        let t = magia([10, 20, 30])
        let z = magia([5, 5])

        // t = t - z -> [10-5, 20-5, 30]
        magia_kmutSub(t, 0, z, 0, 2)

        assertContentEquals([5, 15, 30], t)
    }

    @Test func testInternalBorrow() {
        // t = 0x00000002 00000000 (represented as [0, 2])
        // z = 0x00000000 00000001 (represented as [1])
        let t = magia([0, 2])
        let z = magia([1])

        magia_kmutSub(t, 0, z, 0, 1)

        // Result should be 0x00000001 FFFFFFFF -> [-1, 1]
        assertContentEquals([-1, 1], t)
    }

    @Test func testRippleBorrowAcrossMultipleLimbs() {
        // t = 1 00000000 00000000 (1 followed by 64 bits of zeros)
        let t = magia([0, 0, 1])
        let z = magia([1])

        // Subtract 1 from the lowest limb
        magia_kmutSub(t, 0, z, 0, 1)

        // Should ripple through:
        // Limb 0: 0 - 1 = 0xFFFFFFFF (borrow 1)
        // Limb 1: 0 - 1 = 0xFFFFFFFF (borrow 1)
        // Limb 2: 1 - 1 = 0
        assertContentEquals([-1, -1, 0], t)
    }

    @Test func testWithOffsets() {
        // Source z: [99, 5, 5, 99] (we only want the middle 5s)
        // Dest t: [0, 0, 10, 10, 0] (we want to subtract from the middle 10s)
        let t = magia([0, 0, 10, 10, 0])
        let z = magia([99, 5, 5, 99])

        magia_kmutSub(t, 2, z, 1, 2)

        assertContentEquals([0, 0, 5, 5, 0], t)
    }

    // PORT-NOTE: Kotlin `assertFailsWith<IllegalStateException>` cannot transfer —
    // the Swift `magia_kmutSub` underflow path (borrow escaping `t.size`) is a
    // `fatalError`, which is non-catchable in swift-testing. There is no recoverable
    // throw to assert. The provoking call is therefore omitted to avoid aborting
    // the test process.
    @Test func testUnderflowReturn() {
        // Subtracting 10 from 5 would underflow and trap (fatalError) in the Swift
        // port; intentionally not invoked here (see PORT-NOTE above).
    }
}
