#if os(macOS)
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExportPackage: Codable {
    let categories: [ExportedCategory]
    let notes: [ExportedNote]
    let todos: [ExportedTodo]?
}

struct ExportedCategory: Codable {
    let name: String
    let color: String
    let isPrivate: Bool
    let isHiddenFromHome: Bool?
    let sortOrder: Int
    let createdAt: Date
}

struct ExportedNote: Codable {
    let title: String
    let content: String
    let createdAt: Date
    let timestamp: Date
    let categoryIndex: Int?
    let attributedContentBase64: String?
}

struct ExportedTodo: Codable {
    let text: String
    let sourceText: String
    let createdAt: Date
    let updatedAt: Date
    let isCompleted: Bool
    let completedAt: Date?
    let sourceNoteIndex: Int?
    let sourceNoteTitleSnapshot: String
    let sourceCategoryNameSnapshot: String
    let sourceRangeLocation: Int
    let sourceRangeLength: Int
    let isSourceTextAvailable: Bool?
}

enum DataExportImport {
    static func exportAll(from context: ModelContext) throws -> Data {
        let categoryDescriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.timestamp)]
        )
        let noteDescriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let todoDescriptor = FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        let categories = try context.fetch(categoryDescriptor)
            .filter { !$0.isSystemTrash }
        let notes = try context.fetch(noteDescriptor)
            .filter { !$0.isInTrash }
        let todos = try context.fetch(todoDescriptor)

        let exportedCategories: [ExportedCategory] = categories.enumerated().map { index, category in
            ExportedCategory(
                name: category.name,
                color: category.color,
                isPrivate: category.isPrivate,
                isHiddenFromHome: category.isHiddenFromHome,
                sortOrder: index,
                createdAt: category.timestamp
            )
        }

        let categoryIndexMap: [PersistentIdentifier: Int] = Dictionary(uniqueKeysWithValues: categories.enumerated().map { index, category in
            (category.persistentModelID, index)
        })

        let exportedNotes: [ExportedNote] = notes.map { note in
            let categoryIndex = note.category.flatMap { categoryIndexMap[$0.persistentModelID] }
            let attributedBase64 = note.attributedContent?.base64EncodedString()

            return ExportedNote(
                title: note.title,
                content: note.content,
                createdAt: note.createdAt,
                timestamp: note.timestamp,
                categoryIndex: categoryIndex,
                attributedContentBase64: attributedBase64
            )
        }

        let noteIndexMap: [PersistentIdentifier: Int] = Dictionary(uniqueKeysWithValues: notes.enumerated().map { index, note in
            (note.persistentModelID, index)
        })

        let exportedTodos: [ExportedTodo] = todos.map { todo in
            let sourceNoteIndex = todo.sourceNote.flatMap { noteIndexMap[$0.persistentModelID] }

            return ExportedTodo(
                text: todo.text,
                sourceText: todo.sourceText,
                createdAt: todo.createdAt,
                updatedAt: todo.updatedAt,
                isCompleted: todo.isCompleted,
                completedAt: todo.completedAt,
                sourceNoteIndex: sourceNoteIndex,
                sourceNoteTitleSnapshot: todo.sourceNoteTitleSnapshot,
                sourceCategoryNameSnapshot: todo.sourceCategoryNameSnapshot,
                sourceRangeLocation: todo.sourceRangeLocation,
                sourceRangeLength: todo.sourceRangeLength,
                isSourceTextAvailable: todo.isSourceTextAvailable
            )
        }

        let package = ExportPackage(
            categories: exportedCategories,
            notes: exportedNotes,
            todos: exportedTodos
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(package)
    }

    @discardableResult
    static func importPackage(from data: Data, into context: ModelContext) throws -> (importedCategories: Int, importedNotes: Int, importedTodos: Int) {
        let decoder = JSONDecoder()
        let package = try decoder.decode(ExportPackage.self, from: data)

        var createdCategories: [Category] = []
        var createdNotes: [Item] = []
        for categoryData in package.categories {
            let category = Category(
                name: categoryData.name,
                color: categoryData.color,
                sortOrder: categoryData.sortOrder,
                isPrivate: categoryData.isPrivate,
                isHiddenFromHome: categoryData.isHiddenFromHome ?? false
            )
            category.timestamp = categoryData.createdAt
            context.insert(category)
            createdCategories.append(category)
        }

        for noteData in package.notes {
            let note = Item(
                timestamp: noteData.timestamp,
                title: noteData.title,
                content: noteData.content
            )
            note.createdAt = noteData.createdAt
            if let categoryIndex = noteData.categoryIndex, categoryIndex < createdCategories.count {
                note.category = createdCategories[categoryIndex]
            }
            if let base64 = noteData.attributedContentBase64, let attributedData = Data(base64Encoded: base64) {
                note.attributedContent = attributedData
            }
            context.insert(note)
            createdNotes.append(note)
        }

        let importedTodos = package.todos ?? []
        for todoData in importedTodos {
            let sourceNote: Item? = {
                guard let sourceNoteIndex = todoData.sourceNoteIndex,
                      sourceNoteIndex < createdNotes.count else {
                    return nil
                }
                return createdNotes[sourceNoteIndex]
            }()

            let todo = TodoItem(
                text: todoData.text,
                sourceText: todoData.sourceText,
                sourceNote: sourceNote,
                sourceRangeLocation: todoData.sourceRangeLocation,
                sourceRangeLength: todoData.sourceRangeLength
            )
            todo.createdAt = todoData.createdAt
            todo.updatedAt = todoData.updatedAt
            todo.isCompleted = todoData.isCompleted
            todo.completedAt = todoData.completedAt
            todo.sourceNoteTitleSnapshot = todoData.sourceNoteTitleSnapshot
            todo.sourceCategoryNameSnapshot = todoData.sourceCategoryNameSnapshot
            todo.isSourceTextAvailable = todoData.isSourceTextAvailable ?? true
            context.insert(todo)
        }

        try context.save()
        return (createdCategories.count, package.notes.count, importedTodos.count)
    }
}

struct NotesExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = fileData
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
