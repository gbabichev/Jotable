//
//  AddCategoryView.swift
//  SimpleNote
//
//  Created by George Babichev on 9/28/25.
//

import SwiftUI
import SwiftData

struct AddCategoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var categoryName = ""
    @State private var selectedColor = "blue"
    
    // Optional category for editing
    let categoryToEdit: Category?
    
    private let availableColors = ["blue", "green", "orange", "red", "purple", "pink", "yellow", "gray"]
    
    // Computed properties for UI text
    private var navigationTitle: String {
        categoryToEdit == nil ? "New Category" : "Edit Category"
    }
    
    private var actionButtonTitle: String {
        categoryToEdit == nil ? "Add" : "Save"
    }
    
    init(categoryToEdit: Category? = nil) {
        self.categoryToEdit = categoryToEdit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Text(navigationTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(actionButtonTitle) {
                    if categoryToEdit != nil {
                        saveCategory()
                    } else {
                        addCategory()
                    }
                }
                .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Category Name Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category Name")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("Enter category name", text: $categoryName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                            .textInputAutocapitalization(.words)
#endif
                    }
                    
                    // Color Selection Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 20) {
                            ForEach(availableColors, id: \.self) { color in
                                Button(action: { selectedColor = color }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.fromString(color))
                                            .frame(width: 50, height: 50)
                                        
                                        // Selection indicator
                                        if selectedColor == color {
                                            Circle()
                                                .stroke(Color.primary, lineWidth: 3)
                                                .frame(width: 56, height: 56)
                                            
                                            // Checkmark for better visibility
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.white)
                                                .font(.title2)
                                                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                                        }
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .accessibilityLabel("\(color.capitalized) color")
                                .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            // Pre-populate fields when editing
            if let categoryToEdit = categoryToEdit {
                categoryName = categoryToEdit.name
                selectedColor = categoryToEdit.color
            }
        }
    }
    
    private func addCategory() {
        let trimmedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // Get the next available sort order
        let existingCategories = try? modelContext.fetch(FetchDescriptor<Category>())
        let nextSortOrder = (existingCategories?.map(\.sortOrder).max() ?? -1) + 1
        
        let newCategory = Category(name: trimmedName, color: selectedColor, sortOrder: nextSortOrder)
        modelContext.insert(newCategory)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save category: \(error)")
        }
    }
    
    private func saveCategory() {
        let trimmedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let categoryToEdit = categoryToEdit else { return }
        
        categoryToEdit.name = trimmedName
        categoryToEdit.color = selectedColor
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to update category: \(error)")
        }
    }
}
