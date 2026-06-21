// SPDX-License-Identifier: MIT
//
// ============================================================================
// bigint-swift — a faithful transliteration of bigint-kotlin
//   Source of truth: ~/IntelliJ/bigint-kotlin @ f1f9896 ("publish for Decimal")
// ============================================================================
//
// LOAD-BEARING INVARIANT
// ----------------------
// `BigInt` operations must NEVER mutate their `Magia`. Every result allocates
// a fresh `Magia` (or shares one strictly read-only). This single invariant is
// what makes the value-`struct BigInt` over reference-`class Magia` model
// sound. It is enforced by DISCIPLINE, not the type system — exactly as in the
// Kotlin source. All in-place mutation is confined to `MutableBigInt` and
// construction. If a mutable `BigInt` is ever needed, add COW *then*, not now.
//
// MEMORY MODEL (work order §6.1)
// ------------------------------
//   * `final class Magia`        — reference-type little-endian 32-bit limb
//                                  buffer (`ContiguousArray<UInt32>`); the
//                                  ~2000-line engine mutates it in place.
//   * `struct BigInt`            — immutable value façade over a never-mutated
//                                  `Magia` reference; copying shares the
//                                  reference O(1), like Kotlin.
//   * `final class MutableBigInt`— owns growable `Magia` buffers.
//
// Representation: magnitude = little-endian 32-bit limbs; `Meta` packs sign +
// normalized limb length into one Int. 32-bit limbs are unchanged from Kotlin;
// the 64-bit-limb upgrade is explicitly deferred to a later effort.
//
// The real `struct BigInt` is ported in Phase 2 (see BigIntSwiftPortWorkOrder.md).
// ============================================================================
