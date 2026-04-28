//
//  AppMode.swift
//  Wist
//

import Foundation

enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case windows
    case macos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows: return "Windows"
        case .macos: return "macOS"
        }
    }

    var subtitle: String {
        switch self {
        case .windows: return "UUP → ISO → USB"
        case .macos: return "Installers · IPSW · USB"
        }
    }
}

