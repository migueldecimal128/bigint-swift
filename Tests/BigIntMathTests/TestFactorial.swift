// SPDX-License-Identifier: MIT

import Testing
@testable import BigInt
@testable import BigIntMath

@Suite struct TestFactorial {

    @Test func testSmall() {
        #expect(BigInt.factorial(0) == BigInt.ONE)
        let accum = MutableBigInt().setOne()
        var f: UInt64 = 1
        for i in 1...20 {
            f &*= UInt64(i)
            accum *= Int32(i)
            let hi = BigInt.factorial(i)
            #expect(hi.EQ(f))
            #expect(accum.toBigInt().EQ(f))
        }
    }

    @Test func testMedium() {
        var f = BigInt.factorial(20)
        let accum = MutableBigInt().set(f)
        for i in 21...100 {
            f = f * Int32(i)
            accum *= Int32(i)
            let hi = BigInt.factorial(i)
            #expect(hi == f)
            #expect(accum.toBigInt() == f)
        }
    }

    @Test func testLarge() {
        let bigNum = 1000 // 800000

        var mul = BigInt.ONE
        for i in 2...bigNum {
            mul = mul * Int32(i)
        }

        let accum = MutableBigInt().setOne()
        for i in 2...bigNum {
            accum *= Int32(i)
        }
        let hi = BigInt.factorial(bigNum)
        #expect(hi == accum.toBigInt())
        #expect(hi == mul)
    }
}
