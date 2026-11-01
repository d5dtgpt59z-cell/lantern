import Foundation

enum AccessLevel: String, CaseIterable, Identifiable {
    case readOnly, askFirst, fullProject
    var id: String { rawValue }
    var title: String {
        switch self { case .readOnly: "Read Only"; case .askFirst: "Ask First"; case .fullProject: "Full Project" }
    }
    var detail: String {
        switch self {
        case .readOnly: "PAIGE can inspect the selected project but cannot edit files or run commands."
        case .askFirst: "PAIGE asks before every file change and project command."
        case .fullProject: "PAIGE can edit and run sandboxed commands inside the selected project without asking each time."
        }
    }
}
