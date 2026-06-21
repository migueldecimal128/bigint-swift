import Testing
@testable import BigInt

@Suite struct BigIntAlgorithmsTests {

    private func big(_ v: Int128) -> BigInt {
        if v == 0 { return BigInt.ZERO }
        let neg = v < 0
        let mag = v.magnitude
        let m = Magia(6)
        for i in 0..<5 { m[i] = Limb(truncatingIfNeeded: mag >> (i * 32)) }
        return BigInt.fromNonNormalizedOrZero(neg, m)
    }
    private final class Rng {
        var s: UInt64 = 0x9988_7766_5544_3322
        func next() -> UInt64 {
            s = s &+ 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        func u128(_ bits: Int) -> UInt128 {
            var v: UInt128 = 0
            for i in 0..<4 { v |= UInt128(Limb(truncatingIfNeeded: next())) << (i * 32) }
            if bits < 128 { v &= (UInt128(1) << bits) - 1 }
            return v
        }
        func i128(_ bits: Int) -> Int128 {
            let mag = u128(bits)
            return (next() & 1 == 1) ? -Int128(mag) : Int128(mag)
        }
    }
    private func ngcd(_ a: UInt128, _ b: UInt128) -> UInt128 {
        var x = a, y = b
        while y != 0 { let t = x % y; x = y; y = t }
        return x
    }

    @Test func pow() {
        for base in [Int32(-3), -2, -1, 0, 1, 2, 3, 7, 10] {
            var acc = BigInt.ONE
            for e in 0...45 {
                #expect(BigInt.from(base).pow(e) == acc, "\(base)^\(e)")
                acc = acc * BigInt.from(base)
            }
        }
        #expect(BigInt.from(Int32(2)).pow(200).toHexString() == "0x1" + String(repeating: "0", count: 50))
        #expect(BigInt.from(Int32(10)).pow(100).toString() == "1" + String(repeating: "0", count: 100))
        #expect(BigInt.from(Int32(-2)).pow(7).toString() == "-128")
    }

    @Test func setPowMatchesPow() {
        let rng = Rng()
        for _ in 0..<2000 {
            let base = rng.i128(40)
            let e = Int(rng.next() % 20)
            #expect(MutableBigInt().setPow(big(base), e).toBigInt() == big(base).pow(e))
        }
    }

    @Test func gcdAndLcm() {
        let rng = Rng()
        for _ in 0..<6000 {
            let a = rng.i128(120), b = rng.i128(120)
            let g = BigInt.gcd(big(a), big(b))
            #expect(g.toString() == String(ngcd(a.magnitude, b.magnitude)))
            // gcd * lcm == |a*b|  (for non-zero)
            if a != 0 && b != 0 {
                let lcm = BigInt.lcm(big(a), big(b))
                #expect((g * lcm) == (big(a).abs() * big(b).abs()))
            }
        }
        #expect(BigInt.gcd(BigInt.from(Int32(0)), BigInt.from(Int32(-12))).toString() == "12")
    }

    @Test func isqrtProperty() {
        let rng = Rng()
        for _ in 0..<6000 {
            let n = big(Int128(rng.u128(126)))     // non-negative, up to 126-bit
            let r = n.isqrt()
            #expect(r.sqr().compareTo(n) <= 0)                       // r^2 <= n
            #expect((r + BigInt.ONE).sqr().compareTo(n) > 0)         // (r+1)^2 > n
        }
        // exact large squares: isqrt(10^100) == 10^50
        let tenTo50 = BigInt.from("1" + String(repeating: "0", count: 50))
        let tenTo100 = BigInt.from("1" + String(repeating: "0", count: 100))
        #expect(tenTo100.isqrt() == tenTo50)
        #expect(BigInt.from(Int32(0)).isqrt() == BigInt.ZERO)
        #expect(BigInt.from(Int32(1)).isqrt() == BigInt.ONE)
    }

    @Test func isPerfectSquare() {
        let rng = Rng()
        for _ in 0..<3000 {
            let k = big(Int128(rng.u128(60)))
            #expect(k.sqr().isPerfectSquare())
            if !k.isZero() {
                #expect(!(k.sqr() + BigInt.ONE).isPerfectSquare())   // k^2+1 never a square (k>=1)
            }
        }
    }

    @Test func factorial() {
        #expect(BigInt.factorial(0).toString() == "1")
        #expect(BigInt.factorial(1).toString() == "1")
        #expect(BigInt.factorial(5).toString() == "120")
        #expect(BigInt.factorial(20).toString() == "2432902008176640000")
        #expect(BigInt.factorial(25).toString() == "15511210043330985984000000")
        // n! / (n-1)! == n
        for n in 2...60 {
            #expect((BigInt.factorial(n) / BigInt.factorial(n - 1)) == BigInt.from(Int32(n)))
        }
    }
}
