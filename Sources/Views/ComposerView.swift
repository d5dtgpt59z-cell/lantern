import SwiftUI
struct ComposerView: View {
    @ObservedObject var store: ChatStore
    var body: some View {
        VStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 8) {
                if !store.attachments.isEmpty {
                    AttachmentStrip(attachments: store.attachments) { id in store.attachments.removeAll { $0.id == id } }
                }
                ZStack(alignment: .topLeading) {
                    if store.draft.isEmpty { Text(store.imageMode ? "Describe an image…" : "Message PAIGE…").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                    TextEditor(text: $store.draft).font(.system(size: 14)).scrollContentBackground(.hidden).frame(minHeight: 65, maxHeight: 120).accessibilityLabel(store.imageMode ? "Image prompt" : "Message PAIGE")
                }
                HStack {
                    Button { store.chooseAttachments() } label: { Label("Attach", systemImage: "paperclip") }
                        .buttonStyle(.borderless).disabled(store.generating).help("Attach text, code, or PDFs with selectable text")
                    Button { store.imageMode.toggle() } label: { Label("Image", systemImage: "paintpalette") }
                        .buttonStyle(.borderless).foregroundStyle(store.imageMode ? Color.orange : Color.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(store.imageMode ? Color.orange.opacity(0.14) : Color.clear, in: Capsule())
                        .disabled(store.generating).help("Generate an image on your Mac")
                        .accessibilityValue(store.imageMode ? "Selected" : "Off")

                    Text(store.generating ? store.activity : "⌘ Return to send · Return for a new line").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    if store.generating {
                        Button { store.stop() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(.bordered)
                    } else {
                        Button { store.send() } label: { Label(store.imageMode ? "Make image" : "Send", systemImage: "arrow.up").padding(.horizontal, 5) }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command).disabled(!store.canSend)
                    }
                }
            }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary, lineWidth: 1))
            Text("PAIGE can make mistakes. Start a new conversation when changing topics.").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !store.generating else { return false }
            store.addAttachments(urls); return true
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 16)
    }
}
