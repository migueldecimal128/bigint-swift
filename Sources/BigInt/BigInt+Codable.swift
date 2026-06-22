// SPDX-License-Identifier: MIT
//
// Codable conformance for BigInt, using a decimal-string representation.
//
// Decimal string (not a JSON number) is the safe, portable choice: JSON numbers
// are commonly decoded as Double and lose precision beyond 2^53, which would
// corrupt large values. A string round-trips exactly, is human-readable, and is
// trivially interoperable across languages/ports.

extension BigInt {

    /// Non-trapping decimal parse: returns `nil` for malformed input (the accepted
    /// form is an optional leading `-` followed by one or more ASCII digits — a
    /// strict subset of what `from(String)` accepts, which itself traps on bad
    /// input). This is the single place that defines "malformed", so callers can
    /// choose their own behavior (nil, default, throw) instead of the trapping
    /// `from(String)`; `init(from:)` below builds its throwing behavior on top of it.
    public static func fromDecimalStringOrNil(_ s: String) -> BigInt? {
        var digits = Substring(s)
        if digits.first == "-" { digits = digits.dropFirst() }   // optional sign
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
            return nil
        }
        return BigInt.from(s)
    }
}

extension BigInt: Codable {

    /// Encodes as the decimal string (e.g. "-12345"), via a single-value container.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(toString())
    }

    /// Decodes a decimal string, throwing `DecodingError` on malformed input
    /// (delegating the malformed check to `fromDecimalStringOrNil`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        guard let value = BigInt.fromDecimalStringOrNil(s) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not a decimal BigInt: \"\(s)\"")
        }
        self = value
    }
}
