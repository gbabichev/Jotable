import Foundation
import SwiftData

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Migrates stored notes to attach font size metadata to checkbox attachments so previews render correctly
enum CheckboxMigrator {
    private static let migrationKey = "checkboxFontMigrationCompleted_v1"

    static func runIfNeeded(context: ModelContext) {
        // Avoid repeated work across launches
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        do {
            let items = try context.fetch(FetchDescriptor<Item>())
            var didChangeAny = false

            for item in items {
                guard let data = item.attributedContent,
                      let attributed = unarchiveAttributedString(data) else {
                    continue
                }

                let (migrated, changed) = migrateCheckboxes(in: attributed)
                if changed, let archived = archiveAttributedString(migrated) {
                    item.attributedContent = archived
                    didChangeAny = true
                }
            }

            if didChangeAny {
                try context.save()
            }

            UserDefaults.standard.set(true, forKey: migrationKey)
        } catch {
            // If migration fails, skip setting the flag so we can try again on next launch
            print("⚠️ Checkbox migration failed: \(error)")
        }
    }

    // MARK: - Migration helpers

    private static func migrateCheckboxes(in attributedString: NSAttributedString) -> (NSAttributedString, Bool) {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        var changed = false

        mutable.enumerateAttribute(.attachment, in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
            guard let checkbox = value as? CheckboxTextAttachment else { return }
            guard checkbox.fontPointSize == nil else { return }

            let fontSize = sampleFontSize(around: range, in: mutable) ?? defaultFontSize()
            checkbox.fontPointSize = fontSize

            // Update the attachment's internal data so it persists across archives
            let stateDict: [String: Any] = [
                "checkboxID": checkbox.checkboxID,
                "isChecked": checkbox.isChecked,
                "fontPointSize": fontSize
            ]
            if let stateData = try? JSONSerialization.data(withJSONObject: stateDict) {
                checkbox.contents = stateData
            }

            // Ensure the trailing space (if any) has a font attribute so caret height stays consistent
            let nextIndex = range.location + range.length
            if nextIndex < mutable.length {
                let nextCharRange = NSRange(location: nextIndex, length: 1)
                if mutable.attributedSubstring(from: nextCharRange).string == " " &&
                    mutable.attribute(.font, at: nextIndex, effectiveRange: nil) == nil {
                    #if canImport(UIKit)
                    mutable.addAttribute(.font, value: UIFont.systemFont(ofSize: fontSize), range: nextCharRange)
                    #else
                    mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize), range: nextCharRange)
                    #endif
                }
            }

            changed = true
        }

        return (mutable, changed)
    }

    private static func sampleFontSize(around range: NSRange, in attributedString: NSAttributedString) -> CGFloat? {
        let candidates = [
            range.location + range.length,          // character after attachment
            max(range.location - 1, 0)              // character before attachment
        ]

        for index in candidates {
            guard index < attributedString.length else { continue }
            #if canImport(UIKit)
            if let font = attributedString.attribute(.font, at: index, effectiveRange: nil) as? UIFont {
                return font.pointSize
            }
            #else
            if let font = attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont {
                return font.pointSize
            }
            #endif
        }

        return nil
    }

    private static func defaultFontSize() -> CGFloat {
        #if canImport(UIKit)
        return UIFont.systemFontSize
        #else
        return NSFont.systemFontSize
        #endif
    }

    // MARK: - Archiving helpers (mirrors NoteEditorView)

    private static func archiveAttributedString(_ attributedString: NSAttributedString) -> Data? {
        let cleanedString = removeCheckboxMarkerAttribute(attributedString)
        let stringWithStates = extractAndStoreCheckboxStates(cleanedString)
        let processedString = ColorMapping.preprocessForArchiving(stringWithStates)

        return try? NSKeyedArchiver.archivedData(
            withRootObject: processedString,
            requiringSecureCoding: false
        )
    }

    private static func removeCheckboxMarkerAttribute(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let markerKey = NSAttributedString.Key(rawValue: "checkboxStateChanged")

        var pos = 0
        while pos < mutable.length {
            var range = NSRange()
            let attrs = mutable.attributes(at: pos, longestEffectiveRange: &range, in: NSRange(location: pos, length: mutable.length - pos))
            if attrs[markerKey] != nil {
                mutable.removeAttribute(markerKey, range: range)
            }
            pos = range.location + range.length
        }

        return mutable
    }

    private static func extractAndStoreCheckboxStates(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let checkboxIDKey = NSAttributedString.Key(rawValue: "checkboxID")
        let checkboxIsCheckedKey = NSAttributedString.Key(rawValue: "checkboxIsChecked")

        var pos = 0
        while pos < mutable.length {
            var range = NSRange()
            let attrs = mutable.attributes(at: pos, longestEffectiveRange: &range, in: NSRange(location: pos, length: mutable.length - pos))

            if let checkbox = attrs[.attachment] as? CheckboxTextAttachment {
                mutable.addAttribute(checkboxIDKey, value: checkbox.checkboxID, range: range)
                mutable.addAttribute(checkboxIsCheckedKey, value: NSNumber(value: checkbox.isChecked), range: range)
            }

            pos = range.location + range.length
        }

        return mutable
    }

    private static func unarchiveAttributedString(_ data: Data) -> NSAttributedString? {
        guard let result = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) else {
            return nil
        }
        let colored = ColorMapping.postprocessAfterUnarchiving(result)
        return restoreCheckboxStates(colored)
    }

    private static func restoreCheckboxStates(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let checkboxIDKey = NSAttributedString.Key(rawValue: "checkboxID")
        let checkboxIsCheckedKey = NSAttributedString.Key(rawValue: "checkboxIsChecked")

        var pos = 0
        while pos < mutable.length {
            var range = NSRange()
            let attrs = mutable.attributes(at: pos, longestEffectiveRange: &range, in: NSRange(location: pos, length: mutable.length - pos))

            if let checkboxID = attrs[checkboxIDKey] as? String,
               let isCheckedNum = attrs[checkboxIsCheckedKey] as? NSNumber,
               let checkbox = attrs[.attachment] as? CheckboxTextAttachment {
                checkbox.isChecked = isCheckedNum.boolValue
                let stateDict: [String: Any] = [
                    "checkboxID": checkboxID,
                    "isChecked": checkbox.isChecked,
                    "fontPointSize": checkbox.fontPointSize as Any
                ]
                if let stateData = try? JSONSerialization.data(withJSONObject: stateDict) {
                    checkbox.contents = stateData
                }
            }

            pos = range.location + range.length
        }

        return mutable
    }
}
