import SwiftUI

struct ListToolbar: View {
    @Binding var insertUncheckedCheckboxTrigger: UUID?
    @Binding var insertBulletTrigger: UUID?
    @Binding var insertNumberingTrigger: UUID?
    @Binding var insertDateTrigger: UUID?
    @Binding var insertTimeTrigger: UUID?
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
                insertBulletTrigger = UUID()
            } label: {
                Label("Bullet Point", systemImage: "minus")
            }

            Button {
                insertNumberingTrigger = UUID()
            } label: {
                Label("Numbering", systemImage: "list.number")
            }

            if includePreAddLinkDivider {
                Divider()
            }

            Button(action: addURLAction) {
                Label("Add URL", systemImage: "link")
            }

            Divider()
            
            Button {
                insertDateTrigger = UUID()
            } label: {
                Label("Insert Date", systemImage: "calendar")
            }

            Button {
                insertTimeTrigger = UUID()
            } label: {
                Label("Insert Time", systemImage: "clock")
            }
        } label: {
            Image(systemName: "list.bullet")
        }
    }
}
