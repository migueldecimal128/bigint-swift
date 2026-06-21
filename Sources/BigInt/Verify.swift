// SPDX-License-Identifier: MIT
//
// Port of Verify.kt. Kotlin call sites read `verify { cond }`; the Swift port
// drops the braces — `verify(cond)` — relying on @autoclosure for laziness.

let VERIFY_ENABLED: Bool = true

@inline(__always)
func verify(_ block: @autoclosure () -> Bool) {
    if VERIFY_ENABLED {
        precondition(block())
    }
}
