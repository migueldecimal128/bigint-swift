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
| `Long` (unsigned-magnitude dword) | `UInt64` (see overflow policy) |
| `ULong` | `UInt64` |
| `Int` packed value (e.g. `Meta`) | `Int32` |
| `Int` loop counter / length / index | `Int` |
| `Boolean` | `Bool` |

## Operator / idiom mapping
| Kotlin | Swift | Note |
|---|---|---|
| `x[i].toDws()` | `x[i].toDw()` | `Limb → UInt64`, zero-extended (UNSIGNED — see policy) |
| `dw32(n)` | `dw32(n)` | `Limb → UInt64`, zero-extended |
| `t.toInt()` (store to limb) | `t.toLimb()` | low 32 bits → `Limb` |
| `t.toInt()` (sign-mask math) | `t.toInt32()` | low 32 bits → `Int32` |
| `a + b`, `a - b`, `a * b` (limb math) | `a &+ b`, `a &- b`, `a &* b` | **wrapping** — see policy below |
| `x ushr n` (dword) | `x >> n` | `>>` on `UInt64` IS logical — no helper |
| `x ushr n` (Meta `Int32`) | `x.ushr(n)` | logical-shift helper, only for the signed packed `Meta` |
| `x shr n` (Meta `Int32`) | `x >> n` | arithmetic right shift on signed `Int32` |
| `x shl n` | `x << n` or `x &<< n` | use `&<<` where Kotlin relies on wraparound (e.g. `1 shl 31`) |
| `-x` where x may be Int.min | `0 &- x` | Kotlin Int negate wraps; Swift `-` traps |
| `a.inv()` / `3.inv()` | `~a` / `~3` | |
| `dw == 0uL` / `carry == 0L` | `... == 0` | |
| `verify { cond }` | `verify(cond)` | `@autoclosure`; drop the braces |
| `return throwX()` | `throwX()` | throwers are `-> Never`; drop `return` |
| `y.copyInto(x, destOff, start, end)` | `y.copyInto(x, destOff, start, end)` | method on `Magia` |
| `IntArray.size` | `Magia.size` | capacity, NOT logical length |
| `min`/`max` | `min`/`max` | `Swift.min/max` |

## Overflow policy — UNSIGNED dwords + WRAPPING OPERATORS
The limbs are unsigned magnitudes, so dword temporaries map to **`UInt64`**, not
Kotlin's signed `Long`. (Kotlin uses signed `Long` + `ushr` only to work around
the JVM's awkward unsigned support — `toDws` = "to double-word **signed**" is a
workaround, not the intent.) `UInt64` is the faithful-to-intent choice and is
strictly cleaner:

- **No overflow to reason about.** A limb*limb product is ≤ (2³²−1)² < 2⁶⁴, and
  the schoolbook accumulator stays ≤ 2⁶⁴−1 — both fit in `UInt64`.
- **`ushr` becomes plain `>>`.** Right shift on an unsigned type is logical by
  definition, so the custom dword `.ushr()` helper disappears.
- **The borrow trick still works.** `t = a &- b &- borrow` wraps (two's
  complement) so bit 63 is set on underflow; `t >> 63` reads the borrow bit.

Still, per uniform policy, use the **wrapping operators `&+ &- &*`** for all
limb arithmetic (mirrors Kotlin's two's-complement primitives and never traps,
even at the 2⁶⁴ boundary). `Int32` is kept only for `Meta` and the one `setSub`
nonzero-mask idiom (a genuinely signed view of a single limb).

## Critical subtleties (these are where bugs hide)
- **The borrow bit comes from a wrapped `UInt64`.** Subtraction computes
  `t = a &- b &- borrow` on `UInt64`; on underflow it wraps so bit 63 is set,
  and `borrow = t >> 63` reads it. The `&-` (wrapping) is essential — plain `-`
  would trap on the underflow.
- **High word via `>> 32`** is logical because the dword is `UInt64`.
- **nonZeroMask trick** (`setSub`): `(zi or -zi) shr 31` with `zi` a signed
  `Int32` (`t.toInt32()`) → `(zi | (0 &- zi)) >> 31`, then widen to `Int` for
  index math.
- **Member/free-function name collisions**: a free engine function (e.g.
  `normLen`) is shadowed by a same-named member inside a type's scope — inline
  or rename at that one call site (Swift resolves by name, not by arity).

## Globals
- Shared singletons (`MAGIA_ZERO`, `MAGIA_ONE`, future tables) are
  `nonisolated(unsafe) let` — shared, never mutated, matching Kotlin's `val`.

## Access control (public API boundary)
The value layer is `public` so external packages consume it with a plain
`import BigInt`: `BigInt`, `BigIntNumber`, `MutableBigInt`, `BigIntRandom`,
`BigIntPrime` (+ `LucasParams`), `ModContext`, and all their user-facing
methods/operators/factories. The engine stays `internal`: `magia_*` free
functions, `BigIntAlgorithms`, `BigIntSerde`, `BigIntParsePrint`,
`Latin1Iterator`, `Verify`, `Intrinsic`, `BigIntStats`, the throwers, and the
nested `Barrett`/`Montgomery`. Nothing is `@inlinable`, so a `public` method may
freely call `internal` helpers (no `@usableFromInline` needed).
- `Meta`/`Magia` are public as **types only** (members stay internal → opaque):
  the public `BigIntNumber` protocol requires `meta`/`magia`, and Swift forbids
  internal requirements on a public protocol. One forced divergence from Kotlin,
  where they are `internal`.
- A type going `public` LOSES implicit `Sendable` — declare it where a `static
  let` of that type exists (e.g. `LucasParams: Sendable` for `LUCAS_COMPOSITE`).
- The shared singletons stay `nonisolated(unsafe) let` (above) — fine for a
  `public static let` because the unsafe opt-out bypasses the Sendable check.

## Errors
- `BigIntExceptions.kt` throwers → `-> Never` `fatalError` (Swift has no
  unchecked exceptions; every site is a precondition/invariant violation). The
  Kotlin `_Int`/`_Magia`/`_BigInt` suffixed variants collapse onto the same
  `Never` (kept by name for 1:1 call sites).

## Test porting (Phase 5: `commonTest/.../Test*.kt` → `Tests/BigIntTests/*.swift`)
Use **swift-testing** (not XCTest). Each file:
```swift
import Testing
@testable import BigInt

@Suite struct TestFooName {           // keep the Kotlin class name
    @Test func barCase() { ... }       // keep the Kotlin method name (camelCase)
}
```
| Kotlin (`kotlin.test`) | Swift (`Testing`) |
|---|---|
| `@Test fun f()` | `@Test func f()` |
| `class TestX { ... }` | `@Suite struct TestX { ... }` |
| `assertEquals(exp, act)` | `#expect(act == exp)` (note arg order flips) |
| `assertEquals(exp, act, "msg")` | `#expect(act == exp, "msg")` |
| `assertTrue(c)` / `assertFalse(c)` | `#expect(c)` / `#expect(!c)` |
| `assertNotEquals(a, b)` | `#expect(a != b)` |
| `fail("m")` | `Issue.record("m")` |
| `@BeforeTest` setup | a stored property / `init()` on the suite struct |
| `repeat(n) { ... }` | `for _ in 0..<n { ... }` |
| `for (i in a..<b)` | `for i in a..<b` |
| `for (i in a..b)` (closed) | `for i in a...b` |
| `for (i in n downTo 0)` | `var i = n; while i >= 0 { ...; i -= 1 }` |

**RNG**: Kotlin `kotlin.random.Random` → `BigIntRandom` (Sources, conforms to
`RandomNumberGenerator`, seedable). `Random(12345)` → `BigIntRandom(Int64(12345))`;
`Random.Default` → `BigIntRandom.Default`; `Random.nextInt(8)` →
`BigIntRandom.Default.nextInt(Int32(8))`. Surface preserved: `nextInt()`,
`nextInt(until)`, `nextInt(from, until)`, `nextLong()`, `nextBoolean()`,
`nextDouble(from, until)` (all take/return `Int32`/`Int64`/`Double`). Pass an
explicit `BigIntRandom(seed)` so failures reproduce.

**Factories/helpers** the tests lean on (all in Sources now): `BigInt.from(Int32/
Int64/UInt64/Double/String)`, `BigInt.randomWithBitLen(_:_:withRandomSign:ensureOdd:)`,
`randomWithMaxBitLen`, `randomBelow`, `BigInt.factorial/gcd/lcm`, `.toMutableBigInt()`,
`MutableBigInt(_ :)`. Native `Int128`/`UInt128` are available as oracles (macOS 26).

**Numeric literals**: annotate hex/large literals to avoid defaulting to `Int`
overflow, e.g. `(0xFFFF_0000 as UInt64)`. Kotlin `bi(1)`-style local helpers →
a `private func` on the suite or inline `BigInt.from(Int32(1))`.

**Benchmarks** (`Test*Benchmark*.kt`, the timing halves of `TestBarrettVs*`,
`Test*Comba*`): port the **correctness assertions only**; drop `measureNano`/
`println`/timing loops. Keep representative iteration counts (large random sweeps
are fine; they run in well under a second).
