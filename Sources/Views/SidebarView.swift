import SwiftUI
struct SidebarView: View {
    @ObservedObject var store: ChatStore
    @State private var pendingDelete: Conversation?
    @State private var showPersona = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaigeBrand(compact: true).padding(.horizontal, 18).padding(.top, 22)
            Button { store.newChat() } label: { Label("New conversation", systemImage: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5) }.buttonStyle(.bordered).padding(.horizontal, 14)
            VStack(alignment: .leading, spacing: 8) {
                Button { store.chooseWorkspace() } label: { Label(store.workspace?.lastPathComponent ?? "Choose a project", systemImage: "folder.badge.gearshape").lineLimit(1) }.buttonStyle(.plain).disabled(store.generating)
                if store.workspace != nil {
                    Text("Reads allowed · changes ask first").font(.system(size: 10)).foregroundStyle(.secondary)
                    Button("Turn tools off") { store.workspace = nil; store.newChat() }.font(.caption).buttonStyle(.plain).disabled(store.generating)
                } else { Text("Choose a folder for project tools").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 18)
            List(selection: $store.selected) {
                Section("Conversations") {
                    ForEach(store.conversations) { chat in
                        HStack {
                            Label(chat.title, systemImage: "bubble.left").lineLimit(1)
                            Spacer()
                            Button { pendingDelete = chat } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).help("Delete conversation").accessibilityLabel("Delete " + chat.title)
                        }.tag(chat.id).contextMenu { Button("Delete conversation…", role: .destructive) { pendingDelete = chat } }
                    }
                }
            }.listStyle(.sidebar).disabled(store.generating)
            VStack(alignment: .leading, spacing: 9) {
                Label(store.status, systemImage: store.ready ? "checkmark.shield" : "hourglass").font(.caption).foregroundStyle(.secondary)
                Button("Retry connection") { store.error = nil; Task { await store.connect() } }.font(.caption).buttonStyle(.plain).disabled(store.generating)
                Button("PAIGE persona…") { showPersona = true }.font(.caption).buttonStyle(.plain)
                Button("Tools & access…") { store.showTools = true }.font(.caption).buttonStyle(.plain)
                Button("Manage models…") { store.refreshStorage(); store.showModels = true }.font(.caption).buttonStyle(.plain).disabled(store.generating)
                Text(Personalization.persona.isEmpty ? "No custom persona imported" : "Hermes persona · imported locally").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(18)
        }
        .sheet(isPresented: $showPersona) { PersonaView() }
        .alert("Delete conversation?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) { if let chat = pendingDelete { store.deleteConversation(chat.id) }; pendingDelete = nil }
        } message: { Text("This permanently deletes this conversation and its saved attachments from PAIGE. This cannot be undone.") }
    }
}
