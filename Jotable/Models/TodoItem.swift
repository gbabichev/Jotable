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

@Model
final class TodoItem {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isCompleted: Bool = false
    var completedAt: Date?

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
        sourceRangeLength: Int = 0
    ) {
        let now = Date()
        self.id = UUID()
        self.text = text
        self.createdAt = now
        self.updatedAt = now
        self.isCompleted = false
        self.completedAt = nil
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
