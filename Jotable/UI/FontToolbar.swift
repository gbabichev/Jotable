import SwiftUI

struct FontToolbar: View {
    @Binding var activeColor: RichTextColor
    @Binding var activeHighlighter: HighlighterColor
    @Binding var activeFontSize: FontSize
    @Binding var isBold: Bool
    @Binding var isUnderlined: Bool
    @Binding var isStrikethrough: Bool
    @Binding var presentFormatMenuTrigger: UUID?

    var body: some View {
        Menu {
            // MARK: - Colors / Format Section
            #if os(iOS)
            Button {
                DispatchQueue.main.async {
                    presentFormatMenuTrigger = UUID()
                }
            } label: {
                Label("Format & Color", systemImage: "textformat")
            }

            Divider()
            #elseif os(macOS)
            Button {
                presentFormatMenuTrigger = UUID()
            } label: {
                Label("Show Format Panel", systemImage: "paintpalette")
            }

            Divider()
            #endif

            Button {
                activeColor = .red
            } label: {
                Label("Text Color: Red", systemImage: "circle.fill")
                    .foregroundStyle(Color.red)
            }

            Button {
                activeColor = .automatic
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
            Button {
                isBold.toggle()
            } label: {
                HStack {
                    Image(systemName: isBold ? "checkmark" : "bold")
                    Text("Bold")
                }
            }

            Button {
                isUnderlined.toggle()
            } label: {
                HStack {
                    Image(systemName: isUnderlined ? "checkmark" : "underline")
                    Text("Underline")
                }
            }

            Button {
                isStrikethrough.toggle()
            } label: {
                HStack {
                    Image(systemName: isStrikethrough ? "checkmark" : "strikethrough")
                    Text("Strikethrough")
                }
            }
        } label: {
            Image(systemName: "character.circle")
        }
    }
}
