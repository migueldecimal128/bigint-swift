import Testing
@testable import BigInt

// Squaring is cross-checked against the already-verified magia_setMul(x, x) for every
// size (unrolled 1-4, schoolbook, and Karatsuba), plus small cases against a
// native UInt128 oracle.

@Suite struct MagiaSqrTests {

    private func magiaToU128(_ m: Magia, _ n: Int) -> UInt128 {
        var v: UInt128 = 0
        var i = n - 1
        while i >= 0 { v = (v << 64) | UInt128(m[i]); i -= 1 }
        return v
    }

    private func limbsEqual(_ a: Magia, _ an: Int, _ b: Magia, _ bn: Int) -> Bool {
        if an != bn { return false }
        for i in 0..<an where a[i] != b[i] { return false }
        return true
    }

    // splitmix64 deterministic generator
    private final class Rng {
        var s: UInt64 = 0xC0FF_EE12_3456_789A
        func next() -> UInt64 {
            s = s &+ 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        func magia(_ n: Int) -> Magia {
            let m = Magia(2 * n + 4)
            for i in 0..<n { m[i] = Limb(truncatingIfNeeded: next()) }
            if n > 0 && m[n - 1] == 0 { m[n - 1] = 1 }   // keep normalized
            return m
        }
    }

    @Test func smallVsU128() {
        let rng = Rng()
        // 1-limb and 2-limb squares fit in 128 bits
        for _ in 0..<2000 {
            for n in 1...2 {
                let x = rng.magia(n)
                let xv = magiaToU128(x, n)
                let z = Magia(8)
                let zn = magia_setSqr(z, x, n)
                #expect(magiaToU128(z, zn) == xv &* xv)
            }
        }
    }

    @Test func setSqrVsSetMulAllSizes() {
        let rng = Rng()
        // covers unrolled (1-4), the 5..<12 mul fallback, and schoolbook (>=12)
        for n in 1...130 {
            let x = rng.magia(n)
            let z1 = Magia(2 * n + 4)
            let z2 = Magia(2 * n + 4)
            let sn = magia_setSqr(z1, x, n)
            let mn = magia_setMul(z2, x, n, x, n)
            #expect(limbsEqual(z1, sn, z2, mn), "setSqr != setMul at n=\(n)")
        }
    }

    @Test func karatsubaVsSetMul() {
        let rng = Rng()
        // exercise Karatsuba (threshold 84) including the recursive split
        for n in [84, 85, 100, 127, 170, 256] {
            let x = rng.magia(n)
            let zK = Magia(2 * n + 4)
            let zM = Magia(2 * n + 4)
            let kn = magia_setSqrKaratsuba(zK, x, n)
            let mn = magia_setMul(zM, x, n, x, n)
            #expect(limbsEqual(zK, kn, zM, mn), "karatsuba != setMul at n=\(n)")
        }
    }

    @Test func schoolbookDirectVsSetMul() {
        let rng = Rng()
        for n in [12, 20, 50, 83] {
            let x = rng.magia(n)
            let zS = Magia(2 * n + 4)
            let zM = Magia(2 * n + 4)
            let sn = magia_setSqrSchoolbook(zS, x, n)
            let mn = magia_setMul(zM, x, n, x, n)
            #expect(limbsEqual(zS, sn, zM, mn), "setSqrSchoolbook != setMul at n=\(n)")
        }
    }
}
