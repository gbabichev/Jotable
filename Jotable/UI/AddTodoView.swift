//
//  AddTodoView.swift
//  Jotable
//

import SwiftUI

struct AddTodoView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTodoFocused: Bool

    @State private var todoText = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var priority: TodoPriority = .normal

    let onAdd: (StandaloneTodoDraft) -> Void

    private var trimmedTodoText: String {
        todoText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Text("New Todo")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button("Add") {
                    addTodo()
                }
                .disabled(trimmedTodoText.isEmpty)
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("Todo")
                    .font(.headline)
                    .foregroundColor(.primary)

                TextField("What needs to be done?", text: $todoText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isTodoFocused)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit(addTodo)
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                Picker("Priority", selection: $priority) {
                    ForEach(TodoPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Due Date", isOn: $hasDueDate)

                if hasDueDate {
                    DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 20)
        }
        .frame(minWidth: 360, minHeight: 300)
        .onAppear {
            isTodoFocused = true
        }
    }

    private func addTodo() {
        guard !trimmedTodoText.isEmpty else { return }
        onAdd(
            StandaloneTodoDraft(
                text: trimmedTodoText,
                dueDate: hasDueDate ? dueDate : nil,
                priority: priority
            )
        )
        dismiss()
    }
}
