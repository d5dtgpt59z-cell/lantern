import SwiftUI
struct ContentView: View {
    @ObservedObject var store: ChatStore
    @AppStorage("showPet") private var showPet = true
    @State private var pointer = CGPoint.zero
    var body: some View {
        GeometryReader { geometry in
        HStack(spacing: 0) {
            SidebarView(store: store).frame(width: 240, height: geometry.size.height).background(.bar)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.current?.title ?? "New conversation").font(.headline).lineLimit(1)
                        Picker("Model", selection: Binding(get: { store.model }, set: { store.selectModel($0) })) {
                            ForEach(ChatModel.allCases) { model in Text(model.title).tag(model) }
                        }.pickerStyle(.menu).frame(width: 165).disabled(store.generating || store.switchingModel).accessibilityLabel("Chat model")
                    }
                    if store.model == .qwen {
                        Picker("Response mode", selection: $store.thinking) {
                            Text("Quick").tag(false); Text("Think").tag(true)
                        }.pickerStyle(.segmented).frame(width: 130).disabled(store.generating)
                        .help("Think spends more time reasoning. Quick answers directly.")
                    }
                    Spacer()
                    Button { showPet.toggle() } label: { Image(systemName: "pawprint.fill").foregroundStyle(showPet ? Color.orange : Color.secondary) }.buttonStyle(.plain).help(showPet ? "Hide Pip" : "Show Pip").accessibilityLabel(showPet ? "Hide Pip" : "Show Pip")
                    HStack(spacing: 6) { Circle().fill(store.ready ? Color.green : Color.orange).frame(width: 6, height: 6); Text(store.ready ? "ON YOUR MAC" : "WARMING UP").font(.system(size: 10, weight: .semibold, design: .monospaced)) }
                    .padding(8).background(.quaternary, in: Capsule())
                }.padding(.horizontal, 24).padding(.vertical, 16).frame(height: 80)
                Divider()
                if store.current?.messages.isEmpty != false { welcome } else { transcript }
                if let error = store.error {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.circle")
                        Text(error).font(.callout).textSelection(.enabled)
                        Spacer()
                        if store.ready && !store.generating { Button("Retry answer") { store.retryAnswer() } }
                        Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.padding(12).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 24)
                }
                ComposerView(store: store).frame(height: store.attachments.isEmpty ? 168 : 270)
            }.frame(maxWidth: .infinity).frame(height: geometry.size.height)
        }
        }
        .onContinuousHover { phase in if case .active(let point) = phase { pointer = point } }
        .overlay { if showPet { PetCompanion(store: store, visible: $showPet, pointer: pointer) } }
        .sheet(isPresented: $store.showModels) { ModelManagerView(store: store) }
        .sheet(item: $store.approval) { request in ApprovalView(store: store, request: request) }
        .tint(Color(red: 0.85, green: 0.57, blue: 0.22))
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 12)
            HStack(spacing: 14) {
                LanternMark(size: 80).rotationEffect(.degrees(-7))
                VStack(alignment: .leading, spacing: 7) {
                    Text("HELLO, HUMAN").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.orange)
                    Text("Your little bright spot.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkle").font(.system(size: 25)).foregroundStyle(Color.mint.opacity(0.65)).rotationEffect(.degrees(12)).padding(.trailing, 22)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("What are we making?").font(.system(size: 33, weight: .bold, design: .rounded)).tracking(-1)
                Text("A wild idea, a tricky bit of code, or just the right words.\nPull up a chair. Let's figure it out.").font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                SparkCard(title: "Make something", subtitle: "Give an idea some legs", symbol: "sparkles", color: .orange) { store.draft = "Help me turn this idea into something I can build:\n\n" }
                SparkCard(title: "Untangle code", subtitle: "Find the plot twist", symbol: "curlybraces", color: .mint) { store.draft = "Help me understand and improve this code:\n\n" }
                SparkCard(title: "Find the words", subtitle: "Make it sound like you", symbol: "pencil.and.scribble", color: Color(red: 0.73, green: 0.65, blue: 1)) { store.draft = "Help me write this clearly and naturally:\n\n" }
                SparkCard(title: "Think it through", subtitle: "Sort the beautiful mess", symbol: "lightbulb", color: .pink) { store.draft = "Help me think through this and choose a next step:\n\n" }
            }.padding(.top, 7)
            Spacer(minLength: 12)
        }.frame(maxWidth: 608, alignment: .leading).padding(.horizontal, 32).padding(.vertical, 16).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(store.current?.messages ?? []) { message in
                        MessageView(message: message, waiting: store.generating && message.content.isEmpty)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.frame(maxWidth: 780).padding(28).frame(maxWidth: .infinity)
            }
            .onChange(of: store.current?.messages.last?.content) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: store.selected) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}
