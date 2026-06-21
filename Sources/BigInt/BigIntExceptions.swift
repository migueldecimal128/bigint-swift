// SPDX-License-Identifier: MIT
//
// Port of BigIntExceptions.kt.
//
// The Kotlin throwers raise unchecked RuntimeExceptions (Arithmetic/
// IllegalState/IllegalArgument/Unsupported). Swift has no unchecked
// exceptions, and the engine functions are pervasively non-`throws`. Every one
// of these sites is a precondition / internal-invariant violation ("caller
// must size the destination", "bounds check"), so the faithful Swift mapping is
// `fatalError` returning `Never`.
//
// The Kotlin `_Int` / `_Magia` / `_BigInt` suffixed variants exist only to
// satisfy Kotlin's type checker in `return throwX()` expression position. In
// Swift a single `-> Never` covers every return type (Never is the bottom
// type), so the variants collapse to the same `fatalError` — the names are kept
// 1:1 with the source so call sites transliterate verbatim (drop the `return`).
//
// A future refinement (work order §5) could promote the genuinely recoverable
// ones (div-by-zero, parse errors) to a thrown `enum BigIntError: Error`; not
// needed for the oracle.

private let ERR_MSG_ADD_OVERFLOW = "add overflow ... destination too small"
private let ERR_MSG_SUB_UNDERFLOW = "sub underflow ... minuend too small for subtrahend"
private let ERR_MSG_MUL_OVERFLOW = "mul overflow ... destination too small"
private let ERR_MSG_SHL_OVERFLOW = "shl overflow ... destination too small"
private let ERR_MSG_DIV_BY_ZERO = "div by zero"
private let ERR_MSG_INVALID_ALLOCATION_LENGTH = "invalid allocation length"
private let ERR_MSG_NEGATIVE_INDEX = "negative index"
private let ERR_MSG_MOD_NEG_DIVISOR = "modulus with a negative divisor is undefined"
private let ERR_MSG_NEG_BITCOUNT = "negative bitCount"
private let ERR_MSG_BITLEN_LE_0 = "invalid bitLen <= 0"
private let ERR_MSG_INVALID_BITLEN_RANGE = "invalid bitLen range: 0 <= bitLenMin <= bitLenMax"
private let ERR_MSG_NEG_BITINDEX = "negative bitIndex"
private let ERR_MSG_BOUNDS_CHECK_VIOLATION = "bounds check violation"
private let ERR_MSG_BAD_KNUTH_ARGUMENT = "bad knuth argument"
private let ERR_MSG_HASH_CODE_UNSUPPORTED = "mutable MutableBigInt is an invalid key in collections"

func throwDivByZero() -> Never { fatalError(ERR_MSG_DIV_BY_ZERO) }
func throwDivByZero_Int() -> Never { fatalError(ERR_MSG_DIV_BY_ZERO) }
func throwDivByZero_BigInt() -> Never { fatalError(ERR_MSG_DIV_BY_ZERO) }
func throwAddOverflow() -> Never { fatalError(ERR_MSG_ADD_OVERFLOW) }
func throwAddOverflow_Int() -> Never { fatalError(ERR_MSG_ADD_OVERFLOW) }
func throwSubUnderflow() -> Never { fatalError(ERR_MSG_SUB_UNDERFLOW) }
func throwSubUnderflow_Int() -> Never { fatalError(ERR_MSG_SUB_UNDERFLOW) }
func throwMulOverflow() -> Never { fatalError(ERR_MSG_MUL_OVERFLOW) }
func throwShlOverflow() -> Never { fatalError(ERR_MSG_SHL_OVERFLOW) }
func throwInvalidAllocationLength() -> Never { fatalError(ERR_MSG_INVALID_ALLOCATION_LENGTH) }
func throwInvalidAllocationLength_Int() -> Never { fatalError(ERR_MSG_INVALID_ALLOCATION_LENGTH) }
func throwInvalidAllocationLength_Magia() -> Never { fatalError(ERR_MSG_INVALID_ALLOCATION_LENGTH) }
func throwNegativeIndex() -> Never { fatalError(ERR_MSG_NEGATIVE_INDEX) }
func throwModNegDivisor() -> Never { fatalError(ERR_MSG_MOD_NEG_DIVISOR) }
func throwNegBitCount() -> Never { fatalError(ERR_MSG_NEG_BITCOUNT) }
func throwBitLenLE0() -> Never { fatalError(ERR_MSG_BITLEN_LE_0) }
func throwInvalidBitLenRange() -> Never { fatalError(ERR_MSG_INVALID_BITLEN_RANGE) }
func throwNegBitIndex() -> Never { fatalError(ERR_MSG_NEG_BITINDEX) }
func throwBoundsCheckViolation() -> Never { fatalError(ERR_MSG_BOUNDS_CHECK_VIOLATION) }
func throwBoundsCheckViolation_Int() -> Never { fatalError(ERR_MSG_BOUNDS_CHECK_VIOLATION) }
func throwBadKnuthArgument() -> Never { fatalError(ERR_MSG_BAD_KNUTH_ARGUMENT) }
func throwHashCodeUnsupported() -> Never { fatalError(ERR_MSG_HASH_CODE_UNSUPPORTED) }
