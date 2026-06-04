//
//  TodoItem.swift
//  Jotable
//

import Foundation
import SwiftData

struct TodoCreationRequest {
    let text: String
    let selectedRangeLocation: Int
    let selectedRangeLength: Int
}

struct StandaloneTodoDraft {
    let text: String
    let dueDate: Date?
    let priority: TodoPriority
}

enum TodoPriority: Int, CaseIterable, Identifiable, Codable, Sendable {
    case low = 0
    case normal = 1
    case high = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }
}

@Model
final class TodoItem {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isCompleted: Bool = false
    var completedAt: Date?
    var sortOrder: Int = 0
    var dueDate: Date?
    var priorityRawValue: Int = TodoPriority.normal.rawValue

    var sourceText: String = ""
    var sourceNoteID: String = ""
    var sourceNoteTitleSnapshot: String = ""
    var sourceCategoryNameSnapshot: String = ""
    var sourceRangeLocation: Int = 0
    var sourceRangeLength: Int = 0
    var isSourceTextAvailable: Bool = true

    var sourceNote: Item? = nil

    init(
        text: String,
        sourceText: String,
        sourceNote: Item?,
        sourceRangeLocation: Int = 0,
        sourceRangeLength: Int = 0,
        sortOrder: Int = 0,
        dueDate: Date? = nil,
        priority: TodoPriority = .normal
    ) {
        let now = Date()
        self.id = UUID()
        self.text = text
        self.createdAt = now
        self.updatedAt = now
        self.isCompleted = false
        self.completedAt = nil
        self.sortOrder = sortOrder
        self.dueDate = dueDate
        self.priorityRawValue = priority.rawValue
        self.sourceText = sourceText
        self.sourceNote = sourceNote
        self.sourceNoteID = sourceNote?.id.uuidString ?? ""
        self.sourceNoteTitleSnapshot = sourceNote?.title ?? ""
        self.sourceCategoryNameSnapshot = sourceNote?.category?.name ?? ""
        self.sourceRangeLocation = sourceRangeLocation
        self.sourceRangeLength = sourceRangeLength
        self.isSourceTextAvailable = true
    }
}

extension TodoItem {
    var priority: TodoPriority {
        get {
            TodoPriority(rawValue: priorityRawValue) ?? .normal
        }
        set {
            priorityRawValue = newValue.rawValue
        }
    }
}
