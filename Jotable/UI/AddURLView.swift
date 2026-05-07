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
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismissEnvironment
    @Binding var tempURLData: (String, String)?
    private let editingContext: LinkEditContext?
    var onDismiss: (() -> Void)?

    private enum Field {
        case displayText
        case url
    }

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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? "Edit Link" : "Add Link")
                        .font(.headline)
                    Text("Create a clickable link in the note.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                macField("Text") {
                    TextField("Text to display", text: $displayText)
                        .focused($focusedField, equals: .displayText)
                        .onSubmit(submitIfValid)
                }

                macField("Destination") {
                    TextField("https://example.com", text: $urlString)
                        .focused($focusedField, equals: .url)
                        .autocorrectionDisabled()
                        .onSubmit(submitIfValid)
                } footer: {
                    Text(normalizedURL == nil && !urlString.isEmpty ? "Enter a valid web address." : "Missing schemes are saved as https://")
                        .font(.footnote)
                        .foregroundStyle(normalizedURL == nil && !urlString.isEmpty ? .red : .secondary)
                }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .padding(20)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: dismissView)
                    .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Update Link" : "Add Link", action: submitURL)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .onAppear {
            focusedField = displayText.isEmpty ? .displayText : .url
        }
    }

    private func macField<Content: View, Footer: View>(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
            footer()
        }
    }

    private func macField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        macField(title, content: content) {
            EmptyView()
        }
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

    private func submitIfValid() {
        guard isValid else { return }
        submitURL()
    }

    private func dismissView() {
        if let onDismiss {
            onDismiss()
        } else {
            dismissEnvironment()
        }
    }
}
