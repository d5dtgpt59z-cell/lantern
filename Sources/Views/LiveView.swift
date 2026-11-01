import SwiftUI

struct LiveControls: View {
    @ObservedObject var live: LiveController
    @ObservedObject var store: ChatStore
    var body: some View {
        HStack(spacing: 8) {
            Button { live.goLive() } label: { Label("Go Live", systemImage: "video.fill") }
                .disabled(live.active || store.generating)
                .help("Talk to Paige with local Qwen, ElevenLabs voice and Anam video.")
            Button { live.end() } label: { Label("End Live", systemImage: "stop.fill") }
                .disabled(!live.active || live.phase == .ending)
                .help("Close the Anam session and stop the microphone.")
            Spacer(minLength: 6)
            if live.active {
                Text(live.clock).monospacedDigit().foregroundStyle(live.secondsRemaining < 30 ? Color.orange : Color.secondary)
                Text("FREE SESSION").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            } else {
                Text("Qwen + ElevenLabs + Anam").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Button { live.showSettings = true } label: { Image(systemName: "gearshape") }
                .help("Live connection settings").accessibilityLabel("Live settings").disabled(live.active)
        }.controlSize(.small).padding(.horizontal, 24).padding(.vertical, 10)
    }
}

struct LivePanel: View {
    @ObservedObject var live: LiveController
    @State private var typed = ""
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle().fill(live.active ? Color.pink : Color.secondary).frame(width: 7, height: 7)
                Text(live.statusTitle).font(.callout.weight(.medium))
                Spacer()
                Button("Back to chat") { live.end(); live.showPanel = false }.buttonStyle(.link)
            }
            ZStack {
                LiveAvatarVideo(bridge: live.avatar)
                if !live.active || live.phase == .preparing || live.phase == .connecting {
                    VStack(spacing: 12) {
                        Image(systemName: "video.badge.waveform").font(.system(size: 36)).foregroundStyle(.pink)
                        Text(live.active ? live.phase.title : "Paige, live.").font(.title2.weight(.semibold))
                        Text(live.active ? "Your Qwen conversation stays on this Mac." : "Press Go Live to connect. Each free session lasts up to three minutes.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
            if let notice = live.notice { Text(notice).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if !live.partial.isEmpty { Text(live.partial).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
            if !live.lastReply.isEmpty {
                Text(live.lastReply).font(.callout).lineLimit(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if live.active {
                HStack {
                    Button(live.microphonePaused ? "Resume mic" : "Pause mic", systemImage: live.microphonePaused ? "mic.slash" : "mic") { live.toggleMicrophone() }
                    Button("Interrupt", systemImage: "hand.raised") { live.interrupt() }
                        .disabled(live.phase != .speaking && live.phase != .thinking)
                    TextField("Or type to Paige…", text: $typed).textFieldStyle(.roundedBorder)
                        .disabled(live.phase != .listening)
                        .onSubmit { submit() }
                    Button("Send") { submit() }.disabled(live.phase != .listening || typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.controlSize(.small)
            }
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }
    private func submit() { let message = typed; typed = ""; live.sendTyped(message) }
}

struct LiveSettingsView: View {
    @ObservedObject var account: LiveAccount
    @Environment(\.dismiss) private var dismiss
    @State private var anamKey = ""
    @State private var elevenKey = ""
    @State private var status: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Live Paige").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            Text("Qwen 3.8 stays on your Mac. ElevenLabs provides her voice; Anam provides live video.")
                .font(.callout).foregroundStyle(.secondary)
            Form {
                Section("Anam · free plan") {
                    SecureField(account.hasAnamKey ? "Anam key saved · enter to replace" : "Anam API key", text: $anamKey)
                    TextField("Paige avatar ID", text: $account.avatarID)
                    Link("Open Anam Lab", destination: URL(string: "https://lab.anam.ai/")!)
                    Text("30 minutes per month. PAIGE ends each session after three minutes. Keep the account on Free; paid upgrades are managed in Anam.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("ElevenLabs voice") {
                    SecureField(account.hasElevenKey ? "ElevenLabs key available · enter to replace" : "ElevenLabs API key", text: $elevenKey)
                    TextField("Voice ID", text: $account.elevenVoiceID)
                    Text("Uses your ElevenLabs allowance. Voice defaults to Sarah; paste another voice ID to change it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            if let status { Text(status).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Label("Saved keys use macOS Keychain", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Save settings") {
                    do {
                        if !anamKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try account.saveAnamKey(anamKey); anamKey = "" }
                        if !elevenKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try account.saveElevenKey(elevenKey); elevenKey = "" }
                        status = "Saved. Press Go Live when Qwen is ready."
                    } catch { status = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 570, height: 580)
    }
}
