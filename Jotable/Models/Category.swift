//
//  Category.swift
//  SimpleNote
//
//  Created by George Babichev on 9/28/25.
//

import SwiftUI
import SwiftData

@Model
final class Category {
    var name: String = ""              // Add default value, remove @Attribute(.unique)
    var color: String = "blue"         // Add default value
    var timestamp: Date = Date()       // Add default value
    var sortOrder: Int = 0             // Add default value
    var isPrivate: Bool = false        // Privacy/lock status
    var isHiddenFromHome: Bool = false // Hide from All Notes without auth
    var isSystemTrash: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Item.category)
    var notes: [Item]? = []            // Make optional with default empty array

    @Relationship(deleteRule: .nullify, inverse: \Item.previousCategory)
    var previouslyCategorizedNotes: [Item]? = []

    init(
        name: String,
        color: String = "blue",
        sortOrder: Int = 0,
        isPrivate: Bool = false,
        isHiddenFromHome: Bool = false,
        isSystemTrash: Bool = false
    ) {
        self.name = name
        self.color = color
        self.timestamp = Date()
        self.sortOrder = sortOrder
        self.isPrivate = isPrivate
        self.isHiddenFromHome = isHiddenFromHome
        self.isSystemTrash = isSystemTrash
    }
}

extension Category {
    static let trashName = "Trash"
}

extension Color {
    static func fromString(_ colorString: String) -> Color {
        switch colorString {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        case "teal": return .teal
        case "mint": return .mint
        case "brown": return .brown
        default: return .blue
        }
    }
}
