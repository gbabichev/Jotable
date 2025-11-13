import Foundation

/// Snapshot of a text range inside the rich text editor.
struct LinkRangeSnapshot: Equatable {
    let location: Int
    let length: Int

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

/// Represents a pending link edit request coming from the platform editor.
struct LinkEditContext: Equatable, Identifiable {
    let id: UUID
    let range: LinkRangeSnapshot
    let urlString: String
    let displayText: String
}

/// Payload used to insert or replace a link in the text editor.
struct URLInsertionRequest: Equatable {
    let id: UUID
    let urlString: String
    let displayText: String
    let replacementRange: LinkRangeSnapshot?
}
