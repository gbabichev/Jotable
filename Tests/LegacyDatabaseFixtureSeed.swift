import Foundation
import SwiftData

// Compiled separately against the historical models, with the same module
// name as the current-model test executable. No current model writes this DB.
@main
struct LegacyDatabaseFixtureSeed {
    @MainActor
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema([Item.self, Category.self, TodoItem.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: directory.appending(path: "metadata.store"), cloudKitDatabase: .none)
        ])
        let context = container.mainContext
        context.autosaveEnabled = false
        let category = Category(name: "Historical category")
        context.insert(category)
        for (title, body) in [
            ("Historical rich note", "Old rich body before the document split"),
            ("Historical large note", String(repeating: "Old rich content\n", count: 30_000))
        ] {
            let note = Item(title: title, content: body)
            note.category = category
            note.attributedContent = try NSKeyedArchiver.archivedData(
                withRootObject: NSAttributedString(string: body), requiringSecureCoding: false
            )
            context.insert(note)
            let todo = TodoItem(text: "Historical todo", sourceText: "Old", sourceNote: note,
                                sourceRangeLocation: 0, sourceRangeLength: 3)
            context.insert(todo)
        }
        try context.save()
        print("Seeded a pre-split SQLite database, including the removed todo relationships.")
    }
}
