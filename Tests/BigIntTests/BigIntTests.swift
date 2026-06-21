import Testing
@testable import BigInt

// Placeholder until Phase 1 engine tests land. Confirms the intrinsic shim.
@Test func intrinsicShim() {
    #expect(platformName() == "swift")
    #expect(isJsPlatform() == false)
    // 2^32 * 2^32 = 2^64, so high word of (2^32 * 2^32) == 1.
    #expect(unsignedMulHi(1 << 32, 1 << 32) == 1)
    #expect(unsignedMulHi(0, 0) == 0)
}
