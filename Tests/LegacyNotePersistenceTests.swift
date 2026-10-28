import Foundation
import SwiftData

// These tests use the real app models and storage helper, with two temporary
// SQLite stores and CloudKit explicitly disabled. No user app data is opened.
@main
struct LegacyNotePersistenceTests {
    @MainActor
    static func main() throws {
        if CommandLine.arguments.count > 1 {
            try checkHistoricalDatabase(at: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "JotableLegacyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let archive = try NSKeyedArchiver.archivedData(
            withRootObject: NSAttributedString(string: "Original legacy rich text"),
            requiringSecureCoding: false
        )
        var noteID = ""

        // Seed the old representation only, then close both stores to model
        // an upgrade/relaunch rather than an already-created new-format note.
        try autoreleasepool {
            let (metadata, documents) = try stores(in: directory)
            let note = Item(timestamp: oldDate, title: "travel", content: "Original legacy rich text")
            note.attributedContent = archive
            metadata.mainContext.insert(note)
            try metadata.mainContext.save()
            noteID = note.id.uuidString
            let initialCount = try documents.mainContext.fetchCount(FetchDescriptor<NoteDocument>())
            precondition(initialCount == 0)
        }

        try autoreleasepool {
            let (metadata, documents) = try stores(in: directory)
            let note = try metadata.mainContext.fetch(FetchDescriptor<Item>()).first!
            let context = documents.mainContext
            precondition(note.id.uuidString == noteID)
            let missing = try NoteDocumentStore.fetch(noteID: noteID, context: context)
            precondition(missing == nil)
            let legacy = NoteDocumentSnapshot.resolve(item: note, document: missing)
            precondition(legacy.plainText == note.content && legacy.attributedContent == archive)
            let countAfterRead = try context.fetchCount(FetchDescriptor<NoteDocument>())
            precondition(countAfterRead == 0,
                         "Reading a legacy note must not create a newer body")
            print("PASS: legacy note survives relaunch and reads without creating a document")

            let document = try NoteDocumentStore.documentForEditing(item: note, context: context)
            precondition(document.noteID == noteID && document.attributedContent == archive)
            document.plainText = "Edited after upgrade"
            document.attributedContent = nil
            document.updatedAt = oldDate.addingTimeInterval(60)
            try context.save()
            let selected = try NoteDocumentStore.documentForEditing(item: note, context: context)
            precondition(selected === document)
            let countAfterEdit = try context.fetchCount(FetchDescriptor<NoteDocument>())
            precondition(countAfterEdit == 1)
            let updated = NoteDocumentSnapshot.resolve(item: note, document: selected)
            precondition(updated.plainText == "Edited after upgrade" && updated.attributedContent == nil,
                         "A new plain-text document must not resurrect the legacy rich-text archive")
            precondition(note.attributedContent == archive, "Legacy data must remain recoverable")
            print("PASS: first edit upgrades the body once and keeps the legacy backup")
            print("PASS: new plain-text revision does not mix with old rich text")
        }

        try autoreleasepool {
            let (metadata, documents) = try stores(in: directory)
            let note = try metadata.mainContext.fetch(FetchDescriptor<Item>()).first!
            let document = try NoteDocumentStore.fetch(noteID: noteID, context: documents.mainContext)!
            precondition(NoteDocumentSnapshot.resolve(item: note, document: document).plainText == "Edited after upgrade")
            precondition(document.attributedContent == nil)
            print("PASS: upgraded body survives another relaunch")

            // Replay a separately-created body arriving from an offline peer.
            let peer = NoteDocument(noteID: noteID, plainText: "Peer's newer edit",
                                    updatedAt: oldDate.addingTimeInterval(120))
            documents.mainContext.insert(peer)
            try documents.mainContext.save()
            let all = try documents.mainContext.fetch(FetchDescriptor<NoteDocument>())
            precondition(NoteDocumentStore.latest(in: all)?.plainText == "Peer's newer edit")
            precondition(NoteDocumentStore.latest(in: all.reversed())?.plainText == "Peer's newer edit")
            precondition(all.count == 2, "Resolving a duplicate must preserve both bodies")
            print("PASS: replayed peer revision wins consistently without deleting either body")

            peer.updatedAt = document.updatedAt
            let firstOrder = NoteDocumentStore.latest(in: [document, peer])!
            let otherOrder = NoteDocumentStore.latest(in: [peer, document])!
            precondition(firstOrder.plainText == otherOrder.plainText)
            precondition(NoteDocumentSnapshot(document: peer) != NoteDocumentSnapshot(document: document),
                         "Equal timestamps must not hide a different imported body")
            print("PASS: equal-timestamp revisions resolve consistently and remain distinguishable")
        }
        print("All legacy persistence checks passed (local stores; no CloudKit transport test).")
    }

    @MainActor
    private static func checkHistoricalDatabase(at directory: URL) throws {
        let (metadata, documents) = try stores(in: directory)
        let context = metadata.mainContext
        let notes = try context.fetch(FetchDescriptor<Item>())
        let todos = try context.fetch(FetchDescriptor<TodoItem>())
        precondition(notes.count == 2 && todos.count == 2)
        for note in notes {
            precondition(note.category?.name == "Historical category")
            precondition(todos.contains { $0.sourceNoteID == note.id.uuidString })
            let legacy = NoteDocumentSnapshot.resolve(item: note, document: nil)
            precondition(legacy.attributedContent != nil)
            let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: legacy.attributedContent!)!
            precondition(decoded.string == note.content)
            let body = try NoteDocumentStore.documentForEditing(item: note, context: documents.mainContext)
            body.plainText += "\nEdited after the real database upgrade"
            body.attributedContent = nil
            body.updatedAt = Date()
            try documents.mainContext.save()
            let resolved = NoteDocumentSnapshot.resolve(item: note, document: body)
            precondition(resolved.plainText.hasSuffix("Edited after the real database upgrade"))
            precondition(resolved.attributedContent == nil)
        }
        print("PASS: historical SQLite schema upgrades with categories and todo links intact")
        print("PASS: historical rich and large external-storage bodies decode and upgrade")
        _ = try context.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        print("PASS: persistent history can be read after the historical schema upgrade")
    }

    @MainActor
    private static func stores(in directory: URL) throws -> (ModelContainer, ModelContainer) {
        let metadataSchema = Schema([Item.self, Category.self, TodoItem.self])
        let bodySchema = Schema([NoteDocument.self])
        let metadata = try ModelContainer(for: metadataSchema, configurations: [
            ModelConfiguration(schema: metadataSchema, url: directory.appending(path: "metadata.store"), cloudKitDatabase: .none)
        ])
        let documents = try ModelContainer(for: bodySchema, configurations: [
            ModelConfiguration(schema: bodySchema, url: directory.appending(path: "documents.store"), cloudKitDatabase: .none)
        ])
        metadata.mainContext.autosaveEnabled = false
        documents.mainContext.autosaveEnabled = false
        return (metadata, documents)
    }
}
