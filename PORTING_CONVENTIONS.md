# bigint-kotlin → bigint-swift transliteration conventions

Source of truth: `~/IntelliJ/bigint-kotlin` @ `f1f9896`. This is a **faithful
transliteration**, not a rewrite. Keep the call graph and function names 1:1.

## Memory model (work order §6.1)
- `final class Magia { var a: ContiguousArray<Limb> }` — reference-type limb
  buffer. Engine free functions take a `Magia` and mutate it in place. Aliasing
  (`z === x`) works because they are the same object.
- `struct BigInt` (Phase 2) — immutable value façade over a **never-mutated**
  `Magia` reference (the load-bearing invariant; see `BigInt.swift`).
- `final class MutableBigInt` (Phase 2) — owns growable `Magia` buffers.
- Limbs are native `UInt32` (`typealias Limb = UInt32`). Kotlin's
  `IntArray`-over-`UIntArray` perf rationale does not exist in Swift.

## Type mapping
| Kotlin | Swift |
|---|---|
| `IntArray` magnitude (`Magia`) | `final class Magia` |
| limb cell (`Int`, unsigned semantics) | `Limb` = `UInt32` |
| `Long` | `Int64` |
| `ULong` | `UInt64` |
| `Int` packed value (e.g. `Meta`) | `Int32` |
| `Int` loop counter / length / index | `Int` |
| `Boolean` | `Bool` |

## Operator / idiom mapping
| Kotlin | Swift | Note |
|---|---|---|
| `x[i].toDws()` | `x[i].toDws()` | `Limb → Int64`, zero-extended |
| `dw32(n)` | `dw32(n)` | `Limb → UInt64`, zero-extended |
| `t.toInt()` (store to limb) | `t.toLimb()` | low 32 bits → `Limb` |
| `t.toInt()` (sign-mask math) | `t.toInt32()` | low 32 bits → `Int32` |
| `a + b`, `a - b`, `a * b` (limb math) | `a &+ b`, `a &- b`, `a &* b` | **wrapping** — see policy below |
| `x ushr n` | `x.ushr(n)` | **LOGICAL** right shift (defined on `Int64`/`Int32`) |
| `x shr n` | `x >> n` | arithmetic right shift on a signed type |
| `x shl n` | `x << n` or `x &<< n` | use `&<<` where Kotlin relies on wraparound (e.g. `1 shl 31`) |
| `-x` where x may be Int.min | `0 &- x` | Kotlin Int negate wraps; Swift `-` traps |

## Overflow policy — WRAPPING OPERATORS UNIFORMLY
Kotlin/JVM `Long` and `Int` primitives are two's-complement and wrap silently;
Swift's `+ - *` **trap** on overflow. To be bit-identical to the source AND to
never trap, map `Long → Int64`, `Int → Int32`, and use the **wrapping operators
`&+  &-  &*`** for all limb/dword arithmetic — regardless of whether a given
expression is provably in range.

Why this matters concretely: a limb*limb product is ≤ (2³²−1)² ≈ 2⁶⁴−2³³. That
fits in 64 *unsigned* bits, but the source accumulates in **signed `Long`**, so
any product with bit 63 set exceeds `Int64.max` — plain Swift `*` would trap
where Kotlin wraps. (Computing in `UInt64` would also avoid the trap, but that
diverges from the source's signed accumulators; we mirror `Long` with `Int64` +
wrapping instead, keeping the transliteration mechanical.) High words are then
read with `.ushr(32)` (logical), so the correct bit pattern is preserved.
| `a.inv()` | `~a` | |
| `3.inv()` | `~3` | |
| `dw == 0uL` / `carry == 0L` | `... == 0` | |
| `verify { cond }` | `verify(cond)` | `@autoclosure`; drop the braces |
| `return throwX()` | `throwX()` | throwers are `-> Never`; drop `return` |
| `y.copyInto(x, destOff, start, end)` | `y.copyInto(x, destOff, start, end)` | method on `Magia` |
| `IntArray.size` | `Magia.size` | capacity, NOT logical length |
| `min`/`max` | `min`/`max` | `Swift.min/max` |

## Critical subtleties (these are where bugs hide)
- **`ushr` on a signed value is load-bearing.** Subtraction computes
  `borrow = t ushr 63` on an `Int64` `t` that goes negative on underflow → the
  logical shift yields `1`. `t >> 63` (arithmetic) would yield `-1`. Always use
  `.ushr(_:)`.
- **Carry `ushr 32` on non-negative `t`** is also `.ushr(32)` for uniformity.
- **`toLong()` of a `ULong`** = `Int64(bitPattern: dw)` (bit reinterpret), NOT
  `Int64(dw)` (which would trap on values ≥ 2^63).
- **nonZeroMask trick** (`setSub`): `(zi or -zi) shr 31` with `zi` a signed
  `Int32` → `(zi | (0 &- zi)) >> 31`, then widen to `Int` for index math.
- **Member/free-function name collisions**: a free engine function (e.g.
  `normLen`) is shadowed by a same-named member inside a type's scope — inline
  or rename at that one call site (Swift resolves by name, not by arity).

## Globals
- Shared singletons (`MAGIA_ZERO`, `MAGIA_ONE`, future tables) are
  `nonisolated(unsafe) let` — shared, never mutated, matching Kotlin's `val`.

## Errors
- `BigIntExceptions.kt` throwers → `-> Never` `fatalError` (Swift has no
  unchecked exceptions; every site is a precondition/invariant violation). The
  Kotlin `_Int`/`_Magia`/`_BigInt` suffixed variants collapse onto the same
  `Never` (kept by name for 1:1 call sites).
