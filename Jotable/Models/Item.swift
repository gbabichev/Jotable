//  Item.swift
//  SimpleNote
//
//  Updated Item model with category relationship and creation date
//

import SwiftUI
import SwiftData

@Model
final class Item {
    var id: UUID = UUID()
    var timestamp: Date = Date()      // Add default value
    var createdAt: Date = Date()      // Add default value
    var title: String = ""            // Add default value
    var content: String = ""          // Plain text fallback

    // Store attributed text as Data for rich formatting (includes checkboxes)
    @Attribute(.externalStorage) var attributedContent: Data?

    // Category relationship - already optional, good!
    var category: Category?

    init(timestamp: Date = Date(), title: String = "", content: String = "") {
        let now = Date()
        self.id = UUID()
        self.timestamp = timestamp
        self.createdAt = now
        self.title = title
        self.content = content
        self.attributedContent = nil
        self.category = nil
    }
}
