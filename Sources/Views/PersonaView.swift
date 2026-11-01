import SwiftUI
import AppKit
struct PersonaView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = Personalization.persona
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PAIGE’s persona").font(.title2.bold())
            Text("A local copy of her identity and voice. Applies to new replies in both models. Hermes tools, sessions, and memories are not imported.").foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 320)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack {
                Button("Import SOUL.md…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = false
                    panel.message = "Choose your Hermes SOUL.md persona. It stays on this Mac."
                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            let data = try Data(contentsOf: url)
                            guard data.count <= 64_000, let value = String(data: data, encoding: .utf8) else { throw Attachment.failure("Choose a UTF-8 persona file smaller than 64 KB.") }
                            text = value
                        } catch { self.error = error.localizedDescription }
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save persona") {
                    do {
                        guard text.utf8.count <= 64_000 else { throw Attachment.failure("Keep the persona under 64 KB.") }
                        try text.write(to: Personalization.directory.appendingPathComponent("persona.md"), atomically: true, encoding: .utf8)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 650)
    }
}
