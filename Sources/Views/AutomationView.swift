import SwiftUI
import AppKit
struct AutomationView: View {
    @ObservedObject var store: ChatStore
    private var tools: AutomationTools { store.automation }
    var stop: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("Tools & access").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("Choose how independently PAIGE can work in the selected project.").foregroundStyle(.secondary)
            Picker("Project access", selection: $store.accessLevel) {
                ForEach(AccessLevel.allCases) { level in Text(level.title).tag(level) }
            }.pickerStyle(.segmented)
            Text(store.accessLevel.detail).font(.caption).foregroundStyle(store.accessLevel == .fullProject ? .orange : .secondary)
            Divider()
            Text("Browser and Mac actions always ask first. Internet reads contact external sites; chat and screenshot reasoning use your local model.").font(.caption).foregroundStyle(.secondary)
            Toggle("Internet — read URLs and search", isOn: Binding(get: { tools.internet }, set: { tools.internet = $0 }))
            Toggle("Browser — navigate, inspect, click and type", isOn: Binding(get: { tools.browserEnabled }, set: { tools.browserEnabled = $0 }))
            Toggle("Mac control — inspect apps and operate windows", isOn: Binding(get: { tools.computerEnabled }, set: { tools.computerEnabled = $0 }))
            HStack {
                Button("Enable Accessibility…") { ComputerDriver.requestAccessibility() }
                Button("Enable Screen Recording…") { ComputerDriver.requestScreen() }
                Button("Open browser") { tools.browser.show() }
            }
            Button("Choose PAIGE source project…") {
                let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                panel.message = "Select the PAIGE source checkout. Self-edits require approval and a rebuild."
                if panel.runModal() == .OK, let url = panel.url, AgentTools.permittedRoot(url) { UserDefaults.standard.set(url.path,forKey:"paigeSourceProject") }
            }
            Text("Mac control requires macOS permissions. Enter passwords manually. Browser sessions are discarded when PAIGE quits. Each click may send data or change real app state; review its target carefully.").font(.caption).foregroundStyle(.secondary)
            HStack { Text("Activity").font(.headline); Spacer(); Button("Stop all actions",role:.destructive,action:stop).keyboardShortcut(".",modifiers:.command) }
            ScrollView { VStack(alignment:.leading,spacing:8) { ForEach(Array(tools.events.enumerated()),id:\.offset) { _,event in Text(event).font(.system(.caption,design:.monospaced)).frame(maxWidth:.infinity,alignment:.leading) } } }.frame(minHeight:120)
        }.padding(24).frame(width:680,height:490)
    }
}
