import SwiftUI
import AppKit
struct MessageView: View {
    let message: Message
    let waiting: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(message.role == "user" ? "You" : (message.role == "tool" ? (message.tool_name ?? "Tool").replacingOccurrences(of: "_", with: " ") : (message.modelName.map { "Lantern · " + $0 } ?? "Lantern")), systemImage: message.role == "user" ? "person.crop.circle" : "light.beacon.max.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(message.role == "user" ? Color.secondary : Color.orange)
                Spacer()
                if !message.content.isEmpty {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Copy message").accessibilityLabel("Copy message")
                }
            }
            if let attachments = message.attachments, !attachments.isEmpty { AttachmentStrip(attachments: attachments) }
            if waiting { HStack { ProgressView().controlSize(.small); Text("Thinking on your Mac…").font(.callout).foregroundStyle(.secondary) } }
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
