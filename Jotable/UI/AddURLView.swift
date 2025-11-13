//
//  AddURLView.swift
//  Jotable
//
//  View for adding a URL to the rich text editor
//

import SwiftUI

struct AddURLView: View {
    @State private var displayText: String
    @State private var urlString: String
    @Environment(\.dismiss) private var dismissEnvironment
    @Binding var tempURLData: (String, String)?
    private let editingContext: LinkEditContext?
    var onDismiss: (() -> Void)?

    init(
        tempURLData: Binding<(String, String)?>,
        editingContext: LinkEditContext? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        _tempURLData = tempURLData
        self.editingContext = editingContext
        self.onDismiss = onDismiss
        _displayText = State(initialValue: editingContext?.displayText ?? "")
        _urlString = State(initialValue: editingContext?.urlString ?? "")
    }

    private var normalizedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidate = trimmed
        if candidate.range(of: "://") == nil {
            candidate = "https://\(candidate)"
        }

        guard let url = URL(string: candidate) else { return nil }
        return url
    }

    private var isValid: Bool {
        !displayText.trimmingCharacters(in: .whitespaces).isEmpty &&
        normalizedURL != nil
    }

    private var isEditing: Bool {
        editingContext != nil
    }

    var body: some View {
#if os(macOS)
        macContent
#else
        iosForm
#endif
    }

#if os(macOS)
    private var macContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit Link" : "Add Link")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Display Text")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Link text (e.g., Visit our website)", text: $displayText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("https://example.com", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Text("Include https:// for best results.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button(action: submitURL) {
                    Text(isEditing ? "Update Link" : "Add Link")
                        .frame(minWidth: 100)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(minWidth: 320, maxWidth: 360)
    }
#else
    private var iosForm: some View {
        Form {
            Section(header: Text("Display Text")) {
                TextField("Link text (e.g., Visit our website)", text: $displayText)
            }

            Section(header: Text("URL")) {
                TextField("https://example.com", text: $urlString)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }

            Section {
                Button(action: submitURL) {
                    Text(isEditing ? "Update Link" : "Add Link")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!isValid)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isEditing ? "Edit Link" : "Add Link")
        .navigationBarTitleDisplayMode(.inline)
    }
#endif

    private func submitURL() {
        let display = displayText.trimmingCharacters(in: .whitespaces)
        guard let url = normalizedURL else { return }

        tempURLData = (url.absoluteString, display)
        dismissView()
    }

    private func dismissView() {
        if let onDismiss {
            onDismiss()
        } else {
            dismissEnvironment()
        }
    }
}
