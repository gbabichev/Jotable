import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Handles auto-formatting features like auto-numbering, bullets, and checkboxes
struct AutoFormatting {
    /// Detects if a line starts with a number pattern (e.g., "1. ", "2. ")
    /// Returns the next numbered line if content exists, or nil to remove numbering if blank
    static func handleNumberedList(lineText: String) -> String? {
        // Pattern: one or more digits followed by ". "
        guard let match = lineText.range(of: #"^(\d+)\.\s"#, options: .regularExpression) else {
            return nil
        }

        // Get the matched text (e.g., "1. ")
        let matchedText = String(lineText[match])

        // Extract just the number part by removing the ". " suffix
        let numberPartWithDot = String(matchedText.dropLast(2))  // Remove ". "

        // Get the text after the number pattern
        let contentStart = match.upperBound
        let contentAfterNumber = String(lineText[contentStart...]).trimmingCharacters(in: .whitespaces)

        // If the line is blank after the number, return just newline (removes numbering)
        if contentAfterNumber.isEmpty {
            return "\n"
        }

        // Convert to Int and increment
        if let number = Int(numberPartWithDot) {
            let nextNumber = number + 1
            return "\n\(nextNumber). "
        }

        return nil
    }

    /// Detects if a line starts with a dash pattern (e.g., "- ")
    /// Returns a new bullet point if content exists, or nil to remove bullet if blank
    static func handleBulletPoint(lineText: String) -> String? {
        // Pattern: a dash followed by a space at the start of the line
        guard lineText.hasPrefix("- ") else {
            return nil
        }

        // Get the text after the dash pattern
        let contentAfterDash = String(lineText.dropFirst(2)).trimmingCharacters(in: .whitespaces)

        // If the line is blank after the dash, return just newline (removes bullet)
        if contentAfterDash.isEmpty {
            return "\n"
        }

        // Return a new bullet point
        return "\n- "
    }

    /// Detects and converts checkbox patterns "[ ]" and "[x]" or "[X]" to CheckboxTextAttachment
    /// Returns true if checkboxes were found and converted
    static func convertCheckboxPatterns(in attributedString: NSMutableAttributedString, spaceAttributes: [NSAttributedString.Key: Any]? = nil) -> Bool {
        var foundCheckbox = false
        let string = attributedString.string

        // Pattern for unchecked checkbox: [ ]
        let uncheckedPattern = "\\[ \\]"
        // Pattern for checked checkbox: [x] or [X]
        let checkedPattern = "\\[[xX]\\]"

        // Collect all replacements first (search indices change with replacements)
        var replacements: [(range: NSRange, attachment: CheckboxTextAttachment)] = []

        // Search for unchecked checkboxes
        let uncheckedRegex = try? NSRegularExpression(pattern: uncheckedPattern, options: [])
        let uncheckedMatches = uncheckedRegex?.matches(in: string, options: [], range: NSRange(location: 0, length: string.count)) ?? []
        for match in uncheckedMatches {
            let attachment = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false)
            replacements.append((match.range, attachment))
        }

        // Search for checked checkboxes
        let checkedRegex = try? NSRegularExpression(pattern: checkedPattern, options: [])
        let checkedMatches = checkedRegex?.matches(in: string, options: [], range: NSRange(location: 0, length: string.count)) ?? []
        for match in checkedMatches {
            let attachment = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: true)
            replacements.append((match.range, attachment))
        }

        // Sort by range location in reverse order (so we replace from end to start)
        replacements.sort { $0.range.location > $1.range.location }

        // Apply replacements - attachments should not have font attributes
        // The attachment itself is sized based on attachmentBounds, not font attributes
        for (range, attachment) in replacements {
            let attachmentString = NSAttributedString(attachment: attachment)
            attributedString.replaceCharacters(in: range, with: attachmentString)
            foundCheckbox = true

            // Apply font attributes to the space after the checkbox if attributes provided
            if let attrs = spaceAttributes {
                let spaceInsertionPos = range.location + 1
                if spaceInsertionPos < attributedString.length {
                    let nextCharRange = NSRange(location: spaceInsertionPos, length: 1)
                    let nextChar = attributedString.attributedSubstring(from: nextCharRange).string
                    if nextChar == " " {
                        attributedString.addAttributes(attrs, range: nextCharRange)
                    }
                }
            }
        }

        return foundCheckbox
    }

    /// Gets information about the line containing the given range
    static func getLineInfo(for range: NSRange, in text: String) -> (range: NSRange, text: String)? {
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
        let lineText = nsText.substring(with: lineRange)
            .trimmingCharacters(in: .newlines)
        return (lineRange, lineText)
    }

}
