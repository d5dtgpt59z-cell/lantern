import Foundation
struct SelfDevelopment {
    static var source: URL? {
        guard let path = UserDefaults.standard.string(forKey:"paigeSourceProject") else { return nil }
        let url = URL(fileURLWithPath:path).standardizedFileURL
        guard AgentTools.permittedRoot(url), FileManager.default.fileExists(atPath:url.appendingPathComponent("Package.swift").path), FileManager.default.fileExists(atPath:url.appendingPathComponent("Sources/App/LanternApp.swift").path) else { return nil }
        return url
    }
    static let buildCommand = "mkdir -p work/SelfBuild work/SwiftPMCache work/SwiftPMConfig work/SwiftPMSecurity && /Library/Developer/CommandLineTools/usr/bin/swift build --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk --toolchain /Library/Developer/CommandLineTools/usr --disable-sandbox --disable-automatic-resolution --scratch-path work/SelfBuild --cache-path work/SwiftPMCache --config-path work/SwiftPMConfig --security-path work/SwiftPMSecurity -c release"
    static var schemas: [[String:Any]] { source == nil ? [] : [
        AgentTools.schema("open_paige_source","Switch project tools to PAIGE's configured source checkout, only when the user asks to inspect or modify PAIGE itself. Edits still require approval. Does not modify the installed app.",[:]),
        AgentTools.schema("build_paige","Compile PAIGE's configured source into a separate build folder with a 180-second limit. No signing, installation, restart or publication. Report compiler failures accurately.",[:])
    ] }
}
