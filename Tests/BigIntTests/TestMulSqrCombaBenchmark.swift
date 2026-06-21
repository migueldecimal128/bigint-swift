import Testing
@testable import BigInt

/// Benchmarks set up to determine the crossover threshold for Comba-style
/// multiplication and squaring. Transliterated to correctness asserts only:
/// the timing harness (measureNano / warmup / median) is dropped; the kernels
/// are run at the original sizes and cross-checked against magia_setMul.
@Suite struct TestMulSqrCombaBenchmark {

    private func contentEquals(_ a: Magia, _ aLen: Int, _ b: Magia, _ bLen: Int) -> Bool {
        if aLen != bLen { return false }
        for i in 0..<aLen where a[i] != b[i] { return false }
        return true
    }

    private func fill(_ n: Int, _ golden32: UInt32) -> Magia {
        let a = Magia(n)
        let golden = Int32(bitPattern: golden32)
        for i in 0..<n {
            a[i] = Limb(bitPattern: Int32(truncatingIfNeeded: (i + 1) &* Int(golden)))
        }
        if a[n - 1] == 0 { a[n - 1] = 1 }
        return a
    }

    @Test func testSqrBenchmark() {
        for n in 2...24 {
            let a = fill(n, 0x9E37_79B9)
            let z = Magia(2 * n)

            let ref = Magia(2 * n)
            let refLen = magia_setMul(ref, a, n, a, n)

            let sn = magia_setSqrSchoolbook(z, a, n)
            #expect(contentEquals(z, sn, ref, refLen), "setSqrSchoolbook != setMul at n=\(n)")

            let mn = magia_setMulSchoolbook(z, a, n, a, n)
            #expect(contentEquals(z, mn, ref, refLen), "setMulSchoolbook != setMul at n=\(n)")
        }
    }

    @Test func testMulBenchmark() {
        for n in 5...10 {
            for m in 5...10 {
                let a = fill(n, 0x9E37_79B9)
                let b = fill(m, 0x6A09_E667)
                let z = Magia(m + n)

                let ref = Magia(m + n)
                let refLen = magia_setMul(ref, a, n, b, m)

                let sn = magia_setMulSchoolbook(z, a, n, b, m)
                #expect(contentEquals(z, sn, ref, refLen), "setMulSchoolbook != setMul at n=\(n) m=\(m)")
            }
        }
    }
}
