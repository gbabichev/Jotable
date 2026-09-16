import Foundation
import SwiftData

// High-frequency editor data lives separately from Item metadata. There is no
// SwiftData relationship back to Item: that is intentional, so saving a body
// cannot invalidate the sidebar's Item and Category observation graph.
@Model
final class NoteDocument {
    var noteID: String = ""
    var plainText: String = ""
    @Attribute(.externalStorage) var attributedContent: Data?
    var updatedAt: Date = Date()

    init(
        noteID: String,
        plainText: String = "",
        attributedContent: Data? = nil,
        updatedAt: Date = Date()
    ) {
        self.noteID = noteID
        self.plainText = plainText
        self.attributedContent = attributedContent
        self.updatedAt = updatedAt
    }
}
