//
//  UUPCacheMetadata.swift
//  Wist
//
//  Sidecar next to downloaded UUP files so the Downloads table can show a human title without reloading the catalog.
//

import Foundation

struct UUPCacheMetadata: Codable, Equatable, Hashable, Sendable {
    static let fileName = "Wist.cache.json"
    static let schemaVersion = 1

    var schemaVersion: Int
    var uuid: String
    var title: String
    var buildNumber: String
    var arch: String
    var created: Int?
    /// UUP language code (e.g. en-us).
    var languageCode: String
    /// Selected edition token when downloaded.
    var editionToken: String

    init(
        uuid: String,
        title: String,
        buildNumber: String,
        arch: String,
        created: Int?,
        languageCode: String,
        editionToken: String
    ) {
        self.schemaVersion = Self.schemaVersion
        self.uuid = uuid
        self.title = title
        self.buildNumber = buildNumber
        self.arch = arch
        self.created = created
        self.languageCode = languageCode
        self.editionToken = editionToken
    }

    func write(into uupDirectory: URL) throws {
        let url = uupDirectory.appendingPathComponent(Self.fileName)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    static func read(from uupDirectory: URL) -> UUPCacheMetadata? {
        let url = uupDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UUPCacheMetadata.self, from: data)
    }
}
