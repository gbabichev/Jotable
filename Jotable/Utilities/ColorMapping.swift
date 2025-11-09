import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Utility for mapping colors across platforms while preserving "automatic" theme-aware behavior
struct ColorMapping {
    /// Custom attribute key to store the color ID (e.g., "red", "automatic")
    /// This allows us to distinguish between explicit colors and automatic colors
    static let colorIDKey = NSAttributedString.Key("com.betternotes.colorID")

    /// Custom attribute key to store the font size
    static let fontSizeKey = NSAttributedString.Key("com.betternotes.fontSize")

    /// Custom attribute key to store the highlight ID (e.g., "yellow")
    static let highlightIDKey = NSAttributedString.Key("com.betternotes.highlightID")

    /// Applies a color to the attributed string with the color ID stored for cross-platform sync
    static func applyColor(_ color: RichTextColor, to attributedString: NSMutableAttributedString, range: NSRange) {
        #if os(macOS)
        let platformColor: NSColor = color.nsColor
        #else
        let platformColor: UIColor = color.uiColor
        #endif

        attributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: platformColor, range: range)
        attributedString.addAttribute(colorIDKey, value: color.id, range: range)
    }

    /// Applies highlight background with the highlight ID stored for cross-platform sync
    static func applyHighlight(_ highlight: HighlighterColor, to attributedString: NSMutableAttributedString, range: NSRange) {
        if highlight == .none {
            attributedString.removeAttribute(NSAttributedString.Key.backgroundColor, range: range)
            attributedString.removeAttribute(highlightIDKey, range: range)
            return
        }

        #if os(macOS)
        guard let platformColor: NSColor = highlight.nsColor else { return }
        #else
        guard let platformColor: UIColor = highlight.uiColor else { return }
        #endif

        attributedString.addAttribute(NSAttributedString.Key.backgroundColor, value: platformColor, range: range)
        attributedString.addAttribute(highlightIDKey, value: highlight.id, range: range)
    }

    /// Processes an attributed string for archiving, ensuring color IDs are preserved
    /// This runs BEFORE NSKeyedArchiver encodes the string
    static func preprocessForArchiving(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)

        // Iterate through all attributes and ensure color IDs are present alongside colors
        var currentPos = 0
        while currentPos < mutableString.length {
            var range = NSRange()
            let attrs = mutableString.attributes(at: currentPos, longestEffectiveRange: &range, in: NSRange(location: currentPos, length: mutableString.length - currentPos))

            // If there's a foreground color but no color ID, infer it
            #if os(macOS)
            if let foregroundColor = attrs[NSAttributedString.Key.foregroundColor] as? NSColor,
               attrs[colorIDKey] == nil,
               let inferredID = matchingColorID(for: foregroundColor) {
                mutableString.addAttribute(colorIDKey, value: inferredID, range: range)
            }
            #else
            if let foregroundColor = attrs[NSAttributedString.Key.foregroundColor] as? UIColor,
               attrs[colorIDKey] == nil,
               let inferredID = matchingColorID(for: foregroundColor) {
                mutableString.addAttribute(colorIDKey, value: inferredID, range: range)
            }
            #endif

            #if os(macOS)
            if let backgroundColor = attrs[NSAttributedString.Key.backgroundColor] as? NSColor,
               attrs[highlightIDKey] == nil,
               let highlight = matchingHighlight(for: backgroundColor) {
                mutableString.addAttribute(highlightIDKey, value: highlight.id, range: range)
            }
            #else
            if let backgroundColor = attrs[NSAttributedString.Key.backgroundColor] as? UIColor,
               attrs[highlightIDKey] == nil,
               let highlight = matchingHighlight(for: backgroundColor) {
                mutableString.addAttribute(highlightIDKey, value: highlight.id, range: range)
            }
            #endif

            currentPos = range.location + range.length
        }

        return mutableString
    }

    /// Processes an attributed string for unarchiving, restoring colors from their IDs
    /// This runs AFTER NSKeyedArchiver decodes the string
    static func postprocessAfterUnarchiving(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)

        // Iterate through all attributes and restore colors from color IDs
        var currentPos = 0
        while currentPos < mutableString.length {
            var range = NSRange()
            let attrs = mutableString.attributes(at: currentPos, longestEffectiveRange: &range, in: NSRange(location: currentPos, length: mutableString.length - currentPos))

            if let colorID = attrs[colorIDKey] as? String {
                let color = RichTextColor.from(id: colorID)

                #if os(macOS)
                let platformColor = color.nsColor
                #else
                let platformColor = color.uiColor
                #endif

                mutableString.addAttribute(NSAttributedString.Key.foregroundColor, value: platformColor, range: range)
            } else if attrs[NSAttributedString.Key.foregroundColor] == nil {
                // If there's no color at all, apply the default automatic color
                #if os(macOS)
                mutableString.addAttribute(NSAttributedString.Key.foregroundColor, value: NSColor.labelColor, range: range)
                #else
                mutableString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.label, range: range)
                #endif
                mutableString.addAttribute(colorIDKey, value: "automatic", range: range)
            }

            if let highlightID = attrs[highlightIDKey] as? String {
                let highlight = HighlighterColor.from(id: highlightID)

                #if os(macOS)
                if let platformColor = highlight.nsColor {
                    mutableString.addAttribute(NSAttributedString.Key.backgroundColor, value: platformColor, range: range)
                } else {
                    mutableString.removeAttribute(NSAttributedString.Key.backgroundColor, range: range)
                }
                #else
                if let platformColor = highlight.uiColor {
                    mutableString.addAttribute(NSAttributedString.Key.backgroundColor, value: platformColor, range: range)
                } else {
                    mutableString.removeAttribute(NSAttributedString.Key.backgroundColor, range: range)
                }
                #endif
            }

            currentPos = range.location + range.length
        }

        return mutableString
    }

#if os(macOS)
    private static func matchingHighlight(for color: NSColor) -> HighlighterColor? {
        guard let converted = color.usingColorSpace(.deviceRGB) else { return nil }
        for highlight in HighlighterColor.allCases where highlight != .none {
            guard let highlightColor = highlight.nsColor?.usingColorSpace(.deviceRGB) else { continue }
            if converted.isEqual(highlightColor) {
                return highlight
            }
        }
        return nil
    }

    private static func matchingColorID(for color: NSColor) -> String? {
        guard let converted = color.usingColorSpace(.deviceRGB) else { return nil }
        for candidate in RichTextColor.allCases {
            guard let candidateColor = candidate.nsColor.usingColorSpace(.deviceRGB) else { continue }
            if converted.isEqual(candidateColor) {
                return candidate.id
            }
        }
        return nil
    }
#else
    private static func matchingHighlight(for color: UIColor) -> HighlighterColor? {
        for highlight in HighlighterColor.allCases where highlight != .none {
            guard let highlightColor = highlight.uiColor else { continue }
            if colorsEqual(color, highlightColor) {
                return highlight
            }
        }
        return nil
    }

    private static func matchingColorID(for color: UIColor) -> String? {
        for candidate in RichTextColor.allCases {
            if colorsEqual(color, candidate.uiColor) {
                return candidate.id
            }
        }
        return nil
    }

    private static func colorsEqual(_ lhs: UIColor, _ rhs: UIColor) -> Bool {
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        guard lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la),
              rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra) else {
            return lhs == rhs
        }
        let tolerance: CGFloat = 0.001
        return abs(lr - rr) < tolerance &&
            abs(lg - rg) < tolerance &&
            abs(lb - rb) < tolerance &&
            abs(la - ra) < tolerance
    }
    #endif
}
