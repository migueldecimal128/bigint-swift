import Testing
@testable import BigInt

@Suite struct TestBigIntMulDivRem {

    private func bi(_ v: Int64) -> BigInt { BigInt.from(v) }
    private func mbi(_ v: BigInt) -> MutableBigInt { MutableBigInt().set(v) }

    // ------------------------------------------------------------
    // 1. Small deterministic tests (signs + identities)
    // ------------------------------------------------------------
    @Test func testMulSmall() {
        let cases: [(Int64, Int64)] = [
            (3, 5),
            (-3, 5),
            (3, -5),
            (-3, -5),
            (0, 7),
            (7, 0)
        ]

        for (a, b) in cases {
            let A = bi(a)
            let B = bi(b)
            let m = MutableBigInt().set(A)
            m.setMul(A, B)
            #expect(m.toBigInt() == bi(a &* b), "mul failed: \(a) * \(b)")
        }
    }

    @Test func testDivRemSmall() {
        let cases: [(Int64, Int64)] = [
            (17, 5),
            (-17, 5),
            (17, -5),
            (-17, -5),
            (1, 1),
            (-1, 1),
            (1, -1)
        ]

        for (a, b) in cases {
            let A = bi(a)
            let B = bi(b)

            let qAcc = mbi(A)
            qAcc.setDiv(A, B)

            let rAcc = mbi(A)
            rAcc.setRem(A, B)

            let q = bi(a / b)
            let r = bi(a % b)

            #expect(qAcc.toBigInt() == q, "div failed: \(a) / \(b)")
            #expect(rAcc.toBigInt() == r, "rem failed: \(a) % \(b)")
        }
    }

    @Test func testBigIntRem_Knuth_17_mod_5() {
        let x = BigInt.from(Int32(17))
        let y = BigInt.from(Int32(5))

        let r = x % y   // this forces your BigInt rem path → knuthDivide

        #expect(r == BigInt.from(Int32(2)), "BigInt remainder failed: 17 % 5")
    }

    @Test func testAccumulatorRem_Knuth_17_mod_5() {
        let x = BigInt.from(Int32(17))
        let y = BigInt.from(Int32(5))

        let m = MutableBigInt().set(x)
        m.setRem(x, y)

        #expect(m.toBigInt() == BigInt.from(Int32(2)),
                "Accumulator remainder failed: 17 % 5")
    }

    @Test func debugAccumulatorRemState_17_mod_5() {
        let x = BigInt.from(Int32(17))
        let y = BigInt.from(Int32(5))

        let m = MutableBigInt().set(x)
        m.setRem(x, y)
        // verbose println dropped
    }

    // ------------------------------------------------------------
    // 2. Div/Rem identity for small values
    // ------------------------------------------------------------
    @Test func testDivRemIdentity() {
        for a in [Int64(-20), -7, -1, 0, 1, 7, 20] {
            for b in [Int64(-7), -3, 1, 3, 7] {
                let A = bi(a)
                let B = bi(b)

                let divAcc = mbi(A)
                divAcc.setDiv(A, B)

                let remAcc = mbi(A)
                remAcc.setRem(A, B)

                let q = divAcc.toBigInt()
                let r = remAcc.toBigInt()

                // Check identity: A = B*q + r
                let lhs = A
                let rhs = B * q + r

                #expect(rhs == lhs, "identity failed for \(a), \(b)")

                // Check |r| < |b|
                #expect(r.abs() < B.abs(), "|r| < |b| violated for \(a) % \(b)")
            }
        }
    }

    // ------------------------------------------------------------
    // 3. Aliasing tests: this === x, this === y, x === y === this
    // ------------------------------------------------------------

    @Test func testMulAliasing_this_is_x() {
        let x = bi(12)
        let y = bi(7)
        let m = mbi(x)
        m.setMul(m.toBigInt(), y)
        #expect(m.toBigInt() == bi(84))
    }

    @Test func testMulAliasing_this_is_y() {
        let x = bi(12)
        let y = bi(7)
        let m = mbi(y)
        m.setMul(x, m.toBigInt())
        #expect(m.toBigInt() == bi(84))
    }

    @Test func testMulAliasing_double() {
        let x = bi(15)
        let m = mbi(x)
        m.setMul(m.toBigInt(), m.toBigInt())  // x * x
        #expect(m.toBigInt() == bi(225))
    }

    @Test func testDivAliasing_this_is_x() {
        let x = bi(35)
        let y = bi(7)
        let m = mbi(x)
        m.setDiv(m.toBigInt(), y)
        #expect(m.toBigInt() == bi(5))
    }

    @Test func testRemAliasing_this_is_x() {
        let x = bi(35)
        let y = bi(7)
        let m = mbi(x)
        m.setRem(m.toBigInt(), y)
        #expect(m.toBigInt() == bi(0))
    }

    // ------------------------------------------------------------
    // 4. Multi-limb tests
    // ------------------------------------------------------------

    @Test func testMulLargeRandom() {
        let A = BigInt.randomWithBitLen(500)
        let B = BigInt.randomWithBitLen(500)

        let m = MutableBigInt().set(A)
        m.setMul(A, B)

        #expect(m.toBigInt() == A * B)
    }

    @Test func testDivRemLargeRandom() {
        let A = BigInt.randomWithBitLen(500)
        let B = BigInt.randomWithBitLen(300).abs() + bi(1)  // avoid zero

        let qAcc = mbi(A)
        qAcc.setDiv(A, B)

        let rAcc = mbi(A)
        rAcc.setRem(A, B)

        let q = qAcc.toBigInt()
        let r = rAcc.toBigInt()

        // identity
        #expect(B * q + r == A)
        #expect(r.abs() < B.abs())
    }

    @Test func testRem_twoLimb_by_oneLimb() {
        let x = BigInt.from((0x1_0000_0000 as Int64) + 123) // 2 limbs
        let y = BigInt.from(Int32(97))
        let m = MutableBigInt().set(x)
        m.setRem(x, y)
        #expect(m.toBigInt() == x % y)
    }

    @Test func testRem_multiLimb_by_oneLimb_calcRem() {
        let x = BigInt.randomWithBitLen(300) // ~10 limbs
        let y = BigInt.from(Int32(97))
        let m = MutableBigInt().set(x)
        m.setRem(x, y)
        #expect(m.toBigInt() == x % y)
    }

    @Test func testRem_xLessThanY() {
        let x = BigInt.from(Int32(17))
        let y = BigInt.from(Int32(500))
        let m = MutableBigInt().set(x)
        m.setRem(x, y)
        #expect(m.toBigInt() == x)
    }

    @Test func testRem_twoLimb_by_twoLimb() {
        let x = BigInt.from((0x1_0000_0000 as Int64) + 123)
        let y = BigInt.from((0x2_0000_0000 as Int64) + 7)
        let m = MutableBigInt().set(x)
        m.setRem(x, y)
        #expect(m.toBigInt() == x % y)
    }

    @Test func testRem_multiLimb_by_twoLimb_knuth() {
        let x = BigInt.randomWithBitLen(300)
        let y = BigInt.randomWithBitLen(64)  // 2 limbs
        let m = MutableBigInt().set(x)
        m.setRem(x, y)
        #expect(m.toBigInt() == x % y)
    }

    @Test func testRem_knuth_multiLimb() {
        let x = BigInt.randomWithBitLen(500)
        let y = BigInt.randomWithBitLen(300)
        let m = MutableBigInt().set(x)
        m.setRem(x, y)
        #expect(m.toBigInt() == x % y)
    }

    @Test func testProblem() {
        let x = BigInt.from("2693898200269885236149444911153")
        let y = BigInt.from("874066428351266532052357330140")
        let m = MutableBigInt().set(x)
        m.setRem(x, y)
        let biRem = x % y
        let accRem = m.toBigInt()
        #expect(m.toBigInt() == x % y)
    }
}
