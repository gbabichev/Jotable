//
//  TodoTextAttributes.swift
//  Jotable
//

import Foundation

enum TodoTextAttributes {
    static let todoIDKey = NSAttributedString.Key("com.jotable.todoID")
    static let completionRenderedKey = NSAttributedString.Key("com.jotable.todoCompletionRendered")
    static let originalStrikethroughStyleKey = NSAttributedString.Key("com.jotable.todoOriginalStrikethroughStyle")
    private static let linkedCheckboxPrefix = "com.jotable.linkedTodoCheckbox:"

    static func linkedCheckboxID(for todoID: String) -> String {
        linkedCheckboxPrefix + todoID
    }

    static func linkedTodoID(from checkboxID: String) -> String? {
        guard checkboxID.hasPrefix(linkedCheckboxPrefix) else { return nil }
        return String(checkboxID.dropFirst(linkedCheckboxPrefix.count))
    }
}
