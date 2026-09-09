import SwiftUI
struct ApprovalView: View {
    @ObservedObject var store: ChatStore
    let request: ApprovalRequest
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(request.title, systemImage: "hand.raised.fill").font(.title2.bold()).foregroundStyle(.orange)
            Text("Project: " + (store.workspace?.path ?? "None")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            ScrollView { Text(request.detail).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90)
            if let after = request.after {
                HStack(alignment: .top, spacing: 12) {
                    preview("BEFORE", text: request.before ?? "(New file)")
                    preview("AFTER", text: after)
                }.frame(height: 280)
                Text("Only this file change is approved. Existing content is backed up before replacement.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("This command can change or delete files inside this project. It cannot use the network or read your other home files. It stops after 30 seconds or 64 KB of output. Review the exact command above before approving.").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Not this time") { store.answerApproval(false) }.keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(request.after == nil ? "Approve command" : "Approve this change") { store.answerApproval(true) }.buttonStyle(.borderedProminent).tint(.orange)
            }
        }.padding(24).frame(width: 720).interactiveDismissDisabled()
    }
    private func preview(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) { Text(text).font(.system(size: 11,design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity,alignment: .leading) }.padding(10).background(.quaternary,in: RoundedRectangle(cornerRadius: 8))
        }.frame(maxWidth: .infinity)
    }
}
