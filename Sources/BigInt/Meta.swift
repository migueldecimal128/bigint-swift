// SPDX-License-Identifier: MIT
//
// Port of Meta.kt — compact sign + normalized-limb-length metadata packed into
// one 32-bit `Int`. Kotlin `value class Meta(val _meta: Int)` → Swift
// `struct Meta { let _meta: Int32 }` (zero-allocation value type either way).
//
// Layout (MSB→LSB):  meta = [ signBit | normLen (31 bits) ]
//   signBit 0 → non-negative, 1 → negative;  normLen ≥ 0 in the low 31 bits.
//   Canonical ZERO is normLen==0 with a cleared sign bit.
//
// Kotlin's several `operator fun invoke(...)` overloads become labeled `init`s.
// `shr` (arithmetic) → Swift `>>` on Int32; `ushr` (logical) → `.ushr(_:)`.

struct Meta {
    let _meta: Int32

    init(_ meta: Int32) {
        self._meta = meta
    }

    /// Meta(signBit, normLen) — packs the MSB explicitly.
    init(signBit: Int32, normLen: Int32) {
        verify((signBit >> 1) == 0)
        verify(normLen >= 0)
        // mask `& ((0 - normLen) >> 31)` forces canonical zero (prevents -0)
        self._meta = ((signBit &<< 31) | normLen) & ((0 &- normLen) >> 31)
    }

    /// Meta(signFlag, normLen) — sets the MSB from a Bool.
    init(signFlag: Bool, normLen: Int32) {
        if normLen >= 0 {
            self._meta = (normLen | (signFlag ? Int32.min : 0)) & ((0 &- normLen) >> 31)
        } else {
            fatalError() // IllegalStateException
        }
    }

    init(signFlag: Bool, _ x: Magia, _ xLen: Int) {
        // normLen(x, xLen) inlined: the free engine function is shadowed by the
        // `normLen` member inside this type's scope.
        var n = xLen
        while n > 0 && x[n - 1] == 0 { n -= 1 }
        self.init(signFlag: signFlag, normLen: Int32(n))
    }

    init(signFlag: Bool, _ x: Magia) {
        var n = x.size
        while n > 0 && x[n - 1] == 0 { n -= 1 }
        self.init(signFlag: signFlag, normLen: Int32(n))
    }

    init(signBit: Int32, _ x: Magia) {
        verify(signBit.ushr(1) == 0)
        var n = x.size
        while n > 0 && x[n - 1] == 0 { n -= 1 }
        self.init(signBit: signBit, normLen: Int32(n))
    }

    init(_ x: Magia) {
        self.init(signBit: 0, x)
    }

    /// `true` if the sign bit is set (value is negative).
    var signFlag: Bool { _meta < 0 }

    /// Sign as a single bit: 0 non-negative, 1 negative.
    var signBit: Int32 { _meta.ushr(31) }

    /// Sign mask: 0 for non-negative, -1 for negative.
    var signMask: Int32 { _meta >> 31 }

    var isNegative: Bool { _meta < 0 }
    var isPositive: Bool { _meta >= 0 }
    var isZero: Bool { _meta == 0 }

    /// Negation of the sign, same magnitude; never produces negative zero.
    func negate() -> Meta {
        Meta((_meta ^ Int32.min) & ((0 &- (_meta & Int32.max)) >> 31))
    }

    /// Same magnitude with the specified sign; never produces negative zero.
    func withSign(_ sign: Bool) -> Meta {
        Meta(signBit: sign ? 1 : 0, normLen: _meta & Int32.max)
    }

    /// Non-negative sign, same magnitude.
    func abs() -> Meta {
        Meta(_meta & Int32.max)
    }

    /// Negates `x` iff this Meta is negative (comparison helper).
    func negateIfNegative(_ x: Int32) -> Int32 {
        (x ^ signMask) &- signMask
    }

    /// Sign as -1 or 1 (comparison helper).
    var signNeg1or1: Int32 { signMask | 1 }

    var normLen: Int32 { _meta & Int32.max }

    var signum: Int32 { (_meta >> 31) | (0 &- _meta).ushr(31) }
}
