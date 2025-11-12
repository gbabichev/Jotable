import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Utility for mapping colors across platforms while preserving "automatic" theme-aware behavior
struct ColorMapping {
#if os(macOS)
    typealias PlatformColor = NSColor
#else
    typealias PlatformColor = UIColor
#endif
    
    /// Custom attribute key to store the color ID (e.g., "red", "automatic")
    /// This allows us to distinguish between explicit colors and automatic colors
    static let colorIDKey = NSAttributedString.Key("com.betternotes.colorID")
    private static let customPrefix = "custom:"

    /// Custom attribute key to store the font size
    static let fontSizeKey = NSAttributedString.Key("com.betternotes.fontSize")

    /// Custom attribute key to store the highlight ID (e.g., "yellow")
    static let highlightIDKey = NSAttributedString.Key("com.betternotes.highlightID")

    /// Custom attribute keys to store font traits that don't survive NSArchiver round-trip
    /// These are necessary because UIFont/NSFont encoding is platform-specific
    static let isBoldKey = NSAttributedString.Key("com.betternotes.isBold")
    static let isItalicKey = NSAttributedString.Key("com.betternotes.isItalic")

    /// Applies a color to the attributed string with the color ID stored for cross-platform sync
    static func applyColor(_ color: RichTextColor, to attributedString: NSMutableAttributedString, range: NSRange) {
        if color == .automatic {
            attributedString.removeAttribute(NSAttributedString.Key.foregroundColor, range: range)
            attributedString.addAttribute(colorIDKey, value: color.id, range: range)
            return
        }

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

    /// Processes an attributed string for archiving, ensuring color IDs and font traits are preserved
    /// This runs BEFORE NSKeyedArchiver encodes the string
    static func preprocessForArchiving(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)

            //print("[ColorMapping.preprocess] Starting archiving preprocess on \(attributedString.length) characters")

        // Iterate through all attributes and ensure color IDs are present alongside colors
        var currentPos = 0
        var rangeIndex = 0
        while currentPos < mutableString.length {
            var range = NSRange()
            let attrs = mutableString.attributes(at: currentPos, longestEffectiveRange: &range, in: NSRange(location: currentPos, length: mutableString.length - currentPos))

            #if os(macOS)
            let font = attrs[NSAttributedString.Key.font] as? NSFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            #else
            let font = attrs[NSAttributedString.Key.font] as? UIFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false
            #endif
            let colorID = attrs[colorIDKey] as? String

            // Store bold/italic as custom attributes to survive cross-platform archiving
            // NSFont/UIFont encoding is platform-specific, so font traits get lost
            mutableString.addAttribute(isBoldKey, value: NSNumber(value: isBold), range: range)
            mutableString.addAttribute(isItalicKey, value: NSNumber(value: isItalic), range: range)

            // If there's a foreground color but no color ID, infer it
            if let foregroundColor = attrs[NSAttributedString.Key.foregroundColor] as? PlatformColor,
               attrs[colorIDKey] == nil {
                let newID = identifier(for: foregroundColor)
                mutableString.addAttribute(colorIDKey, value: newID, range: range)
                //print("[ColorMapping.preprocess] Range \(rangeIndex): Added color ID '\(newID)' for foreground color")
            }

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

            //print("[ColorMapping.preprocess] Range \(rangeIndex): isBold=\(isBold), isItalic=\(isItalic), colorID=\(colorID ?? "nil")")

            currentPos = range.location + range.length
            rangeIndex += 1
        }

        //print("[ColorMapping.preprocess] Completed preprocess with \(rangeIndex) ranges")
        return mutableString
    }

    /// Processes an attributed string for unarchiving, restoring colors and font traits from their IDs
    /// This runs AFTER NSKeyedArchiver decodes the string
    static func postprocessAfterUnarchiving(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)

        // Iterate through all attributes and restore colors from color IDs and rebuild fonts from traits
        var currentPos = 0
        var rangeIndex = 0
        while currentPos < mutableString.length {
            var range = NSRange()
            let attrs = mutableString.attributes(at: currentPos, longestEffectiveRange: &range, in: NSRange(location: currentPos, length: mutableString.length - currentPos))

            let colorID = attrs[colorIDKey] as? String
            let storedBold = (attrs[isBoldKey] as? NSNumber)?.boolValue ?? false
            let storedItalic = (attrs[isItalicKey] as? NSNumber)?.boolValue ?? false

            // Restore color from ID
            if let colorID = attrs[colorIDKey] as? String,
               let platformColor = color(from: colorID) {
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

            // Restore font with bold/italic traits using stored attributes
            if storedBold || storedItalic {
                // Extract font size from the archived font or use fontSizeKey attribute
                let fontSize: FontSize
                if let sizeValue = attrs[fontSizeKey] as? CGFloat {
                    fontSize = FontSize(rawValue: sizeValue) ?? .normal
                } else if let font = attrs[NSAttributedString.Key.font] as? PlatformColor {
                    // Fall back to extracting from font object if available
                    #if os(macOS)
                    let pointSize = (attrs[NSAttributedString.Key.font] as? NSFont)?.pointSize ?? 16.0
                    #else
                    let pointSize = (attrs[NSAttributedString.Key.font] as? UIFont)?.pointSize ?? 16.0
                    #endif
                    fontSize = FontSize(rawValue: pointSize) ?? .normal
                } else {
                    fontSize = .normal
                }

                let styler = TextStyler(isBold: storedBold, isItalic: storedItalic, fontSize: fontSize)
                let restoredFont = styler.buildFont()
                mutableString.addAttribute(NSAttributedString.Key.font, value: restoredFont, range: range)
            }

            // Restore highlight
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
            rangeIndex += 1
        }

        return mutableString
    }

#if os(macOS)
    private static func matchingHighlight(for color: NSColor) -> HighlighterColor? {
        guard let converted = color.usingColorSpace(.sRGB) else { return nil }
        for highlight in HighlighterColor.allCases where highlight != .none {
            guard let highlightColor = highlight.nsColor?.usingColorSpace(.sRGB) else { continue }
            if converted.isEqual(highlightColor) {
                return highlight
            }
        }
        return nil
    }

    private static func matchingColorID(for color: NSColor) -> String? {
        guard let converted = color.usingColorSpace(.sRGB) else { return nil }
        for candidate in RichTextColor.allCases {
            guard let candidateColor = candidate.nsColor.usingColorSpace(.sRGB) else { continue }
            if converted.isEqual(candidateColor) {
                return candidate.id
            }
        }
        return nil
    }

    private static func customColorID(for color: NSColor) -> String {
        guard let converted = color.usingColorSpace(.sRGB) else {
            return "\(customPrefix)automatic"
        }
        let r = Int(round(converted.redComponent * 255))
        let g = Int(round(converted.greenComponent * 255))
        let b = Int(round(converted.blueComponent * 255))
        let a = Int(round(converted.alphaComponent * 255))
        return String(format: "\(customPrefix)%02X%02X%02X%02X", r, g, b, a)
    }

    private static func colorFromCustomID(_ id: String) -> NSColor? {
        guard id.hasPrefix(customPrefix) else { return nil }
        let hex = String(id.dropFirst(customPrefix.count))
        guard hex.count == 8,
              let value = UInt32(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 24) & 0xFF) / 255.0
        let g = CGFloat((value >> 16) & 0xFF) / 255.0
        let b = CGFloat((value >> 8) & 0xFF) / 255.0
        let a = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
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

    private static func customColorID(for color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "\(customPrefix)automatic"
        }
        let ir = Int(round(r * 255))
        let ig = Int(round(g * 255))
        let ib = Int(round(b * 255))
        let ia = Int(round(a * 255))
        return String(format: "\(customPrefix)%02X%02X%02X%02X", ir, ig, ib, ia)
    }

    private static func colorFromCustomID(_ id: String) -> UIColor? {
        guard id.hasPrefix(customPrefix) else { return nil }
        let hex = String(id.dropFirst(customPrefix.count))
        guard hex.count == 8,
              let value = UInt32(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 24) & 0xFF) / 255.0
        let g = CGFloat((value >> 16) & 0xFF) / 255.0
        let b = CGFloat((value >> 8) & 0xFF) / 255.0
        let a = CGFloat(value & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
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

    /// Public helpers used outside this file
    static func identifier(for color: PlatformColor, preferPaletteMatch: Bool = true) -> String {
        #if os(macOS)
        // Special case: NSColor.labelColor is the theme-aware automatic color
        if color.isEqual(NSColor.labelColor) {
            return "automatic"
        }
        #else
        // Special case: UIColor.label is the theme-aware automatic color
        if color == UIColor.label {
            return "automatic"
        }
        #endif

        if preferPaletteMatch {
            #if os(macOS)
            if let match = matchingColorID(for: color) {
                return match
            }
            #else
            if let match = matchingColorID(for: color) {
                return match
            }
            #endif
        }
#if os(macOS)
        return customColorID(for: color)
#else
        return customColorID(for: color)
#endif
    }

    static func color(from identifier: String) -> PlatformColor? {
        if identifier.hasPrefix(customPrefix) {
            #if os(macOS)
            return colorFromCustomID(identifier)
            #else
            return colorFromCustomID(identifier)
            #endif
        }
        let palette = RichTextColor.from(id: identifier)
        #if os(macOS)
        return palette.nsColor
        #else
        return palette.uiColor
        #endif
    }

    static func isCustomColorID(_ identifier: String) -> Bool {
        identifier.hasPrefix(customPrefix)
    }

    static func matchingRichTextColor(for color: PlatformColor) -> RichTextColor? {
#if os(macOS)
        guard let match = matchingColorID(for: color) else { return nil }
#else
        guard let match = matchingColorID(for: color) else { return nil }
#endif
        return RichTextColor.from(id: match)
    }
}
