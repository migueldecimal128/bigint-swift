// SPDX-License-Identifier: MIT
//
// Port of BigInt.kt — the immutable arbitrary-precision integer. Kotlin's
// `class BigInt : BigIntNumber, Comparable<BigInt>` becomes a value
// `struct BigInt: BigIntNumber, Comparable` (work order §6.1): copying shares
// the never-mutated `Magia` reference O(1).
//
// LOAD-BEARING INVARIANT: a `BigInt` never mutates its `Magia`. Every factory
// allocates a fresh `Magia` or shares one strictly read-only.
//
// This file currently covers the value façade + factories + conversions +
// comparison. Arithmetic operators (which delegate to MutableBigInt), String/
// Double parsing, bit ops, pow/gcd are DEFERRED (see marker at end).

// File-scope wrapper: the global `validateNormLenAndInjectPoison(_:_:)` is
// shadowed by the same-named BigIntNumber instance method inside BigInt's scope.
private func _validateNormLenAndInjectPoison(_ m: Magia, _ n: Int) -> Bool {
    validateNormLenAndInjectPoison(m, n)
}

struct BigInt: BigIntNumber, Comparable {
    let meta: Meta
    let magia: Magia

    private init(_ meta: Meta, _ magia: Magia) {
        self.meta = meta
        self.magia = magia
    }

    // MARK: canonical constants
    // `nonisolated(unsafe)`: immutable shared values over a never-mutated Magia.

    nonisolated(unsafe) static let ZERO = BigInt(Meta(0), MAGIA_ZERO)
    nonisolated(unsafe) static let ONE = BigInt(Meta(1), MAGIA_ONE)
    nonisolated(unsafe) static let TWO = BigInt(Meta(1), Magia(limbs: [2]))
    nonisolated(unsafe) static let NEG_ONE = BigInt(Meta(signBit: 1, normLen: 1), MAGIA_ONE)
    // NOTE: faithful to source (`Meta(4)`); this packs normLen=4 for a 1-limb
    // [10] — an apparent inconsistency in bigint-kotlin, replicated verbatim.
    nonisolated(unsafe) static let TEN = BigInt(Meta(4), Magia(limbs: [10]))

    // MARK: internal normalized/non-normalized factories

    static func fromNormalizedNonZero(_ magia: Magia) -> BigInt {
        fromNormalizedNonZero(false, magia)
    }
    static func fromNormalizedNonZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        verify(magia.size > 0)
        verify(magia[magia.size - 1] != 0)
        return BigInt(Meta(signFlag: sign, normLen: Int32(magia.size)), magia)
    }
    static func fromNormalizedNonZero(_ magia: Magia, _ normLen: Int) -> BigInt {
        verify(magia.size > 0 && _validateNormLenAndInjectPoison(magia, normLen))
        return BigInt(Meta(Int32(normLen)), magia)
    }
    static func fromNormalizedNonZero(_ sign: Bool, _ magia: Magia, _ normLen: Int) -> BigInt {
        verify(magia.size > 0 && _validateNormLenAndInjectPoison(magia, normLen))
        return BigInt(Meta(signFlag: sign, normLen: Int32(normLen)), magia)
    }

    static func fromNormalizedOrZero(_ magia: Magia) -> BigInt {
        fromNormalizedOrZero(false, magia)
    }
    static func fromNormalizedOrZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        if magia.size == 0 {
            verify(magia === MAGIA_ZERO)
            return ZERO
        }
        verify(magia.size > 0)
        verify(magia[magia.size - 1] != 0)
        return BigInt(Meta(signFlag: sign, normLen: Int32(magia.size)), magia)
    }

    static func fromNonNormalizedManyNonZero(_ magia: Magia) -> BigInt {
        fromNonNormalizedManyNonZero(false, magia)
    }
    static func fromNonNormalizedManyNonZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        let nl = normLen(magia)
        verify(nl > 0)
        verify(_validateNormLenAndInjectPoison(magia, nl))
        return BigInt(Meta(signFlag: sign, normLen: Int32(nl)), magia)
    }

    static func fromNonNormalized1NonZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        let nl = magia.size - (magia[magia.size - 1] != 0 ? 0 : 1)
        verify(nl > 0)
        verify(_validateNormLenAndInjectPoison(magia, nl))
        return BigInt(Meta(signFlag: sign, normLen: Int32(nl)), magia)
    }

    static func fromNonNormalizedOrZero(_ magia: Magia) -> BigInt {
        fromNonNormalizedOrZero(false, magia)
    }
    static func fromNonNormalizedOrZero(_ sign: Bool, _ magia: Magia) -> BigInt {
        let nl = normLen(magia)
        if nl > 0 {
            verify(_validateNormLenAndInjectPoison(magia, nl))
            return BigInt(Meta(signFlag: sign, normLen: Int32(nl)), magia)
        }
        return ZERO
    }

    // MARK: primitive factories

    static func from(_ n: Int32) -> BigInt {
        if n == 0 { return ZERO }
        biStat(.BI_CONSTRUCT_32)
        if n > 0 {
            return BigInt(Meta(signFlag: false, normLen: 1), Magia(limbs: [Limb(bitPattern: n)]))
        }
        return BigInt(Meta(signFlag: true, normLen: 1), Magia(limbs: [Limb(bitPattern: 0 &- n)]))
    }

    static func from(_ w: UInt32) -> BigInt {
        if w != 0 {
            biStat(.BI_CONSTRUCT_32)
            return BigInt(Meta(signFlag: false, normLen: 1), Magia(limbs: [w]))
        }
        return ZERO
    }

    static func from(_ sign: Bool, _ w: UInt32) -> BigInt {
        if w != 0 {
            biStat(.BI_CONSTRUCT_32)
            return BigInt(Meta(signFlag: sign, normLen: 1), Magia(limbs: [w]))
        }
        return ZERO
    }

    static func from(_ l: Int64) -> BigInt { from(l < 0, l.magnitude) }
    static func from(_ dw: UInt64) -> BigInt { from(false, dw) }

    static func from(_ sign: Bool, _ dwMagnitude: UInt64) -> BigInt {
        if dwMagnitude != 0 {
            biStat(.BI_CONSTRUCT_64)
            if (dwMagnitude >> 32) == 0 {
                return BigInt(Meta(signFlag: sign, normLen: 1), Magia(limbs: [dwMagnitude.toLimb()]))
            }
            return BigInt(Meta(signFlag: sign, normLen: 2),
                          Magia(limbs: [dwMagnitude.toLimb(), (dwMagnitude >> 32).toLimb()]))
        }
        return ZERO
    }

    /// Copy constructor from any BigIntNumber (immutable snapshot).
    static func from(_ other: BigIntNumber) -> BigInt {
        biStat(.BI_CONSTRUCT_COPY)
        if !other.meta.isZero {
            return BigInt(other.meta, other.magia.copyOf(Int(other.meta.normLen)))
        }
        return ZERO
    }

    static func from(_ sign: Bool, _ biMagnitude: BigIntNumber) -> BigInt {
        biStat(.BI_CONSTRUCT_COPY)
        return BigInt(Meta(signFlag: sign, normLen: biMagnitude.meta.normLen),
                      biMagnitude.magia.copyOf(Int(biMagnitude.meta.normLen)))
    }

    // MARK: BigIntNumber

    func toBigInt() -> BigInt { self }   // already an immutable snapshot

    // MARK: Comparable / Equatable (numeric value semantics)

    static func < (lhs: BigInt, rhs: BigInt) -> Bool { lhs.compareTo(rhs) < 0 }
    static func == (lhs: BigInt, rhs: BigInt) -> Bool { lhs.compareTo(rhs) == 0 }
}

// ============================================================================
// DEFERRED from BigInt.kt (next pushes):
//   - arithmetic operators +,-,*,/,%, mod, pow, negate, abs, gcd  (need
//     MutableBigInt + addImpl/mulImpl/divImpl/remModImpl)
//   - from(Double) / fromULongShiftLeft
//   - from(String/CharSequence/CharArray/ByteArray)  (Phase 3 ParsePrint +
//     Latin1Iterator); random; binary-array constructors
//   - bit ops (and/or/xor/shl/shr/testBit-returning-BigInt/setBit), square
//   - Equatable/Hashable per Kotlin's exact equals/hashCode (verify vs source)
// ============================================================================
