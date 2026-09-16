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
    let sortOrder: Int?
    let dueDate: Date?
    let priorityRawValue: Int?
    let sourceNoteIndex: Int?
    let sourceNoteTitleSnapshot: String
    let sourceCategoryNameSnapshot: String
    let sourceRangeLocation: Int
    let sourceRangeLength: Int
    let isSourceTextAvailable: Bool?
}

enum DataExportImport {
    static func exportAll(from context: ModelContext) throws -> Data {
        let documentContext = JotableApp.sharedDocumentContainer.mainContext
        let categoryDescriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.timestamp)]
        )
        let noteDescriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let documentDescriptor = FetchDescriptor<NoteDocument>()
        let todoDescriptor = FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )

        let categories = try context.fetch(categoryDescriptor)
            .filter { !$0.isSystemTrash }
        let notes = try context.fetch(noteDescriptor)
            .filter { !$0.isInTrash }
        let documents = try documentContext.fetch(documentDescriptor)
        let todos = try context.fetch(todoDescriptor)
        let documentsByNoteID = Dictionary(
            documents.map { ($0.noteID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

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
            let document = documentsByNoteID[note.id.uuidString]
            let attributedBase64 = (document?.attributedContent ?? note.attributedContent)?.base64EncodedString()

            return ExportedNote(
                title: note.title,
                content: document?.plainText ?? note.content,
                createdAt: note.createdAt,
                timestamp: document?.updatedAt ?? note.timestamp,
                categoryIndex: categoryIndex,
                attributedContentBase64: attributedBase64
            )
        }

        let noteIndexMap: [String: Int] = Dictionary(uniqueKeysWithValues: notes.enumerated().map { index, note in
            (note.id.uuidString, index)
        })

        let exportedTodos: [ExportedTodo] = todos.map { todo in
            let sourceNoteIndex = noteIndexMap[todo.sourceNoteID]

            return ExportedTodo(
                text: todo.text,
                sourceText: todo.sourceText,
                createdAt: todo.createdAt,
                updatedAt: todo.updatedAt,
                isCompleted: todo.isCompleted,
                completedAt: todo.completedAt,
                sortOrder: todo.sortOrder,
                dueDate: todo.dueDate,
                priorityRawValue: todo.priorityRawValue,
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
        let documentContext = JotableApp.sharedDocumentContainer.mainContext
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
            let document = NoteDocument(
                noteID: note.id.uuidString,
                plainText: noteData.content,
                attributedContent: note.attributedContent,
                updatedAt: noteData.timestamp
            )
            documentContext.insert(document)
            createdNotes.append(note)
        }

        let importedTodos = package.todos ?? []
        for (index, todoData) in importedTodos.enumerated() {
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
            todo.sortOrder = todoData.sortOrder ?? (importedTodos.count - index)
            todo.dueDate = todoData.dueDate.map { Calendar.current.startOfDay(for: $0) }
            todo.priorityRawValue = todoData.priorityRawValue ?? TodoPriority.normal.rawValue
            todo.sourceNoteTitleSnapshot = todoData.sourceNoteTitleSnapshot
            todo.sourceCategoryNameSnapshot = todoData.sourceCategoryNameSnapshot
            todo.isSourceTextAvailable = todoData.isSourceTextAvailable ?? true
            context.insert(todo)
        }

        try context.save()
        try documentContext.save()
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
