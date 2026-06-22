import Testing
@testable import BigInt
@testable import BigIntMath

@Suite struct TestBarrettVsKnuth {

    private func checkRemainder(_ m: BigInt, _ x: BigInt) {
        let mod = MutableBigInt()
        let ctx = ModContext(m, useBarrettOnly: true)
        let r1 = ctx.modSet(x, mod)
        let r2 = x % m
        #expect(r1.toBigInt() == r2.toBigInt(), "Mismatch for x=\(x), m=\(m)")
    }

    @Test func testBarrettAgainstKnuth() {

        // ------------------------------------------------
        // 1. Small moduli
        // ------------------------------------------------
        let smallMods = [
            BigInt.from(Int32(2)),
            BigInt.from(Int32(3)),
            BigInt.from(Int32(7)),
            BigInt.from(Int32(10)),
            BigInt.from(Int32(12345))
        ]

        for m in smallMods {
            let m2 = m * m

            checkRemainder(m, BigInt.from(Int32(0)))
            checkRemainder(m, BigInt.from(Int32(1)))
            checkRemainder(m, (m - BigInt.from(Int32(1))))
            checkRemainder(m, m)
            checkRemainder(m, (m + BigInt.from(Int32(1))))
            checkRemainder(m, (m2 - BigInt.from(Int32(1))))
            checkRemainder(m, (m2.shr(1)))
        }

        // ------------------------------------------------
        // 2. Medium & large moduli (random)
        // ------------------------------------------------
        let testMods = [
            BigInt.randomWithMaxBitLen(64),
            BigInt.randomWithMaxBitLen(128),
            BigInt.randomWithMaxBitLen(192),
            BigInt.randomWithMaxBitLen(256),
            BigInt.randomWithMaxBitLen(511).withSetBit(510) // force top bit
        ]

        for m in testMods {
            let m2 = m.sqr()
            let m2BitLen = m2.magnitudeBitLen()

            // boundary points
            checkRemainder(m, m - BigInt.from(Int32(1)))
            checkRemainder(m, m)
            checkRemainder(m, m + BigInt.from(Int32(1)))
            checkRemainder(m, m2 - BigInt.from(Int32(1)))

            // random tests inside x < m²
            for _ in 0..<200 {
                var x = BigInt.randomWithMaxBitLen(m2BitLen)
                while x.compareTo(m2) >= 0 {
                    x = BigInt.randomWithMaxBitLen(m2BitLen)
                }
                checkRemainder(m, x)
            }
        }

        // ------------------------------------------------
        // 3. Pathological moduli
        // ------------------------------------------------
        let pathologicalMods = [
            (BigInt.from(Int32(1)).shl(255)) - BigInt.from(Int32(1)),       // 2^255 - 1
            (BigInt.from(Int32(1)).shl(256)) - BigInt.from(Int32(123)),     // dense
            (BigInt.from(Int32(1)).shl(300)),                               // pure power of two
            (BigInt.from(Int32(1)).shl(300)) + BigInt.from(Int32(1)),       // 2^300 + 1
            (BigInt.from(Int32(1)).shl(511))                                // sparse
        ]

        for m in pathologicalMods {
            for _ in 0..<200 {
                let x = BigInt.randomBelow(m * m)
                checkRemainder(m, x)
            }
        }

        // ------------------------------------------------
        // 4. Deterministic brute-force for small m
        // ------------------------------------------------
        for _ in 0..<20 {
            let m = BigInt.randomWithMaxBitLen(64)

            for v in 0...2000 {
                checkRemainder(m, BigInt.from(Int32(v)))
            }
        }
    }

    @Test func randomLargeBarrett() {
        let bits = [512, 1024, 1536, 2048, 3072, 4096]
        for k in bits {
            let m = BigInt.randomWithBitLen(k)
            let m2 = m * m
            for _ in 0..<1 {
                let m2bit = m2.magnitudeBitLen()
                var x: BigInt
                repeat {
                    x = BigInt.randomWithBitLen(m2bit)
                } while x.compareTo(m2) >= 0
                checkRemainder(m, x)
            }
        }
    }

    @Test func testProblem0() {
        let m = BigInt.from("12345678901234567890123")
        let x = BigInt.from("123456789012345678901234567890")
        checkRemainder(m, x)
    }

    @Test func testProblem1() {
        let m = BigInt.from("15720338158108356290")
        let x = BigInt.from("235477347269641899085489191398656418338")
        checkRemainder(m, x)
    }
}
