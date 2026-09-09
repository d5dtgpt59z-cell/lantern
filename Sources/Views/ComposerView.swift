import SwiftUI
struct ComposerView: View {
    @ObservedObject var store: ChatStore
    @State private var imageStudio = false
    var body: some View {
        VStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 8) {
                if !store.attachments.isEmpty {
                    AttachmentStrip(attachments: store.attachments) { id in store.attachments.removeAll { $0.id == id } }
                }
                ZStack(alignment: .topLeading) {
                    if store.draft.isEmpty { Text("Got a spark? Drop it here…").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                    TextEditor(text: $store.draft).font(.system(size: 14)).scrollContentBackground(.hidden).frame(minHeight: 65, maxHeight: 120).accessibilityLabel("Message Lantern")
                }
                HStack {
                    Button { store.chooseAttachments() } label: { Label("Attach", systemImage: "paperclip") }
                        .buttonStyle(.borderless).disabled(store.generating).help("Attach photos or files")
                    Button { imageStudio = true } label: { Label("Image", systemImage: "paintpalette") }
                        .buttonStyle(.borderless).disabled(store.generating).help("Generate an image on your Mac")

                    Text(store.generating ? store.activity : "⌘ Return to send · Return for a new line").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    if store.generating {
                        Button { store.stop() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(.bordered)
                    } else {
                        Button { store.send() } label: { Label("Let’s go", systemImage: "arrow.up").padding(.horizontal, 5) }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command).disabled(!store.ready || (store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.attachments.isEmpty))
                    }
                }
            }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary, lineWidth: 1))
            Text("Lantern can make mistakes. Start a new conversation when changing topics.").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.sheet(isPresented: $imageStudio) { ImageStudioView(store: store) }
        .dropDestination(for: URL.self) { urls, _ in
            guard !store.generating else { return false }
            store.addAttachments(urls); return true
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 16)
    }
}
