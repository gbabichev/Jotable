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
    @State private var addSpecialSuffix = false
    @State private var mode: PasswordMode = .strong

    var onInsert: (String) -> Void

    private let symbols = "!@#$%^&*()-_=+[]{};:,.<>/?"
    private let separators = ["-", "_", "."]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    sectionHeader("Password Type")
                    
                    #if os(macOS)
                    HStack {
                        Picker("Password Mode", selection: $mode) {
                            ForEach(PasswordMode.allCases) { m in
                                Text(m.title).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    #else
                    Picker("Password Mode", selection: $mode) {
                        ForEach(PasswordMode.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    #endif

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
                            #if os(macOS)
                            HStack {
                                Text("Words: \(simpleWordCount)")
                                Spacer()
                                HStack(spacing: 6) {
                                    Button {
                                        simpleWordCount = max(2, simpleWordCount - 1)
                                    } label: {
                                        Image(systemName: "minus")
                                            .frame(width: 28, height: 28)
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        simpleWordCount = min(6, simpleWordCount + 1)
                                    } label: {
                                        Image(systemName: "plus")
                                            .frame(width: 28, height: 28)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            #else
                            Stepper("Words: \(simpleWordCount)", value: $simpleWordCount, in: 2...6)
                            #endif

                            HStack {
                                Text("Separator")
                                Spacer()
                                #if os(macOS)
                                HStack(spacing: 6) {
                                    ForEach(separators, id: \.self) { sep in
                                        Button(sep) {
                                            simpleSeparator = sep
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(simpleSeparator == sep ? .accentColor : .secondary)
                                        .frame(width: 32, height: 28)
                                    }
                                }
                                #else
                                Picker("", selection: $simpleSeparator) {
                                    ForEach(separators, id: \.self) { sep in
                                        Text(sep)
                                    }
                                }
                                .pickerStyle(.segmented)
                                #endif
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
                            generatedPassword = mode == .strong ? generatePassword() : generateSimplePassword()
                        }
                        .buttonStyle(.bordered)
                        .disabled(mode == .strong ? !(includeUppercase || includeLowercase || includeNumbers || includeSymbols) : false)

                        Spacer()

                        Button("Insert") {
                            let password = generatedPassword.isEmpty ? (mode == .strong ? generatePassword() : generateSimplePassword()) : generatedPassword
                            onInsert(password)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .disabled(mode == .strong ? !(includeUppercase || includeLowercase || includeNumbers || includeSymbols) : false)

#if os(macOS)
                        Button("Copy & Insert") {
                            let password = generatedPassword.isEmpty ? (mode == .strong ? generatePassword() : generateSimplePassword()) : generatedPassword
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(password, forType: .string)
                            onInsert(password)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(mode == .strong ? !(includeUppercase || includeLowercase || includeNumbers || includeSymbols) : false)
#else
                        Button("Copy & Insert") {
                            let password = generatedPassword.isEmpty ? (mode == .strong ? generatePassword() : generateSimplePassword()) : generatedPassword
                            UIPasteboard.general.string = password
                            onInsert(password)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(mode == .strong ? !(includeUppercase || includeLowercase || includeNumbers || includeSymbols) : false)
#endif
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
                generatedPassword = generatePassword()
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
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
