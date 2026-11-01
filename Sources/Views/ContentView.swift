import SwiftUI
struct ContentView: View {
    @ObservedObject var store: ChatStore
    @StateObject private var live = LiveController()
    var body: some View {
        GeometryReader { geometry in
        HStack(spacing: 0) {
            SidebarView(store: store).frame(width: 240, height: geometry.size.height).background(.bar)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.current?.title ?? "New conversation").font(.headline).lineLimit(1)
                        Label(store.model.subtitle, systemImage: "cpu").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Response mode", selection: $store.thinking) {
                        Text("Quick").tag(false); Text("Think").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 130).disabled(store.generating)
                    .help("Think spends more time reasoning. Quick answers directly.")
                    Spacer()
                    if store.generating { Label(store.agentPhase.label, systemImage: store.agentPhase.symbol).font(.caption).foregroundStyle(.orange) }
                    HStack(spacing: 6) { Circle().fill(store.ready ? Color.green : Color.orange).frame(width: 6, height: 6); Text(store.ready ? "ON YOUR MAC" : "WARMING UP").font(.system(size: 10, weight: .semibold, design: .monospaced)) }
                    .padding(8).background(.quaternary, in: Capsule())
                }.padding(.horizontal, 24).padding(.vertical, 16).frame(height: 80)
                Divider()
                LiveControls(live: live, store: store)
                Divider()
                if live.showPanel { LivePanel(live: live) }
                else if store.current?.messages.isEmpty != false { welcome } else { transcript }
                if let error = store.error {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.circle")
                        Text(error).font(.callout).textSelection(.enabled)
                        Spacer()
                        if !store.generating { Button("Retry answer") { store.retryAnswer() } }
                        Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.padding(12).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 24)
                }
                if !live.showPanel { ComposerView(store: store).frame(height: store.attachments.isEmpty ? 168 : 270) }
            }.frame(maxWidth: .infinity).frame(height: geometry.size.height).background { PaigeBackground() }
        }
        }
        .sheet(isPresented: $store.showTools) { AutomationView(store: store, stop: store.stop) }
        .sheet(isPresented: $store.showModels) { ModelManagerView(store: store) }
        .sheet(item: $store.approval) { request in ApprovalView(store: store, request: request) }
        .sheet(isPresented: $live.showSettings) { LiveSettingsView(account: live.account) }
        .onAppear { live.bind(to: store) }
        .onDisappear { live.end() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if let window = notification.object as? NSWindow, window.title == "PAIGE" { live.end() }
        }
        .onChange(of: store.selected) { _, _ in live.end() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in live.end() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willHideNotification)) { _ in live.end() }
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.85, green: 0.57, blue: 0.22))
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 12)
            PaigeBrand()
            VStack(alignment: .leading, spacing: 10) {
                Text("A clear space to think.").font(.system(size: 33, weight: .bold, design: .default)).tracking(-1)
                Text("Write, explore documents, and work through code.\nYour downloaded model runs locally.").font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                SparkCard(title: "Plan a project", subtitle: "Turn requirements into next steps", symbol: "sparkles", color: .orange) { store.draft = "Help me turn this idea into something I can build:\n\n" }
                SparkCard(title: "Understand code", subtitle: "Explain, review, and improve", symbol: "curlybraces", color: .gray) { store.draft = "Help me understand and improve this code:\n\n" }
                SparkCard(title: "Draft and revise", subtitle: "Find the clearest expression", symbol: "pencil.and.scribble", color: .gray) { store.draft = "Help me write this clearly and naturally:\n\n" }
                SparkCard(title: "Make an image", subtitle: "Describe it. Draw it on your Mac.", symbol: "paintpalette", color: .orange) { store.imageMode = true; store.draft = "" }
            }.padding(.top, 7)
            Spacer(minLength: 12)
        }.frame(maxWidth: 608, alignment: .leading).padding(.horizontal, 32).padding(.vertical, 16).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(store.current?.messages ?? []) { message in
                        MessageView(message: message, waiting: store.generating && message.id == store.current?.messages.last?.id && message.content.isEmpty && message.tool_calls == nil && message.generatedImage == nil, waitingText: store.activity.isEmpty ? "Thinking on your Mac…" : store.activity)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.frame(maxWidth: 780).padding(28).frame(maxWidth: .infinity)
            }
            .onChange(of: store.current?.messages.last?.content) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: store.current?.messages.last?.id) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: store.selected) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}
