import Foundation
import SwiftData

struct NoteDocumentSnapshot: Equatable {
    let plainText: String
    let attributedContent: Data?
    let updatedAt: Date

    init(plainText: String, attributedContent: Data?, updatedAt: Date) {
        self.plainText = plainText
        self.attributedContent = attributedContent
        self.updatedAt = updatedAt
    }

    init(document: NoteDocument) {
        self.init(plainText: document.plainText,
                  attributedContent: document.attributedContent,
                  updatedAt: document.updatedAt)
    }

    /// Resolve a whole revision. A nil archive in a document means plain text;
    /// it must never fall back to an older rich-text archive on Item.
    static func resolve(item: Item, document: NoteDocument?) -> Self {
        if let document { return Self(document: document) }
        return Self(plainText: item.content,
                    attributedContent: item.attributedContent,
                    updatedAt: item.timestamp)
    }
}

enum NoteDocumentStore {
    /// Offline devices can independently create bodies for the same legacy
    /// note. Keep all revisions, but choose the same winner on every reader.
    static func latest(in documents: [NoteDocument]) -> NoteDocument? {
        documents.max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            if lhs.plainText != rhs.plainText { return lhs.plainText < rhs.plainText }
            switch (lhs.attributedContent, rhs.attributedContent) {
            case (nil, .some): return true
            case (.some, nil), (nil, nil): return false
            case (.some(let left), .some(let right)):
                return left.lexicographicallyPrecedes(right)
            }
        }
    }

    static func fetch(noteID: String, context: ModelContext) throws -> NoteDocument? {
        let descriptor = FetchDescriptor<NoteDocument>(
            predicate: #Predicate { $0.noteID == noteID }
        )
        return latest(in: try context.fetch(descriptor))
    }

    static func documentForEditing(item: Item, context: ModelContext) throws -> NoteDocument {
        // A failed lookup is not proof that the document is missing. Propagate
        // the error instead of creating another body from stale legacy fields.
        if let document = try fetch(noteID: item.id.uuidString, context: context) {
            return document
        }
        let document = NoteDocument(noteID: item.id.uuidString,
                                    plainText: item.content,
                                    attributedContent: item.attributedContent,
                                    updatedAt: item.timestamp)
        context.insert(document)
        return document
    }
}
