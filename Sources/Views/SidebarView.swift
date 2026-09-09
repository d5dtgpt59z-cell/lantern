import SwiftUI
struct SidebarView: View {
    @ObservedObject var store: ChatStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                LanternMark(size: 32)
                Text("Lantern").font(.system(size: 21, weight: .bold, design: .rounded))
            }.padding(.horizontal, 18).padding(.top, 22)
            Button { store.newChat() } label: { Label("New conversation", systemImage: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5) }.buttonStyle(.bordered).padding(.horizontal, 14).disabled(store.generating)
            VStack(alignment: .leading, spacing: 8) {
                Button { store.chooseWorkspace() } label: { Label(store.workspace?.lastPathComponent ?? "Choose a project", systemImage: "folder.badge.gearshape").lineLimit(1) }.buttonStyle(.plain).disabled(store.generating)
                if !store.model.supportsTools {
                    Text("RPMax · text chat. Choose Qwen for photos and project tools.").font(.system(size: 10)).foregroundStyle(.secondary)
                } else if store.workspace != nil {
                    Text("Reads allowed · changes ask first").font(.system(size: 10)).foregroundStyle(.secondary)
                    Button("Turn tools off") { store.workspace = nil; store.newChat() }.font(.caption).buttonStyle(.plain).disabled(store.generating)
                } else { Text("Just chatting · tools are off").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 18)
            List(selection: $store.selected) {
                Section("Conversations") {
                    ForEach(store.conversations) { chat in
                        Label(chat.title, systemImage: "bubble.left").lineLimit(1).tag(chat.id)
                    }
                }
            }.listStyle(.sidebar).disabled(store.generating)
            VStack(alignment: .leading, spacing: 9) {
                Label(store.status, systemImage: store.ready ? "checkmark.shield" : "hourglass").font(.caption).foregroundStyle(.secondary)
                Button("Retry connection") { store.error = nil; Task { await store.connect() } }.font(.caption).buttonStyle(.plain).disabled(store.generating)
                Button("Manage models…") { store.refreshStorage(); store.showModels = true }.font(.caption).buttonStyle(.plain).disabled(store.generating)
                Text("A little light goes a long way.").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(18)
        }
    }
}
