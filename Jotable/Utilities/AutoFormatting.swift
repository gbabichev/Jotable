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

    /// Detects if a line starts with a number pattern and handles renumbering of subsequent lines
    /// This version has access to the full text to renumber properly
    static func handleNumberedListWithRenumbering(lineText: String, fullText: String, insertionIndex: Int) -> (newText: String, renumberPositions: [(range: NSRange, newNumber: Int)])? {
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
            return (newText: "\n", renumberPositions: [])
        }

        // Convert to Int and increment
        guard let number = Int(numberPartWithDot) else {
            return nil
        }

        let nextNumber = number + 1
        var renumberPositions: [(range: NSRange, newNumber: Int)] = []

        // Now scan subsequent lines to renumber them
        var currentNumber = nextNumber + 1
        var currentPos = insertionIndex

        // Find the start of the next line
        while currentPos < fullText.count && fullText[fullText.index(fullText.startIndex, offsetBy: currentPos)] != "\n" {
            currentPos += 1
        }

        // Skip the newline
        if currentPos < fullText.count {
            currentPos += 1
        }

        // Scan subsequent lines
        while currentPos < fullText.count {
            // Find the end of the current line
            var lineEnd = currentPos
            while lineEnd < fullText.count && fullText[fullText.index(fullText.startIndex, offsetBy: lineEnd)] != "\n" {
                lineEnd += 1
            }

            let lineRange = NSRange(location: currentPos, length: lineEnd - currentPos)
            let lineContent = (fullText as NSString).substring(with: lineRange)

            // Check if this line starts with a number pattern
            if let numberMatch = lineContent.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let numberPrefixLength = lineContent.distance(from: lineContent.startIndex, to: numberMatch.upperBound)
                let oldNumberRange = NSRange(location: currentPos, length: numberPrefixLength)
                renumberPositions.append((range: oldNumberRange, newNumber: currentNumber))
                currentNumber += 1
                currentPos = lineEnd + 1 // +1 for the newline
            } else {
                // Line doesn't have a number pattern, stop renumbering
                break
            }
        }

        return (newText: "\n\(nextNumber). ", renumberPositions: renumberPositions)
    }

    /// Detects if a line starts with a dash or bullet pattern (e.g., "- " or "• ")
    /// Returns a new bullet point if content exists, or nil to remove bullet if blank
    static func handleBulletPoint(lineText: String) -> String? {
        var bulletPrefix = ""
        var contentStart = 0

        // Check for dash pattern (- )
        if lineText.hasPrefix("- ") {
            bulletPrefix = "- "
            contentStart = 2
        }
        // Check for bullet character pattern (• )
        else if lineText.hasPrefix("• ") {
            bulletPrefix = "• "
            contentStart = 2
        }
        else {
            return nil
        }

        // Get the text after the bullet pattern
        let contentAfterBullet = String(lineText.dropFirst(contentStart)).trimmingCharacters(in: .whitespaces)

        // If the line is blank after the bullet, return just newline (removes bullet)
        if contentAfterBullet.isEmpty {
            return "\n"
        }

        // Return a new bullet point with the same prefix
        return "\n\(bulletPrefix)"
    }

    /// Returns true when an empty bullet line should terminate an existing list.
    /// Standalone empty bullets should be left alone so Enter behaves like a normal newline.
    static func shouldRemoveEmptyBulletLine(lineText: String, fullText: String, lineRange: NSRange) -> Bool {
        let bulletPrefix: String

        if lineText.hasPrefix("- ") {
            bulletPrefix = "- "
        } else if lineText.hasPrefix("• ") {
            bulletPrefix = "• "
        } else {
            return false
        }

        let currentContent = String(lineText.dropFirst(bulletPrefix.count))
            .trimmingCharacters(in: .whitespaces)
        guard currentContent.isEmpty, lineRange.location > 0 else {
            return false
        }

        let nsText = fullText as NSString
        let previousLineLookupLocation = lineRange.location - 1
        let previousLineRange = nsText.lineRange(for: NSRange(location: previousLineLookupLocation, length: 0))
        let previousLineText = nsText.substring(with: previousLineRange)
            .trimmingCharacters(in: .newlines)

        guard previousLineText.hasPrefix(bulletPrefix) else {
            return false
        }

        let previousContent = String(previousLineText.dropFirst(bulletPrefix.count))
            .trimmingCharacters(in: .whitespaces)
        return !previousContent.isEmpty
    }

    /// Returns true when an empty numbered line should terminate an existing numbered list.
    static func shouldRemoveEmptyNumberedLine(lineText: String, fullText: String, lineRange: NSRange) -> Bool {
        guard let currentMatch = lineText.range(of: #"^\d+\.\s"#, options: .regularExpression) else {
            return false
        }

        let currentContent = String(lineText[currentMatch.upperBound...])
            .trimmingCharacters(in: .whitespaces)
        guard currentContent.isEmpty, lineRange.location > 0 else {
            return false
        }

        let nsText = fullText as NSString
        let previousLineLookupLocation = lineRange.location - 1
        let previousLineRange = nsText.lineRange(for: NSRange(location: previousLineLookupLocation, length: 0))
        let previousLineText = nsText.substring(with: previousLineRange)
            .trimmingCharacters(in: .newlines)

        guard let previousMatch = previousLineText.range(of: #"^\d+\.\s"#, options: .regularExpression) else {
            return false
        }

        let previousContent = String(previousLineText[previousMatch.upperBound...])
            .trimmingCharacters(in: .whitespaces)
        return !previousContent.isEmpty
    }

    /// Returns true when an empty checkbox line should terminate an existing checkbox list.
    static func shouldRemoveEmptyCheckboxLine(in attributedString: NSAttributedString, lineRange: NSRange) -> Bool {
        guard lineRange.location > 0, lineRange.location < attributedString.length else {
            return false
        }

        guard attributedString.attribute(.attachment, at: lineRange.location, longestEffectiveRange: nil, in: lineRange) is CheckboxTextAttachment else {
            return false
        }

        let currentContentStart = min(lineRange.location + 1, attributedString.length)
        let currentContentRange = NSRange(
            location: currentContentStart,
            length: max(0, NSMaxRange(lineRange) - currentContentStart)
        )
        let currentContent = attributedString.attributedSubstring(from: currentContentRange).string
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentContent.isEmpty else {
            return false
        }

        let fullText = attributedString.string as NSString
        let previousLineLookupLocation = lineRange.location - 1
        let previousLineRange = fullText.lineRange(for: NSRange(location: previousLineLookupLocation, length: 0))

        guard previousLineRange.location < attributedString.length,
              attributedString.attribute(.attachment, at: previousLineRange.location, longestEffectiveRange: nil, in: previousLineRange) is CheckboxTextAttachment else {
            return false
        }

        let previousContentStart = min(previousLineRange.location + 1, attributedString.length)
        let previousContentRange = NSRange(
            location: previousContentStart,
            length: max(0, NSMaxRange(previousLineRange) - previousContentStart)
        )
        let previousContent = attributedString.attributedSubstring(from: previousContentRange).string
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !previousContent.isEmpty
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
            #if canImport(UIKit)
            let fontSize = (spaceAttributes?[.font] as? UIFont)?.pointSize
            #else
            let fontSize = (spaceAttributes?[.font] as? NSFont)?.pointSize
            #endif
            let attachment = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: false, fontPointSize: fontSize)
            replacements.append((match.range, attachment))
        }

        // Search for checked checkboxes
        let checkedRegex = try? NSRegularExpression(pattern: checkedPattern, options: [])
        let checkedMatches = checkedRegex?.matches(in: string, options: [], range: NSRange(location: 0, length: string.count)) ?? []
        for match in checkedMatches {
            #if canImport(UIKit)
            let fontSize = (spaceAttributes?[.font] as? UIFont)?.pointSize
            #else
            let fontSize = (spaceAttributes?[.font] as? NSFont)?.pointSize
            #endif
            let attachment = CheckboxTextAttachment(checkboxID: UUID().uuidString, isChecked: true, fontPointSize: fontSize)
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
