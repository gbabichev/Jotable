import SwiftUI

struct ListToolbar: View {
    @Binding var insertUncheckedCheckboxTrigger: UUID?
    @Binding var insertDashTrigger: UUID?
    @Binding var insertBulletTrigger: UUID?
    @Binding var insertNumberingTrigger: UUID?
    @Binding var dateInsertionRequest: DateInsertionRequest?
    @Binding var dateInsertionFormat: DateInsertionFormat
    @Binding var timeInsertionRequest: TimeInsertionRequest?
    @Binding var timeInsertionFormat: TimeInsertionFormat
    @Binding var showingAddURLDialog: Bool
    @Binding var tempURLData: (String, String)?

    var body: some View {
#if os(macOS)
        HStack(spacing: 8) {
            toolbarMenu(includePreAddLinkDivider: false) {
                showingAddURLDialog = true
            }
            .sheet(isPresented: $showingAddURLDialog) {
                NavigationStack {
                    AddURLView(
                        tempURLData: $tempURLData,
                        editingContext: nil,
                        onDismiss: {
                            showingAddURLDialog = false
                        }
                    )
                    .frame(width: 320, height: 260)
                    .padding()
                }
                .frame(width: 360, height: 320)
            }
        }
#else
        toolbarMenu(includePreAddLinkDivider: true) {
            withAnimation(.easeInOut) {
                showingAddURLDialog = true
            }
        }
#endif
    }

    @ViewBuilder
    private func toolbarMenu(includePreAddLinkDivider: Bool,
                             addURLAction: @escaping () -> Void) -> some View {
        Menu {
            Button {
                insertUncheckedCheckboxTrigger = UUID()
            } label: {
                Label("Checkbox", systemImage: "square")
            }

            Button {
                insertDashTrigger = UUID()
            } label: {
                Label("Insert Dash", systemImage: "minus")
            }

            Button {
                insertBulletTrigger = UUID()
            } label: {
                Label("Insert Bullet", systemImage: "circle.fill")
            }

            Button {
                insertNumberingTrigger = UUID()
            } label: {
                Label("Numbering", systemImage: "list.number")
            }

            if includePreAddLinkDivider {
                Divider()
            }

            Divider()
            
            Button(action: addURLAction) {
                Label("Add Link", systemImage: "link")
            }

            Divider()
            
            Menu {
                let currentDate = Date()
                ForEach(DateInsertionFormat.allCases) { format in
                    Button {
                        dateInsertionFormat = format
                        dateInsertionRequest = DateInsertionRequest(format: format)
                    } label: {
                        Text(format.formattedDate(from: currentDate))
                    }
                }
            } label: {
                Label("Insert Date", systemImage: "calendar")
            }

            Menu {
                let currentTime = Date()
                ForEach(TimeInsertionFormat.allCases) { format in
                    Button {
                        timeInsertionFormat = format
                        timeInsertionRequest = TimeInsertionRequest(format: format)
                    } label: {
                        Text(format.formattedTime(from: currentTime))
                    }
                }
            } label: {
                Label("Insert Time", systemImage: "clock")
            }
        } label: {
            Image(systemName: "list.bullet")
        }
    }
}
