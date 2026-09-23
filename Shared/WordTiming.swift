import SwiftUI

/// LRCLIB only times whole lines, so word timing is estimated: the line is assumed
/// to be sung at about 14 characters per second, and each word gets a share of that
/// time based on its length.
enum WordTiming {
    static func words(_ text: String) -> [Substring] { text.split(separator: " ") }

    /// Estimated start time of each word in the line.
    static func starts(_ text: String, lineStart: TimeInterval, lineEnd: TimeInterval) -> [TimeInterval] {
        let words = words(text)
        let totalChars = Double(words.reduce(0) { $0 + $1.count + 1 })
        // Singers rarely stretch a line across the whole gap before the next one.
        let sung = min(lineEnd - lineStart, max(1.2, totalChars * 0.07))
        var charsBefore = 0.0
        return words.map { word in
            defer { charsBefore += Double(word.count + 1) }
            return lineStart + sung * charsBefore / totalChars
        }
    }

    /// The line with each word's brightness set by `litAmount(index)`, from 0 (dim) to 1 (lit).
    static func highlighted(_ text: String, dim: Double, litAmount: (Int) -> Double) -> AttributedString {
        var out = AttributedString()
        for (i, word) in words(text).enumerated() {
            var piece = AttributedString(i == 0 ? String(word) : " " + word)
            piece.foregroundColor = .white.opacity(dim + (1 - dim) * litAmount(i))
            out += piece
        }
        return out
    }
}
