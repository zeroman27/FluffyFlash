//
//  WriteHistoryStore.swift
//  Fluffy Flash
//
//  Persistent journal of completed USB writes (JSON under Application Support).
//

import Combine
import Foundation

/// Stored in `WriteHistoryEntry.kind` (string for JSON compatibility with older logs).
enum WriteHistoryKind: String, Codable, Equatable, Hashable, Sendable {
    case windowsUUP = "windowsUUP"
    case windowsExistingISO = "windowsExistingISO"
    case macOSInstaller = "macOSInstaller"
}

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
    /// Smoothed write throughput captured during the copy stage (bytes per second).
    /// Optional so old entries decode without migration.
    var averageWriteSpeedBytesPerSecond: Double?
    /// `WriteHistoryKind` raw value; `nil` on legacy entries (treated as Windows UUP in filters).
    var kind: String?
    /// Wall-clock duration of the pipeline run (seconds).
    var durationSeconds: Double?
    /// macOS installer display name (sidecar / Mist).
    var installerDisplayName: String?
    /// macOS marketing version from sidecar when available.
    var installerMarketingVersion: String?
    /// Mist catalog `build` string used for download (repeat macOS write).
    var macOSCatalogBuild: String?

    var date: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: dateISO8601)
            ?? ISO8601DateFormatter().date(from: dateISO8601)
    }

    var resolvedKind: WriteHistoryKind {
        if let k = kind, let parsed = WriteHistoryKind(rawValue: k) {
            return parsed
        }
        return .windowsUUP
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
    /// `speedsByDeviceId` carries the smoothed write throughput captured by
    /// `USBWriterViewModel` so we can show "Slow" badges next time the same
    /// drive shows up.
    func record(
        build: UUPBuilds.Build?,
        metadata: WistUSBMetadata?,
        drives: [RemovableDriveInfo],
        isoPath: String?,
        succeeded: Bool,
        errorMessage: String? = nil,
        fullLogText: String? = nil,
        speedsByDeviceId: [String: Double] = [:],
        historyKind: WriteHistoryKind? = nil,
        durationSeconds: Double? = nil
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        let resolvedKind = historyKind ?? .windowsUUP
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
                logFileName: logFileName,
                averageWriteSpeedBytesPerSecond: speedsByDeviceId[drive.deviceIdentifier],
                kind: resolvedKind.rawValue,
                durationSeconds: durationSeconds,
                installerDisplayName: nil,
                installerMarketingVersion: nil,
                macOSCatalogBuild: nil
            )
            append(entry)
        }
    }

    /// One journal row per drive after a macOS installer → USB run.
    func recordMacOSInstallerRun(
        drives: [RemovableDriveInfo],
        succeeded: Bool,
        errorMessage: String?,
        fullLogText: String?,
        catalogBuild: String,
        catalogInstallerName: String?,
        startedAt: Date,
        endedAt: Date,
        speedsByDeviceId: [String: Double] = [:]
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        let duration = endedAt.timeIntervalSince(startedAt)
        for drive in drives {
            let id = UUID()
            let logFileName = saveFullLogIfNeeded(text: fullLogText, entryId: id)
            let sidecar: FluffyMacOSUSBMetadata? = {
                guard succeeded, let m = drive.mountPoint else { return nil }
                return FluffyMacOSUSBMetadata.read(from: m)
            }()
            let entry = WriteHistoryEntry(
                id: id,
                dateISO8601: now,
                buildUuid: "",
                buildNumber: catalogBuild,
                buildTitle: catalogInstallerName ?? sidecar?.installerDisplayName,
                arch: "",
                language: "",
                editionToken: "",
                driveMediaName: drive.mediaName,
                driveDeviceIdentifier: drive.deviceIdentifier,
                isoPath: nil,
                succeeded: succeeded,
                errorMessage: errorMessage,
                logFileName: logFileName,
                averageWriteSpeedBytesPerSecond: speedsByDeviceId[drive.deviceIdentifier],
                kind: WriteHistoryKind.macOSInstaller.rawValue,
                durationSeconds: duration.isFinite && duration >= 0 ? duration : nil,
                installerDisplayName: sidecar?.installerDisplayName,
                installerMarketingVersion: sidecar?.installerMarketingVersion ?? sidecar?.installerShortVersion,
                macOSCatalogBuild: catalogBuild
            )
            append(entry)
        }
    }

    /// Approximate threshold under which we consider a drive "slow".
    /// 8 MB/s is a soft heuristic that catches USB-2 sticks and bottom-tier USB-3 ones.
    static let slowSpeedThresholdBytesPerSecond: Double = 8 * 1024 * 1024

    /// Returns the most recent recorded throughput for the given drive (matched
    /// by media name — device identifiers change between sessions). `nil` if we
    /// haven't seen it yet.
    func lastKnownSpeed(for mediaName: String) -> Double? {
        for entry in entries where entry.driveMediaName == mediaName {
            if let s = entry.averageWriteSpeedBytesPerSecond, s > 0 {
                return s
            }
        }
        return nil
    }

    /// Convenience: `true` when the drive is on record as slower than the threshold.
    func isKnownSlowDrive(mediaName: String) -> Bool {
        guard let s = lastKnownSpeed(for: mediaName) else { return false }
        return s < Self.slowSpeedThresholdBytesPerSecond
    }

    // MARK: - Smart suggestions

    /// Soft speed range expressed in MB/s, derived from the last known speed for
    /// a drive. We widen the value by ±18% so the UI doesn't claim a precise
    /// number when we only have a single noisy sample.
    struct SpeedRangeMBps: Equatable, Sendable {
        var lowMBps: Double
        var highMBps: Double
        /// Centre of the range, useful for ETA math.
        var midBytesPerSecond: Double { (lowMBps + highMBps) / 2 * 1024 * 1024 }
    }

    /// Returns a soft "usually X–Y MB/s" range for a known drive.
    /// Returns `nil` when we have never seen this drive before.
    func expectedSpeedRange(for mediaName: String) -> SpeedRangeMBps? {
        guard let bps = lastKnownSpeed(for: mediaName), bps > 0 else { return nil }
        let mbps = bps / (1024 * 1024)
        let spread = 0.18
        let low = max(0.5, mbps * (1 - spread))
        let high = max(low + 0.5, mbps * (1 + spread))
        return SpeedRangeMBps(lowMBps: low, highMBps: high)
    }

    /// Rough ETA range (seconds) for writing `payloadBytes` to a drive with the
    /// given expected speed range. The ETA is intentionally conservative — we
    /// use the lower MB/s bound as the upper bound of duration so the user is
    /// not surprised by a slower run.
    func expectedDurationRangeSeconds(for mediaName: String, payloadBytes: UInt64) -> ClosedRange<Double>? {
        guard payloadBytes > 0, let range = expectedSpeedRange(for: mediaName) else { return nil }
        let bytes = Double(payloadBytes)
        let high = bytes / (range.lowMBps * 1024 * 1024)
        let low = bytes / (range.highMBps * 1024 * 1024)
        guard low.isFinite, high.isFinite, low > 0, high > 0 else { return nil }
        return min(low, high) ... max(low, high)
    }

    /// Most recent **successful** entry that has an ISO path on disk. Used by
    /// Production Line mode to repeat the last write configuration on a fresh
    /// blank drive.
    var latestSuccessfulConfig: WriteHistoryEntry? {
        for entry in entries where entry.succeeded {
            if let path = entry.isoPath, FileManager.default.fileExists(atPath: path) {
                return entry
            }
        }
        return nil
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
