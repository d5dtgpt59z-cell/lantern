import SwiftUI
import AppKit
import UniformTypeIdentifiers
struct MessageView: View {
    let message: Message
    let waiting: Bool
    var waitingText = "Thinking on your Mac…"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(message.role == "user" ? "You" : (message.role == "tool" ? (message.tool_name ?? "Tool").replacingOccurrences(of: "_", with: " ") : (message.modelName.map { "PAIGE · " + $0 } ?? "PAIGE")), systemImage: message.role == "user" ? "person.crop.circle" : "light.beacon.max.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(message.role == "user" ? Color.secondary : Color.orange)
                Spacer()
                if !message.content.isEmpty {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Copy message").accessibilityLabel("Copy message")
                }
            }
            if let attachments = message.attachments, !attachments.isEmpty { AttachmentStrip(attachments: attachments) }
            if message.role == "assistant", let generatedImage = message.generatedImage { GeneratedImageView(record: generatedImage) }
            if waiting { HStack { ProgressView().controlSize(.small); Text(waitingText).font(.callout).foregroundStyle(.secondary) } }
            else if message.role == "tool" {
                DisclosureGroup("Tool result") { Text(message.content).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.font(.caption).padding(12).background(Color.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
            else {
                let chunks = message.content.components(separatedBy: "```")
                ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                    if index % 2 == 1 {
                        let parts = chunk.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                        let code = parts.count > 1 ? String(parts[1]) : chunk
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(parts.count > 1 ? String(parts[0]) : "code").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Copy code") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }.font(.caption).buttonStyle(.plain)
                            }
                            ScrollView(.horizontal) { Text(code).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false) }
                        }.padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Text((try? AttributedString(markdown: chunk, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(chunk)).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct GeneratedImageView: View {
    let record: GeneratedImage
    @State private var saveError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let source = record.url, let image = NSImage(contentsOf: source) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 640, maxHeight: 360, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Generated image: " + record.prompt)
                HStack(spacing: 16) {
                    Button("Save PNG…") { export(source) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([source]) }
                }.font(.caption)
            } else {
                Label("This image is no longer available.", systemImage: "photo.badge.exclamationmark")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
    }
    private func export(_ source: URL) {
        saveError = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "PAIGE-image.png"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try Data(contentsOf: source).write(to: destination, options: .atomic) }
        catch { saveError = "Could not save the image: " + error.localizedDescription }
    }
}
