import Foundation

public extension String {
    /// Parses a typed money/number string in the user's locale, falling back to ".".
    ///
    /// The decimal pad types "9,50" on comma-decimal locales (de, fr, es, pt-BR ...), where
    /// `Double("9,50")` is nil. Prefilled values use `String(format:)`, which is always ".", so
    /// both forms must parse to the same amount: "9,50" -> 9.5, "9.50" -> 9.5, "1.234,50" -> 1234.5.
    /// Rule: when both "." and "," appear, the later one is the decimal mark and the other is
    /// grouping; when only one kind appears it is the decimal mark.
    var parsedDecimal: Double? {
        let text = trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        guard !text.isEmpty else { return nil }

        let lastDot = text.lastIndex(of: ".")
        let lastComma = text.lastIndex(of: ",")
        let normalized: String
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            normalized = dot > comma
                ? text.replacingOccurrences(of: ",", with: "")
                : text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        case (nil, _?):
            normalized = text.replacingOccurrences(of: ",", with: ".")
        default:
            normalized = text
        }
        return Double(normalized)
    }
}
