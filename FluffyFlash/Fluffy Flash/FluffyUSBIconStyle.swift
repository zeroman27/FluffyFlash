//
//  FluffyUSBIconStyle.swift
//  Fluffy Flash
//
//  User-selectable artwork for the USB drive icon shown on the drive list
//  (Home + Library). Persisted via `@AppStorage("fluffy.usbIconStyle")`.
//

import SwiftUI

/// Visual styles for the USB drive icon. The raw value is stored in
/// `UserDefaults`, so renaming a case is a breaking change.
enum FluffyUSBIconStyle: String, CaseIterable, Identifiable, Sendable {
    case original
    case c4
    case chest
    case loot
    case radiation
    case robot
    case shield
    case bear
    case unicorn
    case black
    case white
    case cyber
    case premiumBlack
    case premiumOrange
    case cat
    case fox
    case panda
    case rabbit

    static let defaultStyle: FluffyUSBIconStyle = .original
    static let appStorageKey = "fluffy.usbIconStyle"

    var id: String { rawValue }

    /// Name of the image asset in `Assets.xcassets`.
    var assetName: String {
        switch self {
        case .original: return "FluffyUSBDriveOriginal"
        case .c4: return "FluffyUSBDriveC4"
        case .chest: return "FluffyUSBDriveChest"
        case .loot: return "FluffyUSBDriveLoot"
        case .radiation: return "FluffyUSBDriveRadiation"
        case .robot: return "FluffyUSBDriveRobot"
        case .shield: return "FluffyUSBDriveShield"
        case .bear: return "FluffyUSBDriveBear"
        case .unicorn: return "FluffyUSBDriveUnicorn"
        case .black: return "FluffyUSBDriveBlack"
        case .white: return "FluffyUSBDriveWhite"
        case .cyber: return "FluffyUSBDriveCyber"
        case .premiumBlack: return "FluffyUSBDrivePremiumBlack"
        case .premiumOrange: return "FluffyUSBDrivePremiumOrange"
        case .cat: return "FluffyUSBDriveCat"
        case .fox: return "FluffyUSBDriveFox"
        case .panda: return "FluffyUSBDrivePanda"
        case .rabbit: return "FluffyUSBDriveRabbit"
        }
    }

    /// Short user-facing label.
    var displayName: String {
        switch self {
        case .original: return String(localized: "Original")
        case .c4: return String(localized: "C4")
        case .chest: return String(localized: "Chest")
        case .loot: return String(localized: "Loot")
        case .radiation: return String(localized: "Radiation")
        case .robot: return String(localized: "Robot")
        case .shield: return String(localized: "Shield")
        case .bear: return String(localized: "Bear")
        case .unicorn: return String(localized: "Unicorn")
        case .black: return String(localized: "Black")
        case .white: return String(localized: "White")
        case .cyber: return String(localized: "Cyber")
        case .premiumBlack: return String(localized: "Premium Black")
        case .premiumOrange: return String(localized: "Premium Orange")
        case .cat: return String(localized: "Cat")
        case .fox: return String(localized: "Fox")
        case .panda: return String(localized: "Panda")
        case .rabbit: return String(localized: "Rabbit")
        }
    }

    /// Parses a raw value from `@AppStorage`, falling back to `.defaultStyle`
    /// when the value is missing or unknown.
    static func resolve(rawValue: String?) -> FluffyUSBIconStyle {
        guard let rawValue,
              let style = FluffyUSBIconStyle(rawValue: rawValue)
        else { return .defaultStyle }
        return style
    }
}
