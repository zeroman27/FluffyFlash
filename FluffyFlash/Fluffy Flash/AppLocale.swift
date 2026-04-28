//
//  AppLocale.swift
//  Wist
//
//  In-app UI language (overrides String Catalog resolution via SwiftUI environment).
//

import SwiftUI

/// BCP-47 codes matching Localizable.xcstrings locales plus system.
enum WistAppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case es
    case zhHans = "zh-Hans"
    case hi
    case ar
    case fr
    case he

    var id: String { rawValue }

    static var selectable: [WistAppLanguage] {
        [.system, .en, .es, .zhHans, .hi, .ar, .fr, .he]
    }

    /// Locale passed to SwiftUI; `system` uses the OS setting.
    var locale: Locale {
        switch self {
        case .system:
            return Locale.autoupdatingCurrent
        default:
            return Locale(identifier: rawValue)
        }
    }

    /// Resolved with SwiftUI environment (`.environment(\\.locale, …)`); do not use `String(localized:)` here — it ignores that override.
    var menuLabel: LocalizedStringKey {
        switch self {
        case .system:
            return "System default"
        case .en:
            return "English"
        case .es:
            return "Spanish"
        case .zhHans:
            return "Chinese (Simplified)"
        case .hi:
            return "Hindi"
        case .ar:
            return "Arabic"
        case .fr:
            return "French"
        case .he:
            return "Hebrew"
        }
    }
}
