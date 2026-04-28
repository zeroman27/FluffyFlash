//
//  DiskManager.swift
//  Wist
//

import Combine
import Foundation

// MARK: - Removable drive model

/// A USB or other external whole-disk device suitable as a Windows installer target.
struct RemovableDriveInfo: Identifiable, Hashable {
    /// e.g. "disk4" — pass to future `diskutil eraseDisk ... /dev/disk4`
    var id: String { deviceIdentifier }
    let deviceIdentifier: String
    /// Manufacturer / model name from diskutil when available.
    let mediaName: String
    /// Total capacity in bytes (`TotalSize` from `diskutil info`).
    let totalSizeBytes: Int64
    /// Parsed from `FluffyFlash.meta.json` (or legacy `Wist.meta.json`) on a mounted volume belonging to this whole disk, if present.
    var wistSidecarMeta: WistUSBMetadata?
    /// A mounted volume path belonging to this whole disk (best-effort). Needed
    /// for Finder-level customization like setting a custom volume icon.
    var mountPoint: URL?
}

// MARK: - DiskManager

/// Discovers external removable drives using `diskutil` (same binary the UI will later use for erase).
///
/// **Phase 2+ integration (via `Process`):**
/// - **Format USB:** `diskutil eraseDisk MS-DOS "WINSETUP" MBRFormat /dev/diskX`
/// - **Mount ISO:** `hdiutil attach -nomount /path/to.iso` then mount to a temp directory
/// - **Copy (exclude WIM):** `rsync -av --exclude='sources/install.wim' ...`
/// - **Split WIM:** run bundled `wimlib-imagex` from `Bundle.main.url(forResource:withExtension:)` →
///   `wimlib-imagex split /Volumes/ISO/sources/install.wim /Volumes/USB/sources/install.swm 3800`
///   Add `wimlib-imagex` under **Copy Bundle Resources** and preserve the executable bit (build phase script if needed).
@MainActor
final class DiskManager: ObservableObject {

    @Published private(set) var drives: [RemovableDriveInfo] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    /// Refreshes the drive list by shelling out to `diskutil` off the main thread.
    func refresh() async {
        isRefreshing = true
        lastError = nil
        let result: Result<[RemovableDriveInfo], Error> = await Task.detached(priority: .userInitiated) {
            Result {
                let list = try DiskManager.fetchEligibleRemovableDrives()
                return DiskManager.attachWistSidecarMeta(to: list)
            }
        }.value
        isRefreshing = false
        switch result {
        case .success(let list):
            drives = list
        case .failure(let error):
            lastError = error.localizedDescription
            drives = []
        }
    }

    // MARK: - diskutil (nonisolated)

    private static let diskutilPath = "/usr/sbin/diskutil"

    /// Enumerate whole disks, then keep only devices that are not internal and are removable or ejectable.
    nonisolated private static func fetchEligibleRemovableDrives() throws -> [RemovableDriveInfo] {
        let listPlist = try runDiskutil(arguments: ["list", "-plist"])
        let wholeDisks = try parseWholeDiskIdentifiers(fromListPlist: listPlist)

        var found: [RemovableDriveInfo] = []
        found.reserveCapacity(wholeDisks.count)

        for diskID in wholeDisks {
            let infoPlist = try runDiskutil(arguments: ["info", "-plist", "/dev/\(diskID)"])
            guard let drive = try parseRemovableDriveIfEligible(infoPlist: infoPlist, deviceIdentifier: diskID) else {
                continue
            }
            found.append(drive)
        }

        return found.sorted { $0.deviceIdentifier < $1.deviceIdentifier }
    }

    /// Runs `/usr/sbin/diskutil` and returns stdout. Used for `list` / `info` today; same pattern will run `eraseDisk` later.
    nonisolated private static func runDiskutil(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: diskutilPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let output = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw DiskManagerError.diskutilFailed(
                arguments: arguments,
                status: Int(process.terminationStatus),
                stderr: errText
            )
        }

        return output
    }

    nonisolated private static func parseWholeDiskIdentifiers(fromListPlist data: Data) throws -> [String] {
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let root = obj as? [String: Any] else {
            throw DiskManagerError.unexpectedPlist("Root is not a dictionary")
        }
        guard let whole = root["WholeDisks"] as? [String] else {
            throw DiskManagerError.unexpectedPlist("Missing WholeDisks")
        }
        // WholeDisks entries are already whole devices (disk3), not slices (disk3s1).
        return whole
    }

    /// Filters using `Internal`, `RemovableMedia`, and `Ejectable` from `diskutil info -plist`.
    /// Excludes the internal SSD; keeps typical USB sticks (Removable) and some external enclosures (Ejectable, not internal).
    nonisolated private static func parseRemovableDriveIfEligible(
        infoPlist data: Data,
        deviceIdentifier: String
    ) throws -> RemovableDriveInfo? {
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = obj as? [String: Any] else {
            throw DiskManagerError.unexpectedPlist("info plist root")
        }

        let internalDisk = bool(forKey: "Internal", in: dict) ?? true
        if internalDisk {
            return nil
        }

        // Exclude virtual devices such as disk images / simulator volumes.
        // These often show up as Ejectable+Removable and would otherwise pollute the USB list.
        if let vop = dict["VirtualOrPhysical"] as? String,
           vop.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "virtual" {
            return nil
        }
        if let bus = dict["BusProtocol"] as? String,
           bus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "disk image" {
            return nil
        }
        if let registryName = dict["IORegistryEntryName"] as? String,
           registryName.localizedCaseInsensitiveContains("disk image") {
            return nil
        }

        let removableMedia = bool(forKey: "RemovableMedia", in: dict) ?? false
        let ejectable = bool(forKey: "Ejectable", in: dict) ?? false
        guard removableMedia || ejectable else {
            return nil
        }

        let mediaName = dict["MediaName"] as? String
        let volumeName = dict["VolumeName"] as? String
        // Extra hard stop: some virtual devices still slip through with a generic name.
        if (mediaName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Disk Image") == .orderedSame {
            return nil
        }
        let title = [volumeName, mediaName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? deviceIdentifier

        let totalSize: Int64
        if let n = dict["TotalSize"] as? NSNumber {
            totalSize = n.int64Value
        } else if let i = dict["TotalSize"] as? Int64 {
            totalSize = i
        } else {
            totalSize = 0
        }

        return RemovableDriveInfo(
            deviceIdentifier: deviceIdentifier,
            mediaName: title,
            totalSizeBytes: totalSize,
            wistSidecarMeta: nil
        )
    }

    /// Scans `/Volumes` for Fluffy Flash / Wist sidecar JSON, maps each file to a whole-disk id via `diskutil info`, merges into `drives`.
    nonisolated private static func attachWistSidecarMeta(to drives: [RemovableDriveInfo]) -> [RemovableDriveInfo] {
        let volumesRoot = URL(fileURLWithPath: "/Volumes")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: volumesRoot.path) else {
            return drives
        }
        var metaByWholeDisk: [String: WistUSBMetadata] = [:]
        var mountByWholeDisk: [String: URL] = [:]
        for name in names where !name.hasPrefix(".") {
            let vol = volumesRoot.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: vol.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let whole = wholeDiskForVolumeMount(at: vol) else { continue }
            if mountByWholeDisk[whole] == nil {
                mountByWholeDisk[whole] = vol
            }
            guard let meta = WistUSBMetadata.read(from: vol) else { continue }
            metaByWholeDisk[whole] = meta
        }
        guard !metaByWholeDisk.isEmpty || !mountByWholeDisk.isEmpty else { return drives }
        return drives.map { d in
            var copy = d
            if let m = metaByWholeDisk[d.deviceIdentifier] {
                copy.wistSidecarMeta = m
            }
            if let mount = mountByWholeDisk[d.deviceIdentifier] {
                copy.mountPoint = mount
            }
            return copy
        }
    }

    /// Resolves `disk4` from a volume mount path using `diskutil info -plist` (`DeviceIdentifier` like `disk4s1`).
    nonisolated private static func wholeDiskForVolumeMount(at volumeURL: URL) -> String? {
        guard let data = try? runDiskutil(arguments: ["info", "-plist", volumeURL.path]) else { return nil }
        let obj: Any
        do {
            obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            return nil
        }
        guard let dict = obj as? [String: Any] else { return nil }
        let deviceID = dict["DeviceIdentifier"] as? String
            ?? dict["DeviceNode"] as? String
        guard let raw = deviceID else { return nil }
        let id = raw.hasPrefix("/dev/") ? String(raw.dropFirst(5)) : raw
        return wholeDiskFromSliceIdentifier(id)
    }

    /// `disk7s1` → `disk7`; `disk7` → `disk7`.
    nonisolated private static func wholeDiskFromSliceIdentifier(_ deviceIdentifier: String) -> String? {
        if deviceIdentifier.range(of: #"^disk\d+$"#, options: .regularExpression) != nil {
            return deviceIdentifier
        }
        guard let regex = try? NSRegularExpression(pattern: #"^(disk\d+)s\d+$"#) else { return nil }
        let ns = deviceIdentifier as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: deviceIdentifier, range: full), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    nonisolated private static func bool(forKey key: String, in dict: [String: Any]) -> Bool? {
        if let b = dict[key] as? Bool { return b }
        if let n = dict[key] as? NSNumber { return n.boolValue }
        return nil
    }
}

// MARK: - Errors

private enum DiskManagerError: LocalizedError {
    case diskutilFailed(arguments: [String], status: Int, stderr: String)
    case unexpectedPlist(String)

    var errorDescription: String? {
        switch self {
        case .diskutilFailed(let arguments, let status, let stderr):
            let cmd = (["diskutil"] + arguments).joined(separator: " ")
            let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.isEmpty {
                return "diskutil failed (\(status)): \(cmd)"
            }
            return "diskutil failed (\(status)): \(cmd)\n\(tail)"
        case .unexpectedPlist(let reason):
            return "Could not parse diskutil output: \(reason)"
        }
    }
}
