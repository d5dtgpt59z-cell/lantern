import SwiftUI
import AppKit
struct ModelManagerView: View {
    @ObservedObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var removing: ChatModel?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                LanternMark(size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.installed.isEmpty ? "A little setup. A lot of possibility." : "Make room for bright ideas.").font(.title2.bold())
                    Text("Download once. Chat offline.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Label("\(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB memory", systemImage: "memorychip")
                Spacer()
                Label("\(Int(store.freeGB)) GB available", systemImage: "internaldrive")
            }.font(.callout).foregroundStyle(.secondary)
            if !store.supportedHardware { Text("This release is designed for Apple Silicon Macs with 16 GB or more.").foregroundStyle(.orange) }
            ForEach(ChatModel.allCases) { model in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.subtitle).font(.headline)
                            Text(model.summary).font(.caption).foregroundStyle(.secondary)
                            Text("Approximately \(model.downloadGB, specifier: "%.1f") GB download").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.downloading == model {
                            Button("Pause") { store.pauseDownload() }
                        } else if store.installed.contains(model.ollamaName) {
                            Button(store.model == model ? "Selected" : "Use model") { store.selectModel(model) }.disabled(store.model == model || store.switchingModel || store.generating || store.downloading != nil)
                            Button { removing = model } label: { Image(systemName: "trash") }.help("Remove downloaded model").disabled(store.generating || store.downloading != nil)
                        } else {
                            Button("Download / Resume") { store.download(model) }.disabled(store.downloading != nil || store.generating || !store.supportedHardware)
                        }
                    }
                    if store.downloading == model {
                        if let progress = store.downloadProgress { ProgressView(value: progress); Text("\(Int(progress * 100))% of current file").font(.caption) }
                        else { ProgressView().controlSize(.small) }
                        Text(store.downloadStatus).font(.caption).lineLimit(2)
                    }
                }.padding(16).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            }
            if let error = store.modelError { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            else if store.downloading == nil && !store.downloadStatus.isEmpty { Text(store.downloadStatus).font(.caption).foregroundStyle(.secondary) }
            Text("Downloads need internet. Chats and attachments stay on your Mac. Existing Ollama downloads are reused when available; removing a shared model also removes it from Ollama.").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Check for updates") { Task { await store.checkUpdate() } }.disabled(store.checkingUpdate)
                Link("Releases ↗", destination: URL(string: "https://github.com/d5dtgpt59z-cell/lantern/releases")!)
                Spacer()
                Text("Free · MIT licensed").font(.caption).foregroundStyle(.secondary)
            }
            if !store.updateStatus.isEmpty { Text(store.updateStatus).font(.caption).foregroundStyle(.secondary) }
        }.padding(32).frame(width: 660).fixedSize(horizontal: false, vertical: true)
        .task { store.refreshStorage() }
        .alert("Remove downloaded model?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Cancel", role: .cancel) { removing = nil }
            Button("Remove", role: .destructive) { if let model = removing { Task { await store.removeModel(model) } }; removing = nil }
        } message: { Text("Your conversations stay saved. The model can be downloaded again. If shared with Ollama, it will also be removed there.") }
    }
}
