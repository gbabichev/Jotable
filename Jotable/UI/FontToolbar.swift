import SwiftUI

struct FontToolbar: View {
    @Binding var activeColor: RichTextColor
    @Binding var activeHighlighter: HighlighterColor
    @Binding var activeFontSize: FontSize
    @Binding var isBold: Bool
    @Binding var isItalic: Bool
    @Binding var isUnderlined: Bool
    @Binding var isStrikethrough: Bool
    @Binding var presentFormatMenuTrigger: UUID?
    @Binding var resetColorTrigger: UUID?

    var body: some View {
        Menu {
            // MARK: - Colors / Format Section
            Menu {
                ForEach(RichTextColor.allCases, id: \.id) { color in
                    Button {
                        activeColor = color
                    } label: {
                        HStack {
                            Text("\(color.emoji) \(color.id.capitalized)")
                            if activeColor == color {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Text Color", systemImage: "paintpalette")
            }

            Button {
                activeColor = .automatic
                let newTrigger = UUID()
                resetColorTrigger = newTrigger
            } label: {
                Label("Reset Text Color", systemImage: "arrow.uturn.backward")
            }

            Divider()

            // MARK: - Font Size Section
            Menu {
                ForEach(FontSize.allCases, id: \.self) { size in
                    Button {
                        activeFontSize = size
                    } label: {
                        HStack {
                            Text(size.displayName)
                            if activeFontSize == size {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Font Size", systemImage: "textformat.size")
            }

            Divider()

            // MARK: - Highlighter Section
            Menu {
                Button {
                    activeHighlighter = .none
                } label: {
                    HStack {
                        Text("None")
                        if activeHighlighter == .none {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(HighlighterColor.allCases.filter { $0 != .none }, id: \.id) { highlight in
                    Button {
                        activeHighlighter = highlight
                    } label: {
                        HStack {
                            Text("\(highlight.emoji) \(highlight.displayName)")
                            if activeHighlighter == highlight {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Highlighter", systemImage: "highlighter")
            }

            Divider()

            // MARK: - Text Formatting Section
            Toggle("Bold", isOn: $isBold)
            #if os(macOS)
            .keyboardShortcut("b", modifiers: .command)
            #endif

            Toggle("Italic", isOn: $isItalic)
            #if os(macOS)
            .keyboardShortcut("i", modifiers: .command)
            #endif

            Toggle("Underline", isOn: $isUnderlined)

            Toggle("Strikethrough", isOn: $isStrikethrough)
        } label: {
            Image(systemName: "character.circle")
        }
    }
}
