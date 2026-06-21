// SPDX-License-Identifier: MIT
//
// Swift realization of `intrinsic/XPlatform.kt` (the only `expect`/`actual`
// seam in bigint-kotlin). On Kotlin/JVM `unsignedMulHi` is
// `Math.unsignedMultiplyHigh`; on Kotlin/Native it is a cinterop C shim. Swift
// needs neither — `multipliedFullWidth(by:)` is built in — so the four
// platform actuals collapse into this one file.
//
// `unsignedMulHi` has 4 live call sites in the engine. Limbs are 32-bit, but
// these sites pack two adjacent 32-bit limbs into a 64-bit dword and do
// 64-bit-wide math (dword-batched squaring; divide-by-constant via
// reciprocal/Barrett for decimal I/O). It is NOT a 64-bit-limb signal.

@inline(__always)
func unsignedMulHi(_ x: UInt64, _ y: UInt64) -> UInt64 {
    x.multipliedFullWidth(by: y).high
}

@inline(__always)
func platformName() -> String {
    "swift"
}

@inline(__always)
func isJsPlatform() -> Bool {
    false
}
