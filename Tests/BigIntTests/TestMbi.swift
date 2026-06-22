import Testing
@testable import BigInt

// PORT-NOTE: `BigIntRandom` has no bounded `nextLong(bound)` (surface is
// nextLong() only). All Kotlin call sites use power-of-two bounds (`1L shl n`),
// so they are reproduced exactly by masking `nextLong()` with `(1 << n) - 1`.

@Suite struct TestMbi {

    let verbose = false

    private let rng = BigIntRandom.Default

    @Test func testMutableBigInt() {
        let count = 10
        for _ in 0..<count {
            testAddSub()
            testMul()
            testAddAbsValue()
            testAddSquareOf()
        }
    }

    private func testEQ(_ bi: BigInt, _ mbi: MutableBigInt) -> Bool {
        if bi.EQ(mbi.toBigInt()) {
            return true
        }
        return false
    }

    @Test func testAddSub() {
        let mbi = MutableBigInt()
        var bi = BigInt.ZERO

        for _ in 0..<Int(rng.nextInt(Int32(1000))) {
            let n = randomInt()
            bi = bi + n
            mbi += n
            #expect(bi.EQ(mbi.toBigInt()))
        }
        #expect(bi.EQ(mbi.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(1000))) {
            let w = randomUInt()
            mbi += w
            bi = bi + w
        }
        #expect(bi.EQ(mbi.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(1000))) {
            let l = randomLong()
            mbi += l
            bi = bi + l
        }
        #expect(bi.EQ(mbi.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(1000))) {
            let dw = randomULong()
            mbi += dw
            bi = bi + dw
        }
        #expect(bi.EQ(mbi.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(100))) {
            let rand = BigInt.randomWithBitLen(31)
            mbi += rand
            bi = bi + rand
            #expect(testEQ(bi, mbi))
        }
        #expect(testEQ(bi, mbi))

        for _ in 0..<5 {
            mbi += mbi
            bi = bi + bi
            #expect(testEQ(bi, mbi))
        }
        #expect(testEQ(bi, mbi))

        // now start subtracting

        for _ in 0..<Int(rng.nextInt(Int32(1000))) {
            let n = randomInt()
            mbi -= n
            bi = bi - n
            #expect(testEQ(bi, mbi))
        }
        #expect(testEQ(bi, mbi))

        for _ in 0..<Int(rng.nextInt(Int32(1000))) {
            let w = randomUInt()
            mbi -= w
            bi = bi - w
            #expect(testEQ(bi, mbi))
        }

        for _ in 0..<Int(rng.nextInt(Int32(1000))) {
            let l = randomLong()
            mbi -= l
            bi = bi - l
            #expect(testEQ(bi, mbi))
        }

        for _ in 0..<Int(rng.nextInt(Int32(1000))) {
            let dw = randomULong()
            mbi -= dw
            bi = bi - dw
            #expect(testEQ(bi, mbi))
        }

        for _ in 0..<Int(rng.nextInt(Int32(100))) {
            let rand = randomBigInt(200)
            mbi -= rand
            bi = bi - rand
            #expect(testEQ(bi, mbi))
        }

        mbi -= mbi
        bi = bi - bi
        #expect(testEQ(bi, mbi))
    }

    @Test func testMul() {
        let hia = MutableBigInt().setOne()
        var hi = BigInt.ONE

        for _ in 0..<200 {
            let rand = randomInt()
            if rand == 0 {
                continue
            }
            hi = hi * rand
            hia *= rand
            #expect(hi.EQ(hia.toBigInt()))
        }
        #expect(hi.EQ(hia.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(10))) {
            let rand = randomUInt()
            if rand == 0 {
                continue
            }
            hia *= rand
            hi = hi * rand
        }
        #expect(hi.EQ(hia.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(10))) {
            let rand = randomLong()
            if rand == 0 {
                continue
            }
            hia *= rand
            hi = hi * rand
        }
        #expect(hi.EQ(hia.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(1000))) {
            let rand = randomULong()
            if rand == 0 {
                continue
            }
            hi = hi * rand
            hia *= rand
            #expect(hi.EQ(hia.toBigInt()))
        }
        #expect(hi.EQ(hia.toBigInt()))

        for _ in 0..<10 {
            let rand = randomBigInt(400)
            if rand.compareTo(Int32(2)) < 0 {
                continue
            }
            hi = hi * rand
            hia *= rand
            #expect(hi.EQ(hia.toBigInt()))
        }
        #expect(hi.EQ(hia.toBigInt()))

        for _ in 0..<3 {
            hia *= hia
            hi = hi * hi
        }
        #expect(hi.EQ(hia.toBigInt()))
    }

    @Test func testProblem() {
        let bia1 = MutableBigInt().set(Int32(3))
        let bia2 = MutableBigInt().set(Int32(2))
        bia1 *= bia2
        bia1 *= bia2
        #expect(testEQ(BigInt.from(Int32(12)), bia1))
    }

    @Test func testAddAbsValue() {
        let hia = MutableBigInt()
        var hi = BigInt.ZERO

        for _ in 0..<10 {
            let rand = randomInt()
            hia.addAbsValueOf(rand)
            hi = hi + BigInt.from(Int64(Int(rand).magnitude))
            #expect(hi.EQ(hia.toBigInt()))
        }
        #expect(hi.EQ(hia.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(10))) {
            let rand = randomLong()
            hia.addAbsValueOf(rand)
            hi = hi + BigInt.from(rand.magnitude)
            #expect(hi.EQ(hia.toBigInt()))
        }
        #expect(hi.EQ(hia.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(10))) {
            let rand = randomBigInt(200)
            hi = hi + rand.abs()
            hia.addAbsValueOf(rand)
            #expect(hi.EQ(hia.toBigInt()))
        }
        #expect(hi.EQ(hia.toBigInt()))

        hia.set(Int32(3))
        hi = BigInt.from(Int32(3))

        for _ in 0..<3 {
            hi = hi + hi.abs()
            hia.addAbsValueOf(hia)
            #expect(hi.EQ(hia.toBigInt()))
        }
    }

    @Test func testAddSquareOf() {
        let hia = MutableBigInt()
        var hi = BigInt.ZERO

        for _ in 0..<Int(rng.nextInt(Int32(10))) {
            let rand = randomInt()
            hia.addSquareOf(rand)
            let mag = Int64(Int(rand).magnitude)
            hi = hi + (mag &* mag)
        }
        #expect(hi.EQ(hia.toBigInt()))

        hia.setZero()
        hi = BigInt.ZERO
        for _ in 0..<Int(rng.nextInt(Int32(10))) {
            let rand = randomUInt()
            hia.addSquareOf(rand)
            hi = hi + (UInt64(rand) &* UInt64(rand))
        }
        #expect(hi.EQ(hia.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(10))) {
            let rand = randomLong()
            hia.addSquareOf(rand)
            hi = hi + BigInt.from(rand).sqr()
        }
        #expect(hi.EQ(hia.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(10))) {
            let rand = randomULong()
            hia.addSquareOf(rand)
            hi = hi + BigInt.from(rand).sqr()
        }
        #expect(hi.EQ(hia.toBigInt()))

        for _ in 0..<Int(rng.nextInt(Int32(10))) {
            let rand = randomBigInt(10)
            if rand.isZero() {
                continue
            }
            hia.addSquareOf(rand)
            hi = hi + (rng.nextBoolean() ? rand.sqr() : rand * rand)
        }
        #expect(hi.EQ(hia.toBigInt()))

        for _ in 0..<3 {
            hia.addSquareOf(hia)
            hi = hi + (rng.nextBoolean() ? hi.sqr() : hi * hi)
        }
        #expect(hi.EQ(hia.toBigInt()))
    }

    private func randomBigInt(_ hiBitLen: Int) -> BigInt {
        let n = Int(rng.nextInt(Int32(hiBitLen)))
        let v = BigInt.randomWithMaxBitLen(n, rng)
        return rng.nextBoolean() ? v.negated() : v
    }

    private func randomInt() -> Int32 {
        let n = Int(rng.nextInt(Int32(31)))
        let v = rng.nextInt(Int32(1 << n))
        return rng.nextBoolean() ? -v : v
    }

    private func randomUInt() -> UInt32 {
        // PORT-NOTE: no bounded nextLong; `nextLong(1L shl n)` == masked nextLong().
        let n = Int(rng.nextInt(Int32(33)))
        let bounded = UInt64(bitPattern: rng.nextLong()) & ((UInt64(1) << n) - 1)
        return UInt32(truncatingIfNeeded: bounded)
    }

    private func randomLong() -> Int64 {
        let n = Int(rng.nextInt(Int32(63)))
        let v = rng.nextLong() & ((Int64(1) << n) - 1)
        return rng.nextBoolean() ? -v : v
    }

    private func randomULong() -> UInt64 {
        let n = Int(rng.nextInt(Int32(64)))
        let v: Int64
        if n < 63 {
            v = ((rng.nextLong() & ((Int64(1) << n) - 1)) << 1) &+ Int64(rng.nextInt(Int32(2)))
        } else {
            v = rng.nextLong()
        }
        return UInt64(bitPattern: v)
    }
}
