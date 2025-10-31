//
//  CategoryPickerView.swift
//  SimpleNote
//
//  Created by George Babichev on 9/28/25.
//


//
//  CategoryPickerView.swift
//  SimpleNote
//

import SwiftUI
import SwiftData

struct CategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [Category]
    
    @Binding var selectedCategory: Category?
    
    var body: some View {
        NavigationStack {
            List {
                // No Category option
                Button(action: {
                    selectedCategory = nil
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                        Text("No Category")
                        Spacer()
                        if selectedCategory == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Categories
                ForEach(categories.sorted(by: { $0.name < $1.name })) { category in
                    Button(action: {
                        selectedCategory = category
                        dismiss()
                    }) {
                        HStack {
                            Circle()
                                .fill(Color.fromString(category.color))
                                .frame(width: 16, height: 16)
                            Text(category.name)
                            Spacer()
                            if selectedCategory?.id == category.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .navigationTitle("Choose Category")
            //.navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
