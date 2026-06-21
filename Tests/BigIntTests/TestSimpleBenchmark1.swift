import Testing
@testable import BigInt

// Benchmark ported as a correctness smoke test: timing (measureTime), warm-up
// loops, platformName() and println are dropped per the porting conventions;
// representative iteration counts are kept so the operations actually exercise.

@Suite struct TestSimpleBenchmark1 {

    var foo = BigInt.ZERO
    let a = BigInt.from("987654321098765432109876543210")
    let b = BigInt.from("123456789012345678901234567890")
    let mbiFoo = MutableBigInt()

    @Test mutating func runBenchmark() {
        benchmarkOperations()
        benchmarkOperationsMbi()
    }

    mutating func benchmarkOperations() {
        foo = BigInt.from(Int32(0))
        for _ in 0..<1000 {
            runOperations()
        }
    }

    private mutating func runOperations() {
        let sum = a + b
        foo = foo + sum
        let diff = a - b
        foo = foo + diff
        let product = a * b
        foo = foo + product

        foo = foo + b.sqr()

        let quotient = product / a
        foo = foo + quotient
    }

    func benchmarkOperationsMbi() {
        mbiFoo.setZero()
        for _ in 0..<1000 {
            runOperationsMbi()
        }
    }

    let mbiTmp = MutableBigInt()

    private func runOperationsMbi() {
        let a = BigInt.from("987654321098765432109876543210")
        let b = BigInt.from("123456789012345678901234567890")

        mbiTmp.setAdd(a, b)
        mbiFoo += mbiTmp

        mbiTmp.setSub(a, b)
        mbiFoo += mbiTmp

        mbiTmp.setMul(a, b)
        mbiFoo += mbiTmp

        mbiFoo.addSquareOf(b)

        mbiTmp.setDiv(a, b)
        mbiFoo += mbiTmp
    }
}
