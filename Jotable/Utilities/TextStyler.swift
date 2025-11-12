import Foundation
import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

/// Universal text styling struct that works across iOS and macOS
/// Eliminates platform-specific branching for font and text attribute handling
struct TextStyler: Equatable {
    let isBold: Bool
    let isItalic: Bool
    let fontSize: FontSize
    let colorID: String?
    let color: PlatformColor?
    let highlightID: String?
    let highlight: PlatformColor?
    let isUnderlined: Bool
    let isStrikethrough: Bool

    // MARK: - Initialization

    init(
        isBold: Bool = false,
        isItalic: Bool = false,
        fontSize: FontSize = .normal,
        colorID: String? = nil,
        color: PlatformColor? = nil,
        highlightID: String? = nil,
        highlight: PlatformColor? = nil,
        isUnderlined: Bool = false,
        isStrikethrough: Bool = false
    ) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.fontSize = fontSize
        self.colorID = colorID
        self.color = color
        self.highlightID = highlightID
        self.highlight = highlight
        self.isUnderlined = isUnderlined
        self.isStrikethrough = isStrikethrough
    }

    // MARK: - Font Building (Platform-Agnostic)

    /// Builds a platform font from current styling state
    func buildFont() -> PlatformFont {
        let weight: PlatformFont.Weight = isBold ? .bold : .regular
        var font = PlatformFont.systemFont(ofSize: fontSize.rawValue, weight: weight)

        // Build symbolic traits for combined bold + italic
        #if os(macOS)
        var traits: NSFontDescriptor.SymbolicTraits = isBold ? .bold : []
        if isItalic {
            traits.insert(.italic)
        }

        if !traits.isEmpty {
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
            font = NSFont(descriptor: descriptor, size: fontSize.rawValue) ?? font
        }
        #else
        var traits: UIFontDescriptor.SymbolicTraits = isBold ? .traitBold : []
        if isItalic {
            traits.insert(.traitItalic)
        }

        if !traits.isEmpty {
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: fontSize.rawValue)
            }
        }
        #endif

        return font
    }

    // MARK: - Attribute Building

    /// Builds complete typing attributes dictionary from current state
    func buildAttributes(
        usingAutomatic: Bool = false,
        customColor: PlatformColor? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]

        // Font
        attrs[NSAttributedString.Key.font] = buildFont()
        attrs[ColorMapping.fontSizeKey] = fontSize.rawValue

        // Color
        if usingAutomatic {
            #if os(macOS)
            attrs[NSAttributedString.Key.foregroundColor] = NSColor.labelColor
            #else
            attrs[NSAttributedString.Key.foregroundColor] = UIColor.label
            #endif
            attrs[ColorMapping.colorIDKey] = RichTextColor.automatic.id
        } else if let customColor = customColor {
            attrs[NSAttributedString.Key.foregroundColor] = customColor
            let identifier = ColorMapping.identifier(for: customColor, preferPaletteMatch: false)
            attrs[ColorMapping.colorIDKey] = identifier
        } else if let color = color {
            attrs[NSAttributedString.Key.foregroundColor] = color
            if let colorID = colorID {
                attrs[ColorMapping.colorIDKey] = colorID
            }
        }

        // Underline and strikethrough
        attrs[NSAttributedString.Key.underlineStyle] = isUnderlined ? NSUnderlineStyle.single.rawValue : 0
        attrs[NSAttributedString.Key.strikethroughStyle] = isStrikethrough ? NSUnderlineStyle.single.rawValue : 0

        // Highlight
        if let highlight = highlight, let highlightID = highlightID {
            attrs[NSAttributedString.Key.backgroundColor] = highlight
            attrs[ColorMapping.highlightIDKey] = highlightID
        }

        return attrs
    }

    // MARK: - State Extraction

    /// Extracts styling state from an attributes dictionary
    static func extract(from attrs: [NSAttributedString.Key: Any]) -> TextStyler {
        let font = attrs[NSAttributedString.Key.font] as? PlatformFont

        #if os(macOS)
        let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
        #else
        let isBold = font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
        let isItalic = font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false
        #endif

        let fontSize = extractFontSize(from: attrs)
        let colorID = attrs[ColorMapping.colorIDKey] as? String
        let color = attrs[NSAttributedString.Key.foregroundColor] as? PlatformColor
        let highlightID = attrs[ColorMapping.highlightIDKey] as? String
        let highlight = attrs[NSAttributedString.Key.backgroundColor] as? PlatformColor

        let underlineValue = attrs[NSAttributedString.Key.underlineStyle] as? Int ?? 0
        let isUnderlined = underlineValue != 0

        let strikethroughValue = attrs[NSAttributedString.Key.strikethroughStyle] as? Int ?? 0
        let isStrikethrough = strikethroughValue != 0

        let styler = TextStyler(
            isBold: isBold,
            isItalic: isItalic,
            fontSize: fontSize,
            colorID: colorID,
            color: color,
            highlightID: highlightID,
            highlight: highlight,
            isUnderlined: isUnderlined,
            isStrikethrough: isStrikethrough
        )

        // Log extracted attributes for debugging
        print("[TextStyler.extract] Extracted from attributes:")
        print("  Font object present: \(font != nil)")
        if let font = font {
            print("  Font name: \(font.fontName)")
            print("  Font size: \(font.pointSize)")
            #if os(macOS)
            print("  Font symbolic traits: \(font.fontDescriptor.symbolicTraits.rawValue)")
            #else
            print("  Font symbolic traits: \(font.fontDescriptor.symbolicTraits.rawValue)")
            #endif
        }
        print("  isBold: \(isBold), isItalic: \(isItalic)")
        print("  isUnderlined: \(isUnderlined), isStrikethrough: \(isStrikethrough)")
        print("  colorID: \(colorID ?? "nil")")
        print("  highlightID: \(highlightID ?? "nil")")

        return styler
    }

    /// Extracts font size from attributes, with fallback to default
    private static func extractFontSize(from attrs: [NSAttributedString.Key: Any]) -> FontSize {
        // Try to get from explicit fontSizeKey first
        if let sizeValue = attrs[ColorMapping.fontSizeKey] as? CGFloat {
            return FontSize(rawValue: sizeValue) ?? .normal
        }

        // Fall back to extracting from font object
        if let font = attrs[NSAttributedString.Key.font] as? PlatformFont {
            return FontSize(rawValue: font.pointSize) ?? .normal
        }

        return .normal
    }

    // MARK: - Toggle Operations

    /// Returns a new TextStyler with bold toggled
    func togglingBold() -> TextStyler {
        TextStyler(
            isBold: !isBold,
            isItalic: isItalic,
            fontSize: fontSize,
            colorID: colorID,
            color: color,
            highlightID: highlightID,
            highlight: highlight,
            isUnderlined: isUnderlined,
            isStrikethrough: isStrikethrough
        )
    }

    /// Returns a new TextStyler with italic toggled
    func togglingItalic() -> TextStyler {
        TextStyler(
            isBold: isBold,
            isItalic: !isItalic,
            fontSize: fontSize,
            colorID: colorID,
            color: color,
            highlightID: highlightID,
            highlight: highlight,
            isUnderlined: isUnderlined,
            isStrikethrough: isStrikethrough
        )
    }

    /// Returns a new TextStyler with underline toggled
    func togglingUnderline() -> TextStyler {
        TextStyler(
            isBold: isBold,
            isItalic: isItalic,
            fontSize: fontSize,
            colorID: colorID,
            color: color,
            highlightID: highlightID,
            highlight: highlight,
            isUnderlined: !isUnderlined,
            isStrikethrough: isStrikethrough
        )
    }

    /// Returns a new TextStyler with strikethrough toggled
    func togglingStrikethrough() -> TextStyler {
        TextStyler(
            isBold: isBold,
            isItalic: isItalic,
            fontSize: fontSize,
            colorID: colorID,
            color: color,
            highlightID: highlightID,
            highlight: highlight,
            isUnderlined: isUnderlined,
            isStrikethrough: !isStrikethrough
        )
    }

    /// Returns a new TextStyler with font size changed
    func withFontSize(_ size: FontSize) -> TextStyler {
        TextStyler(
            isBold: isBold,
            isItalic: isItalic,
            fontSize: size,
            colorID: colorID,
            color: color,
            highlightID: highlightID,
            highlight: highlight,
            isUnderlined: isUnderlined,
            isStrikethrough: isStrikethrough
        )
    }

    /// Returns a new TextStyler with color changed
    func withColor(_ colorID: String?, color: PlatformColor?) -> TextStyler {
        TextStyler(
            isBold: isBold,
            isItalic: isItalic,
            fontSize: fontSize,
            colorID: colorID,
            color: color,
            highlightID: highlightID,
            highlight: highlight,
            isUnderlined: isUnderlined,
            isStrikethrough: isStrikethrough
        )
    }

    /// Returns a new TextStyler with highlight changed
    func withHighlight(_ highlightID: String?, highlight: PlatformColor?) -> TextStyler {
        TextStyler(
            isBold: isBold,
            isItalic: isItalic,
            fontSize: fontSize,
            colorID: colorID,
            color: color,
            highlightID: highlightID,
            highlight: highlight,
            isUnderlined: isUnderlined,
            isStrikethrough: isStrikethrough
        )
    }
}
