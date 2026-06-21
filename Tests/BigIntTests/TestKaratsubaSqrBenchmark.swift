import Testing
@testable import BigInt

// Benchmark transliterated to correctness asserts only: the timing harness
// (measureNano / warmup / median) is dropped; the squaring kernels are run at
// representative sizes and cross-checked against magia_setMul.
@Suite struct TestKaratsubaSqrBenchmark {

    private func contentEquals(_ a: Magia, _ aLen: Int, _ b: Magia, _ bLen: Int) -> Bool {
        if aLen != bLen { return false }
        for i in 0..<aLen where a[i] != b[i] { return false }
        return true
    }

    private func fill(_ n: Int) -> Magia {
        let a = Magia(n)
        let golden = Int32(bitPattern: 0x9E37_79B9)
        for i in 0..<n {
            a[i] = Limb(bitPattern: Int32(truncatingIfNeeded: (i + 1) &* Int(golden)))
        }
        if a[n - 1] == 0 { a[n - 1] = 1 }   // keep normalized
        return a
    }

    @Test func testSqrBenchmark() {
        var n = 64
        while n <= 96 {
            let a = fill(n)
            let z = Magia(2 * n + 1)
            let k1 = (n + 1) / 2
            let t = Magia(3 * k1 + 3)

            let ref = Magia(2 * n + 1)
            let refLen = magia_setMul(ref, a, n, a, n)

            z.fill(0, 0, z.size)
            let kn = magia_setSqrKaratsuba(z, a, n, t)
            #expect(contentEquals(z, kn, ref, refLen), "Karatsuba != setMul at n=\(n)")

            let sn = magia_setSqrSchoolbook(z, a, n)
            #expect(contentEquals(z, sn, ref, refLen), "schoolbook != setMul at n=\(n)")

            n += 4
        }
    }
}
