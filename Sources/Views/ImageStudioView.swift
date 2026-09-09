import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImageStudioView: View {
    @ObservedObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var negative = ""
    @State private var size = 512
    @State private var model: String?
    @State private var checking = false
    @State private var working = false
    @State private var error: String?
    @State private var output: URL?
    @State private var engine = LocalImageEngine()

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Label("A little imagination", systemImage: "sparkles").font(.title2.bold()).foregroundStyle(.orange)
                Text("Describe an image. Make it on your Mac.").foregroundStyle(.secondary)
                TextEditor(text: $prompt).font(.body).scrollContentBackground(.hidden).padding(10)
                    .frame(height: 145).background(.quaternary, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Image prompt")
                DisclosureGroup("Leave out (optional)") { TextField("Things to avoid in the image", text: $negative).textFieldStyle(.roundedBorder) }
                Picker("Image size", selection: $size) {
                    Text("512 · quick draft").tag(512)
                    Text("768 · more detail").tag(768)
                    Text("1024 · full size").tag(1024)
                }
                if let model {
                    Label(model.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".ckpt", with: ""), systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Open Draw Things and enable its HTTP API at 127.0.0.1:7860. Select a downloaded local model and leave cloud/bridge mode off.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open Draw Things") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Draw Things.app")) }
                    Button(checking ? "Checking…" : "Reconnect") { Task { await connect() } }.disabled(checking)
                }.controlSize(.small)
                if let error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
                Spacer(minLength: 0)
                if working {
                    HStack { ProgressView().controlSize(.small); Text("Drawing on your Mac…").font(.callout) }
                    Text("The first image can take several minutes. Chat resumes when drawing finishes.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button { generate() } label: { Label("Make image", systemImage: "paintpalette.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).disabled(model == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.generating)
                }
            }.frame(width: 320).disabled(working)
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color.orange.opacity(0.06))
                    if let output, let image = NSImage(contentsOf: output) {
                        Image(nsImage: image).resizable().scaledToFit().padding(12)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 44)).foregroundStyle(.orange.opacity(0.6))
                            Text("Your next bright idea").foregroundStyle(.secondary)
                        }
                    }
                }.frame(width: 380, height: 380)
                HStack {
                    if let output {
                        Button("Save PNG…") { export(output) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                        Button("Attach to chat") { store.addAttachments([output]); dismiss() }
                    }
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }.disabled(working)
            }
        }.padding(28).frame(width: 780, height: 540).interactiveDismissDisabled(working)
            .task { await connect() }
    }
    private func connect() async {
        checking = true; defer { checking = false }
        do { model = try await engine.model(); error = nil }
        catch { model = nil; self.error = "Draw Things is not connected: \(error.localizedDescription)" }
    }
    private func generate() {
        guard let model, !store.generating else { return }
        working = true; store.generating = true; store.activity = "Drawing on your Mac…"; error = nil
        Task {
            defer { working = false; store.generating = false; store.activity = "" }
            do { output = try await engine.generate(prompt: prompt, negative: negative, size: size, model: model) }
            catch { self.error = error.localizedDescription + " If the request timed out, check Draw Things before retrying; it may still be rendering." }
        }
    }
    private func export(_ source: URL) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "Lantern.png"
        if panel.runModal() == .OK, let url = panel.url {
            do { try Data(contentsOf: source).write(to: url, options: .atomic) }
            catch { self.error = error.localizedDescription }
        }
    }
}
