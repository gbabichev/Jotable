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
            if attrs[NSAttributedString.Key.foregroundColor] != nil && attrs[colorIDKey] == nil {
                // If no color ID was set, try to infer from the color itself
                // Otherwise default to "automatic"
                mutableString.addAttribute(colorIDKey, value: "automatic", range: range)
            }

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

            currentPos = range.location + range.length
        }

        return mutableString
    }
}
