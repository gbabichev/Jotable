import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PasswordGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var length: Double = 16
    @State private var includeUppercase = true
    @State private var includeLowercase = true
    @State private var includeNumbers = true
    @State private var includeSymbols = true
    @State private var generatedPassword: String = ""
    @State private var simpleWordCount: Int = 3
    @State private var simpleSeparator: String = "-"
    @State private var simpleCapitalize = true
    @State private var simpleNumberSuffix = true
    @State private var addSpecialSuffix = true
    @State private var mode: PasswordMode = .simple

    var onInsert: (String) -> Void

    private let symbols = "!@#$%^&*()-_=+[]{};:,.<>/?"
    private let separators = ["-", "_", "."]

    var body: some View {
#if os(macOS)
        macBody
#else
        iosBody
#endif
    }

    private var iosBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Password Type")

                    Picker("Password Mode", selection: $mode) {
                        ForEach(PasswordMode.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Divider()

                    if mode == .strong {
                        sectionHeader("Password Length")

                        HStack {
                            Slider(value: $length, in: 4...32, step: 1)
                            Text("\(Int(length))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        sectionHeader("Settings")

                        VStack(alignment: .leading, spacing: 10) {
                            SettingsRow("Uppercase (A-Z)", subtitle: "Password will includes uppercase letters.") {
                                Toggle("", isOn: $includeUppercase)
                                    .toggleStyle(.switch)
                            }
                            SettingsRow("Lowercase (a-z)", subtitle: "Password will includes lowercase letters.") {
                                Toggle("", isOn: $includeLowercase)
                                    .toggleStyle(.switch)
                            }
                            SettingsRow("Numbers (0-9)", subtitle: "Password will include numbers.") {
                                Toggle("", isOn: $includeNumbers)
                                    .toggleStyle(.switch)
                            }
                            SettingsRow("Symbols (!@#...)", subtitle: "Password will include symbols.") {
                                Toggle("", isOn: $includeSymbols)
                                    .toggleStyle(.switch)
                            }
                        }
                    } else {
                        sectionHeader("Settings")
                        VStack(alignment: .leading, spacing: 10) {
                            Stepper("Words: \(simpleWordCount)", value: $simpleWordCount, in: 2...6)

                            HStack {
                                Text("Separator")
                                Spacer()
                                Picker("", selection: $simpleSeparator) {
                                    ForEach(separators, id: \.self) { sep in
                                        Text(sep)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            SettingsRow("Capitalize words", subtitle: "First character of each word will be capitalized.") {
                                Toggle("", isOn: $simpleCapitalize)
                                    .toggleStyle(.switch)
                            }
                            SettingsRow("Add number suffix", subtitle: "There will be a number at the end of the password.") {
                                Toggle("", isOn: $simpleNumberSuffix)
                                    .toggleStyle(.switch)
                            }
                            SettingsRow("Add special character suffix", subtitle: "There will be a random symbol at the end.") {
                                Toggle("", isOn: $addSpecialSuffix)
                                    .toggleStyle(.switch)
                            }
                        }
                    }

                    Divider()

                    sectionHeader("Password")

                    TextField("Password", text: $generatedPassword, prompt: Text("Tap Generate to create a password"))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
#endif

                    HStack {
                        Button("Generate") {
                            refreshPassword()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGeneratorDisabled)

                        Spacer()

                        Button("Insert") {
                            insertGeneratedPassword()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGeneratorDisabled)

                        Button("Copy & Insert") {
                            insertGeneratedPassword(copyToClipboard: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGeneratorDisabled)
                    }
                }
                .padding()
            }
            .navigationTitle("Generate Password")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                refreshPassword()
            }
            .onChange(of: configurationSignature) { _, _ in
                refreshPassword()
            }
        }
    }

#if os(macOS)
    private var macBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    macHeroCard
                    macModePicker

                    if mode == .strong {
                        macStrongConfiguration
                    } else {
                        macSimpleConfiguration
                    }
                }
                .padding(12)
            }
            .frame(width: 500, height: 420)
            .background(Color(nsColor: .windowBackgroundColor))
            .controlSize(.small)
            .font(.callout)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        insertGeneratedPassword(copyToClipboard: true)
                    } label: {
                        Label("Copy & Insert", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isGeneratorDisabled)
                }
            }
            .onAppear {
                refreshPassword()
            }
            .onChange(of: configurationSignature) { _, _ in
                refreshPassword()
            }
        }
    }

    private var macHeroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(mode == .strong ? "Strong Password" : "Memorable Password",
                          systemImage: mode == .strong ? "lock.shield" : "text.badge.checkmark")
                        .font(.headline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                    Text(mode == .strong ? "\(Int(length)) characters, tuned for entropy" : "Readable words with a cleaner default recipe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        let password = resolvedPassword()
                        guard !password.isEmpty else { return }
                        generatedPassword = password
                        copyToClipboard(password)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isGeneratorDisabled)

                    Button {
                        refreshPassword()
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isGeneratorDisabled)
                }
            }

            Text(generatedPassword.isEmpty ? "Choose options to generate a password" : generatedPassword)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(isGeneratorDisabled ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private var macModePicker: some View {
        macCard(
            title: "Password Type",
            subtitle: "Switch between fully random and human-readable output.",
            symbol: "slider.horizontal.3"
        ) {
            HStack(spacing: 6) {
                ForEach(PasswordMode.allCases) { currentMode in
                    Button {
                        mode = currentMode
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(currentMode.title, systemImage: currentMode == .strong ? "lock.fill" : "textformat")
                                .font(.subheadline.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                            Text(currentMode == .strong ? "Random characters" : "Words with separators")
                                .font(.caption2)
                                .foregroundStyle(mode == currentMode ? Color.white.opacity(0.82) : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(mode == currentMode ? Color.accentColor : Color.primary.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var macStrongConfiguration: some View {
        VStack(spacing: 10) {
            macCard(
                title: "Length",
                subtitle: "Dial the tradeoff between usability and brute-force resistance.",
                symbol: "ruler"
            ) {
                HStack(spacing: 10) {
                    Text("\(Int(length))")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .leading)

                    Slider(value: $length, in: 4...32, step: 1)
                }
            }

            macCard(
                title: "Character Sets",
                subtitle: "Choose which alphabets are allowed in the generator pool.",
                symbol: "textformat.abc"
            ) {
                VStack(spacing: 8) {
                    macToggleRow(
                        title: "Uppercase",
                        subtitle: "Include A-Z",
                        symbol: "textformat",
                        isOn: $includeUppercase
                    )
                    macToggleRow(
                        title: "Lowercase",
                        subtitle: "Include a-z",
                        symbol: "character",
                        isOn: $includeLowercase
                    )
                    macToggleRow(
                        title: "Numbers",
                        subtitle: "Include 0-9",
                        symbol: "numbers",
                        isOn: $includeNumbers
                    )
                    macToggleRow(
                        title: "Symbols",
                        subtitle: "Include punctuation and special characters",
                        symbol: "exclamationmark.circle",
                        isOn: $includeSymbols
                    )
                }
            }
        }
    }

    private var macSimpleConfiguration: some View {
        VStack(spacing: 10) {
            macCard(
                title: "Word Recipe",
                subtitle: "Build a phrase that is easier to type without looking obviously weak.",
                symbol: "text.book.closed"
            ) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Words")
                                .font(.subheadline.weight(.semibold))
                            Text("Choose 2 to 6 words")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Button {
                                simpleWordCount = max(2, simpleWordCount - 1)
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.bordered)

                            Text("\(simpleWordCount)")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .frame(minWidth: 22)

                            Button {
                                simpleWordCount = min(6, simpleWordCount + 1)
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Separator")
                            .font(.subheadline.weight(.semibold))

                        HStack(spacing: 6) {
                            ForEach(separators, id: \.self) { separator in
                                Button {
                                    simpleSeparator = separator
                                } label: {
                                    Text(separator == "." ? "Dot" : separator)
                                        .font(.caption.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(simpleSeparator == separator ? Color.accentColor : Color.primary.opacity(0.05))
                                        )
                                        .foregroundStyle(simpleSeparator == separator ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            macCard(
                title: "Finishing Touches",
                subtitle: "Add predictable structure only where it helps memorability.",
                symbol: "sparkles"
            ) {
                VStack(spacing: 8) {
                    macToggleRow(
                        title: "Capitalize Words",
                        subtitle: "Uppercase the first letter of each word",
                        symbol: "textformat.abc",
                        isOn: $simpleCapitalize
                    )
                    macToggleRow(
                        title: "Number Suffix",
                        subtitle: "Append a two-digit number",
                        symbol: "number.square",
                        isOn: $simpleNumberSuffix
                    )
                    macToggleRow(
                        title: "Special Character",
                        subtitle: "Add a symbol to the end",
                        symbol: "sparkles",
                        isOn: $addSpecialSuffix
                    )
                }
            }
        }
    }

    private func macCard<Content: View>(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func macToggleRow(
        title: String,
        subtitle: String,
        symbol: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
#endif

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    private var isGeneratorDisabled: Bool {
        mode == .strong && !(includeUppercase || includeLowercase || includeNumbers || includeSymbols)
    }

    private var configurationSignature: String {
        [
            mode.rawValue,
            String(Int(length)),
            includeUppercase.description,
            includeLowercase.description,
            includeNumbers.description,
            includeSymbols.description,
            String(simpleWordCount),
            simpleSeparator,
            simpleCapitalize.description,
            simpleNumberSuffix.description,
            addSpecialSuffix.description
        ].joined(separator: "|")
    }

    private func refreshPassword() {
        generatedPassword = activeGenerator()
    }

    private func activeGenerator() -> String {
        mode == .strong ? generatePassword() : generateSimplePassword()
    }

    private func resolvedPassword() -> String {
        generatedPassword.isEmpty ? activeGenerator() : generatedPassword
    }

    private func insertGeneratedPassword(copyToClipboard shouldCopyToClipboard: Bool = false) {
        let password = resolvedPassword()
        guard !password.isEmpty else { return }

        generatedPassword = password

        if shouldCopyToClipboard {
            copyToClipboard(password)
        }

        onInsert(password)
        dismiss()
    }

    private func copyToClipboard(_ password: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(password, forType: .string)
#else
        UIPasteboard.general.string = password
#endif
    }

    private func generatePassword() -> String {
        var pool = ""
        if includeUppercase { pool.append("ABCDEFGHIJKLMNOPQRSTUVWXYZ") }
        if includeLowercase { pool.append("abcdefghijklmnopqrstuvwxyz") }
        if includeNumbers { pool.append("0123456789") }
        if includeSymbols { pool.append(symbols) }

        guard !pool.isEmpty else { return "" }

        var password = ""
        for _ in 0..<Int(length) {
            if let char = pool.randomElement() {
                password.append(char)
            }
        }
        return password
    }

    private func generateSimplePassword() -> String {
        guard !PasswordGeneratorView.wordPool.isEmpty else { return "" }

        var words: [String] = []
        for _ in 0..<simpleWordCount {
            if let word = PasswordGeneratorView.wordPool.randomElement() {
                words.append(simpleCapitalize ? word.capitalized : word.lowercased())
            }
        }

        var password = words.joined(separator: simpleSeparator)
        if simpleNumberSuffix {
            let number = Int.random(in: 10...99)
            password.append("\(simpleSeparator)\(number)")
        }
        if addSpecialSuffix, let special = symbols.randomElement() {
            password.append(special)
        }
        return password
    }

    private enum PasswordMode: String, CaseIterable, Identifiable {
        case strong
        case simple

        var id: String { rawValue }

        var title: String {
            switch self {
            case .strong: return "Strong"
            case .simple: return "Simple"
            }
        }
    }

    private static let wordPool: [String] = [
        "apple","river","stone","quiet","light","cloud","forest","silver","ocean","mountain",
        "breeze","shadow","dawn","ember","hazel","maple","copper","iron","spruce","cedar",
        "comet","orbit","nova","lumen","echo","fable","harbor","meadow","harvest","canyon",
        "cinder","drift","flint","glade","harp","ivory","jade","kelp","lagoon",
        "marble","nectar","onyx","pearl","quill","raven","sable","thistle","umber","violet",
        "willow","yonder","zephyr","aurora","bluff","cove","dune","elm","fir",
        "grove","isle","knoll","ledge","mocha","noble","opal","pine","quartz",
        "reef","sage","tundra","valley","wren","yarrow","zenith","amber","bison","chalk",
        "delta","frost","glisten","ink","juniper","keystone","linen","merit",
        "nomad","olive","plume","quasar","ridge","summit","tide","upland","vista","whisper",
        "yukon","azure","bramble","cascade","flare","garnet","heather","indigo","jasper",
        "kepler","lilac","moss","nebula","orchid","prairie","quince","robin","solace","thunder",
        "ursa","verve","wander","xenon","yodel","zinnia"
    ]
}
