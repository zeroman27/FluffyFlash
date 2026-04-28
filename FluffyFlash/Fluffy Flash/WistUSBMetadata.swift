//
//  WistUSBMetadata.swift
//  Wist
//
//  Sidecar JSON on the FAT32 volume (written by the app).
//

import Foundation

/// Written to `FluffyFlash.meta.json` at the root of the `WINSETUP` volume before eject.
struct WistUSBMetadata: Codable, Equatable, Hashable, Sendable {
    static let fileName = "FluffyFlash.meta.json"
    static let currentSchema = 1

    var schemaVersion: Int
    /// UUP build uuid (or synthetic id for ISO-only path).
    var buildUuid: String
    var buildNumber: String
    var arch: String
    var language: String
    var editionToken: String
    /// Human title from UUP when available.
    var buildTitle: String?
    /// ISO path used for write (optional).
    var sourceIsoPath: String?
    /// ISO8601
    var writtenAt: String

    init(
        buildUuid: String,
        buildNumber: String,
        arch: String,
        language: String,
        editionToken: String,
        buildTitle: String? = nil,
        sourceIsoPath: String? = nil,
        writtenAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchema
        self.buildUuid = buildUuid
        self.buildNumber = buildNumber
        self.arch = arch
        self.language = language
        self.editionToken = editionToken
        self.buildTitle = buildTitle
        self.sourceIsoPath = sourceIsoPath
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.writtenAt = f.string(from: writtenAt)
    }

    func write(to volumeRoot: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(self)
        let url = volumeRoot.appendingPathComponent(Self.fileName)
        try data.write(to: url, options: .atomic)
    }

    /// Tries `FluffyFlash.meta.json`, then `Wist.meta.json`, then legacy `WinForge.meta.json`.
    static func read(from volumeRoot: URL) -> WistUSBMetadata? {
        let candidates = [fileName, "Wist.meta.json", "WinForge.meta.json"]
        for name in candidates {
            let url = volumeRoot.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            if let meta = try? JSONDecoder().decode(WistUSBMetadata.self, from: data) {
                return meta
            }
        }
        return nil
    }
}
