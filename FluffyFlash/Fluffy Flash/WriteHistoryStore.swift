//
//  WriteHistoryStore.swift
//  Fluffy Flash
//
//  Persistent journal of completed USB writes (JSON under Application Support).
//

import Combine
import Foundation

struct WriteHistoryEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var dateISO8601: String
    var buildUuid: String
    var buildNumber: String
    var buildTitle: String?
    var arch: String
    var language: String
    var editionToken: String
    var driveMediaName: String
    var driveDeviceIdentifier: String
    var isoPath: String?
    /// `true` if the write finished without an error.
    var succeeded: Bool
    /// Optional error message surfaced by the writer.
    var errorMessage: String?
    /// Optional filename for the full log captured at completion time.
    /// Stored under `Application Support/FluffyFlash/history-logs/`.
    var logFileName: String?

    var date: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: dateISO8601)
            ?? ISO8601DateFormatter().date(from: dateISO8601)
    }
}

/// JSON-backed append-only log of USB writes. Main-actor isolated to match the UI usage pattern.
@MainActor
final class WriteHistoryStore: ObservableObject {

    @Published private(set) var entries: [WriteHistoryEntry] = []

    private let fileURL: URL
    private let logsDirectoryURL: URL
    private let maxEntries: Int

    init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("FluffyFlash", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("write-history.json")
        self.logsDirectoryURL = dir.appendingPathComponent("history-logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            entries = []
            return
        }
        entries = (try? JSONDecoder().decode([WriteHistoryEntry].self, from: data)) ?? []
    }

    func append(_ entry: WriteHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: logsDirectoryURL)
        try? FileManager.default.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Convenience: record a completed pipeline run (one entry per drive).
    func record(
        build: UUPBuilds.Build?,
        metadata: WistUSBMetadata?,
        drives: [RemovableDriveInfo],
        isoPath: String?,
        succeeded: Bool,
        errorMessage: String? = nil,
        fullLogText: String? = nil
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        for drive in drives {
            let id = UUID()
            let logFileName = saveFullLogIfNeeded(text: fullLogText, entryId: id)
            let entry = WriteHistoryEntry(
                id: id,
                dateISO8601: now,
                buildUuid: build?.uuid ?? metadata?.buildUuid ?? "",
                buildNumber: build?.build ?? metadata?.buildNumber ?? "",
                buildTitle: build?.title ?? metadata?.buildTitle,
                arch: build?.arch ?? metadata?.arch ?? "",
                language: metadata?.language ?? "",
                editionToken: metadata?.editionToken ?? "",
                driveMediaName: drive.mediaName,
                driveDeviceIdentifier: drive.deviceIdentifier,
                isoPath: isoPath,
                succeeded: succeeded,
                errorMessage: errorMessage,
                logFileName: logFileName
            )
            append(entry)
        }
    }

    func logFileURL(for entry: WriteHistoryEntry) -> URL? {
        guard let name = entry.logFileName, !name.isEmpty else { return nil }
        return logsDirectoryURL.appendingPathComponent(name)
    }

    func loadFullLogText(for entry: WriteHistoryEntry) -> String? {
        guard let url = logFileURL(for: entry) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func saveFullLogIfNeeded(text: String?, entryId: UUID) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let fileName = "\(entryId.uuidString).log"
        let url = logsDirectoryURL.appendingPathComponent(fileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return fileName
        } catch {
            return nil
        }
    }
}
