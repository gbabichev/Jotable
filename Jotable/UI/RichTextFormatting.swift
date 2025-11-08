import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum FontSize: CGFloat, Equatable, Identifiable, CaseIterable {
    case small = 12
    case normal = 16
    case large = 18
    case extraLarge = 20
    case huge = 24

    var id: CGFloat { self.rawValue }

    var displayName: String {
        switch self {
        case .small: return "Small (12pt)"
        case .normal: return "Normal (16pt)"
        case .large: return "Large (18pt)"
        case .extraLarge: return "Extra Large (20pt)"
        case .huge: return "Huge (24pt)"
        }
    }
}

enum RichTextColor: Equatable, Identifiable {
    case automatic
    case red
    case green
    case orange
    case yellow
    case purple
    case blue

    var id: String {
        switch self {
        case .automatic: return "automatic"
        case .red: return "red"
        case .green: return "green"
        case .orange: return "orange"
        case .yellow: return "yellow"
        case .purple: return "purple"
        case .blue: return "blue"
        }
    }

    var emoji: String {
        switch self {
        case .automatic: return "⚫"
        case .red: return "🔴"
        case .green: return "🟢"
        case .orange: return "🟠"
        case .yellow: return "🟡"
        case .purple: return "🟣"
        case .blue: return "🔵"
        }
    }

    #if os(macOS)
    var nsColor: NSColor {
        switch self {
        case .automatic:
            return NSColor.labelColor
        case .red:
            return NSColor.systemRed
        case .green:
            return NSColor.systemGreen
        case .orange:
            return NSColor.systemOrange
        case .yellow:
            return NSColor.systemYellow
        case .purple:
            return NSColor.systemPurple
        case .blue:
            return NSColor.systemBlue
        }
    }
    #else
    var uiColor: UIColor {
        switch self {
        case .automatic:
            return UIColor.label
        case .red:
            return UIColor.systemRed
        case .green:
            return UIColor.systemGreen
        case .orange:
            return UIColor.systemOrange
        case .yellow:
            return UIColor.systemYellow
        case .purple:
            return UIColor.systemPurple
        case .blue:
            return UIColor.systemBlue
        }
    }
    #endif

    /// Initializes from a color ID string
    static func from(id: String) -> RichTextColor {
        switch id {
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "blue": return .blue
        default: return .automatic
        }
    }
}

enum HighlighterColor: Equatable, Identifiable, CaseIterable {
    case none
    case yellow
    case red
    case green

    var id: String {
        switch self {
        case .none: return "none"
        case .yellow: return "yellow"
        case .red: return "red"
        case .green: return "green"
        }
    }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .green: return "Green"
        }
    }

    var emoji: String {
        switch self {
        case .none: return "◻️"
        case .yellow: return "🟨"
        case .red: return "🟥"
        case .green: return "🟩"
        }
    }

    #if os(macOS)
    var nsColor: NSColor? {
        switch self {
        case .none:
            return nil
        case .yellow:
            return NSColor.systemYellow.withAlphaComponent(0.35)
        case .red:
            return NSColor.systemRed.withAlphaComponent(0.35)
        case .green:
            return NSColor.systemGreen.withAlphaComponent(0.35)
        }
    }
    #else
    var uiColor: UIColor? {
        switch self {
        case .none:
            return nil
        case .yellow:
            return UIColor.systemYellow.withAlphaComponent(0.35)
        case .red:
            return UIColor.systemRed.withAlphaComponent(0.35)
        case .green:
            return UIColor.systemGreen.withAlphaComponent(0.35)
        }
    }
    #endif

    static func from(id: String) -> HighlighterColor {
        switch id {
        case "yellow": return .yellow
        case "red": return .red
        case "green": return .green
        default: return .none
        }
    }
}

