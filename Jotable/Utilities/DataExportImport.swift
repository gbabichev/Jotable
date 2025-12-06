import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExportPackage: Codable {
    let exportedAt: Date
    let categories: [ExportedCategory]
    let notes: [ExportedNote]
}

struct ExportedCategory: Codable {
    let name: String
    let color: String
    let isPrivate: Bool
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

enum DataExportImport {
    static func exportAll(from context: ModelContext) throws -> Data {
        let categoryDescriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.timestamp)]
        )
        let noteDescriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        let categories = try context.fetch(categoryDescriptor)
        let notes = try context.fetch(noteDescriptor)

        let exportedCategories: [ExportedCategory] = categories.enumerated().map { index, category in
            ExportedCategory(
                name: category.name,
                color: category.color,
                isPrivate: category.isPrivate,
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

        let package = ExportPackage(
            exportedAt: Date(),
            categories: exportedCategories,
            notes: exportedNotes
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(package)
    }

    @discardableResult
    static func importPackage(from data: Data, into context: ModelContext) throws -> (importedCategories: Int, importedNotes: Int) {
        let decoder = JSONDecoder()
        let package = try decoder.decode(ExportPackage.self, from: data)

        var createdCategories: [Category] = []
        for categoryData in package.categories {
            let category = Category(
                name: categoryData.name,
                color: categoryData.color,
                sortOrder: categoryData.sortOrder,
                isPrivate: categoryData.isPrivate
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
        }

        try context.save()
        return (createdCategories.count, package.notes.count)
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
