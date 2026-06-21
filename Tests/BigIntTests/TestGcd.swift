// SPDX-License-Identifier: MIT

import Testing
@testable import BigInt

@Suite struct TestGcd {

    @Test func testGcd() {
        for _ in 0..<10000 {
            test1(Int(BigIntRandom.Default.nextInt(Int32(8))))
        }
    }

    private func test1(_ bitLen: Int) {
        let x = BigInt.randomWithMaxBitLen(bitLen, withRandomSign: true)
        let y = BigInt.randomWithMaxBitLen(bitLen, withRandomSign: true)

        testSymmetry(x, y)
        testIdempotence(x)
        testZero(x)
        testSigns(x, y)

        let k = BigInt.randomWithMaxBitLen(Int(BigIntRandom.Default.nextInt(Int32(29))))
        let a = x * k
        let b = y * k

        let gcdAB = BigInt.gcd(a, b)
        let gcdXY = BigInt.gcd(x, y)
        #expect(k * gcdXY == gcdAB)
    }

    private func testSymmetry(_ x: BigInt, _ y: BigInt) {
        let gcdXY = BigInt.gcd(x, y)
        let gcdYX = BigInt.gcd(y, x)
        #expect(gcdYX == gcdXY)
    }

    private func testIdempotence(_ x: BigInt) {
        let gcdXX = BigInt.gcd(x, x)
        #expect(x.abs() == gcdXX)
    }

    private func testZero(_ x: BigInt) {
        let gcdXZero = BigInt.gcd(x, BigInt.ZERO)
        let gcdZeroX = BigInt.gcd(BigInt.from(Int32(0)), x)
        #expect(x.abs() == gcdXZero)
        #expect(x.abs() == gcdZeroX)
    }

    private func testSigns(_ x: BigInt, _ y: BigInt) {
        let gcd0 = BigInt.gcd(x, y)
        let gcd1 = BigInt.gcd(x, y.negate())
        let gcd2 = BigInt.gcd(x.negate(), y)
        let gcd3 = BigInt.gcd(x.negate(), y.negate())

        #expect(gcd1 == gcd0)
        #expect(gcd2 == gcd0)
        #expect(gcd3 == gcd0)
    }

    @Test func testProblemChild() {
        let x = BigInt.from("75739105468096430")
        let y = BigInt.from("112746730774794142")
        testSymmetry(x, y)
    }

    @Test func testProblemChild2() {
        let x = BigInt.from("4")
        let y = BigInt.from("1")
        testSymmetry(x, y)
    }

    @Test func testProblemChild3() {
        let x = BigInt.from("-39")
        let y = BigInt.from("-39")
        let k = BigInt.from("115399892")
        let a = k * x
        let b = k * y
        let gcdAB = BigInt.gcd(a, b)
        let gcdXY = BigInt.gcd(x, y)
        let gcdXY_k = k * gcdXY
        #expect(gcdAB == gcdXY_k)
    }
}
