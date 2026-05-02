//
//  WindowsToGoPrototype.swift
//  Fluffy Flash
//
//  Research-only prototype for the Windows-To-Go track.
//  Read first: ObsidianVault/10-Project-Wist/Windows-To-Go-Research.md.
//
//  EVERY public entry point in this file is gated behind `WTG_LOCAL`. Without
//  that compilation condition the methods throw `requiresWtgLocal`, so this
//  cannot accidentally ship in a release build.
//

import CryptoKit
import Foundation

private func cryptoKitSha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

/// Tiny thread-safe collector used by the wimlib stderr stream.
/// Exists in this file because `ProcessRunner.runCollectingOutput`'s closure
/// is `@Sendable` and we want the stderr tail without leaking heavy state.
final class SafeStringCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let maxRetained = 256

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        if lines.count > maxRetained {
            lines.removeFirst(lines.count - maxRetained)
        }
        lock.unlock()
    }

    func tail(maxLines: Int) -> String {
        lock.lock()
        let snapshot = lines.suffix(maxLines).joined(separator: "\n")
        lock.unlock()
        return snapshot
    }
}

/// Marker namespace for the future Windows-To-Go pipeline.
enum WindowsToGoPrototype {

    // MARK: - Public model

    enum Slice: String, CaseIterable, Sendable {
        case partitioning
        case ntfsWriteSpike
        case applyInstallWim
        case copyBootloader
        case bootTest

        var description: String {
            switch self {
            case .partitioning:
                return "Create GPT layout with EFI System Partition + main NTFS partition."
            case .ntfsWriteSpike:
                return "Verify ntfs-3g / FUSE-T workflow on a non-shipping branch."
            case .applyInstallWim:
                return "Use wimlib-imagex apply to extract install.wim onto NTFS."
            case .copyBootloader:
                return "Copy bootmgfw.efi + templated BCD onto the EFI partition."
            case .bootTest:
                return "Boot test on Intel + ARM hardware, with/without Secure Boot."
            }
        }
    }

    enum WTGError: LocalizedError, Equatable {
        case requiresWtgLocal
        case diskutilFailed(stage: String, stderr: String)
        case parsingFailed(String)
        case ntfsToolMissing(String)
        case fuseNotInstalled
        case unsupportedDisk(String)
        case sliceNotImplemented(Slice)
        case verificationFailed(String)

        var errorDescription: String? {
            switch self {
            case .requiresWtgLocal:
                return "Windows-To-Go is gated behind WTG_LOCAL (DEBUG only)."
            case .diskutilFailed(let stage, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return "diskutil \(stage) failed: \(trimmed)"
            case .parsingFailed(let what):
                return "Could not parse diskutil output: \(what)."
            case .ntfsToolMissing(let name):
                return "Required NTFS tool not found: \(name). Install ntfs-3g (Homebrew) and FUSE-T."
            case .fuseNotInstalled:
                return "FUSE-T or macFUSE is not installed. Windows-To-Go requires a FUSE provider on macOS."
            case .unsupportedDisk(let why):
                return "Unsupported target disk: \(why)."
            case .sliceNotImplemented(let s):
                return "Windows-To-Go slice not implemented yet: \(s.rawValue)."
            case .verificationFailed(let why):
                return "Verification failed: \(why)."
            }
        }
    }

    /// Result of `partitionDisk(bsdName:dryRun:)`.
    struct PartitionLayout: Sendable, Equatable {
        let espDeviceID: String     // e.g. "disk5s1"
        let mainDeviceID: String    // e.g. "disk5s2"
        let espMountPoint: URL?     // typically `/Volumes/EFI`, nil if unmounted
    }

    // MARK: - Slice 1: partitioning

    /// Create a GPT layout suitable for Windows-To-Go on `bsdName` (e.g. "disk5").
    ///
    /// - Important: This **erases** the disk. The caller must have explicit user consent.
    /// - Parameters:
    ///   - bsdName: BSD device identifier without the `/dev/` prefix.
    ///   - dryRun:  When `true`, no `diskutil` write commands are executed; the function
    ///              instead returns a synthesised layout for tests and rehearsals.
    ///   - runner:  Process runner injection point for tests.
    static func partitionDisk(
        bsdName: String,
        dryRun: Bool = false,
        runner: ProcessRunning = SystemProcessRunner()
    ) async throws -> PartitionLayout {
        try ensureGate()
        try validateBsdName(bsdName)

        let device = "/dev/\(bsdName)"
        if dryRun {
            return PartitionLayout(
                espDeviceID: "\(bsdName)s1",
                mainDeviceID: "\(bsdName)s2",
                espMountPoint: URL(fileURLWithPath: "/Volumes/EFI")
            )
        }

        // 200 MiB FAT32 ESP, the rest is left as `free` so we can `mkntfs` it ourselves
        // in slice 2 (avoids macOS auto-mounting an unwanted exFAT volume).
        let args = [
            "partitionDisk",
            device,
            "GPT",
            "fat32", "EFI", "200M",
            "free", "WTGMAIN", "R",
        ]
        let output = try await runner.run(executable: "/usr/sbin/diskutil", arguments: args)
        if output.terminationStatus != 0 {
            throw WTGError.diskutilFailed(stage: "partitionDisk", stderr: output.combinedOutput)
        }

        // Re-read the layout to get fresh slice IDs and mount points.
        let listOutput = try await runner.run(
            executable: "/usr/sbin/diskutil",
            arguments: ["list", "-plist", device]
        )
        guard listOutput.terminationStatus == 0 else {
            throw WTGError.diskutilFailed(stage: "list", stderr: listOutput.combinedOutput)
        }
        return try parseLayout(diskutilListPlist: listOutput.stdoutData, parentDisk: bsdName)
    }

    /// Parses `diskutil list -plist <disk>` output into a `PartitionLayout`.
    /// Exposed for tests; do not call directly from production code.
    static func parseLayout(diskutilListPlist data: Data, parentDisk: String) throws -> PartitionLayout {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw WTGError.parsingFailed("plist deserialization: \(error.localizedDescription)")
        }

        guard let root = plist as? [String: Any],
              let allDisksAndPartitions = root["AllDisksAndPartitions"] as? [[String: Any]] else {
            throw WTGError.parsingFailed("missing AllDisksAndPartitions")
        }

        let parent = allDisksAndPartitions.first { ($0["DeviceIdentifier"] as? String) == parentDisk }
        guard let parent else {
            throw WTGError.parsingFailed("no entry for \(parentDisk)")
        }
        guard let parts = parent["Partitions"] as? [[String: Any]], parts.count >= 2 else {
            throw WTGError.parsingFailed("expected at least 2 partitions on \(parentDisk)")
        }

        let espRaw = parts[0]
        let mainRaw = parts[1]
        guard let espID = espRaw["DeviceIdentifier"] as? String else {
            throw WTGError.parsingFailed("first partition has no DeviceIdentifier")
        }
        guard let mainID = mainRaw["DeviceIdentifier"] as? String else {
            throw WTGError.parsingFailed("second partition has no DeviceIdentifier")
        }
        let mount = (espRaw["MountPoint"] as? String).flatMap { p -> URL? in
            p.isEmpty ? nil : URL(fileURLWithPath: p, isDirectory: true)
        }
        return PartitionLayout(espDeviceID: espID, mainDeviceID: mainID, espMountPoint: mount)
    }

    /// Top-level entry that future code can replace with the real pipeline.
    /// Currently throws so misuse is loud; B1 is wired through `partitionDisk(bsdName:)`.
    static func runPrototype(slice: Slice) throws {
        try ensureGate()
        throw WTGError.sliceNotImplemented(slice)
    }

    // MARK: - Slice 2: NTFS write spike

    /// Result of `ntfsWriteSpike(...)`. Lives outside the function for ergonomic
    /// access from logs, callers, and tests.
    struct NTFSSpikeReport: Sendable, Equatable {
        let bytesWritten: UInt64
        let writeMBps: Double
        let readMBps: Double
        let sha256Match: Bool
        let mountPoint: URL
    }

    /// Looks for a FUSE provider (macFUSE or FUSE-T) on the host. Returns the
    /// human-readable provider name, or nil if neither is installed.
    static func detectFUSEProvider() -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: "/Library/Filesystems/macfuse.fs/Contents/Info.plist") {
            return "macFUSE"
        }
        if fm.fileExists(atPath: "/Library/Filesystems/fuse-t.fs") {
            return "FUSE-T"
        }
        if fm.fileExists(atPath: "/usr/local/lib/libfuse-t.dylib") {
            return "FUSE-T"
        }
        return nil
    }

    /// Format `mainDeviceID` as NTFS, mount via ntfs-3g, write & read back a
    /// scratch file to verify the path end-to-end. The volume is unmounted
    /// before returning.
    ///
    /// Best-effort cleanup: if the test panics, the mount may linger; the
    /// caller is expected to detect this via `diskutil unmountDisk`.
    static func ntfsWriteSpike(
        mainDeviceID: String,
        bytes: UInt64 = 64 * 1024 * 1024,
        runner: ProcessRunning = SystemProcessRunner()
    ) async throws -> NTFSSpikeReport {
        try ensureGate()
        try validatePartitionDeviceID(mainDeviceID)
        guard detectFUSEProvider() != nil else {
            throw WTGError.fuseNotInstalled
        }

        let mkntfs = try await locateExecutable("mkntfs", runner: runner)
        let ntfs3g = try await locateExecutable("ntfs-3g", runner: runner)
        let umount = "/sbin/umount"

        let device = "/dev/\(mainDeviceID)"
        let mountPoint = try makeTemporaryDirectory()

        // Format. -F skips the "are you sure?" prompt; -L sets the volume label.
        let mkntfsResult = try await runner.run(
            executable: mkntfs,
            arguments: ["-Q", "-F", "-L", "WTGMAIN", device]
        )
        if mkntfsResult.terminationStatus != 0 {
            throw WTGError.diskutilFailed(stage: "mkntfs", stderr: mkntfsResult.combinedOutput)
        }

        // Mount via ntfs-3g.
        let mountResult = try await runner.run(
            executable: ntfs3g,
            arguments: [device, mountPoint.path]
        )
        if mountResult.terminationStatus != 0 {
            throw WTGError.diskutilFailed(stage: "ntfs-3g mount", stderr: mountResult.combinedOutput)
        }

        defer {
            // Best-effort unmount on the way out.
            Task.detached(priority: .utility) {
                _ = try? await runner.run(executable: umount, arguments: [mountPoint.path])
            }
        }

        // Generate deterministic test bytes (PRNG with a known seed) so we don't
        // pull megabytes from `/dev/urandom`. We only care about throughput +
        // round-trip integrity, not entropy.
        let payload = makeDeterministicPayload(byteCount: Int(bytes))
        let payloadHash = sha256(of: payload)

        let scratch = mountPoint.appendingPathComponent("wtg-spike.bin")
        let writeStart = Date()
        try payload.write(to: scratch, options: .atomic)
        let writeSeconds = Date().timeIntervalSince(writeStart)

        let readStart = Date()
        let readBack = try Data(contentsOf: scratch, options: [.uncached])
        let readSeconds = Date().timeIntervalSince(readStart)
        let readHash = sha256(of: readBack)

        let writeMBps = writeSeconds > 0 ? Double(payload.count) / writeSeconds / 1_000_000 : 0
        let readMBps = readSeconds > 0 ? Double(readBack.count) / readSeconds / 1_000_000 : 0

        return NTFSSpikeReport(
            bytesWritten: UInt64(payload.count),
            writeMBps: writeMBps,
            readMBps: readMBps,
            sha256Match: payloadHash == readHash,
            mountPoint: mountPoint
        )
    }

    // MARK: - Slice 3: apply install.wim

    struct WimApplyProgress: Sendable {
        var percent: Double           // 0...1
        var line: String              // raw wimlib line (debug aid)
    }

    struct WimApplyReport: Sendable, Equatable {
        let durationSeconds: Double
        let filesAfterApply: Int      // best-effort `find <mount> -type f | wc -l`
        let stderrTail: String
    }

    /// Apply `install.wim` (image at `imageIndex`, 1-based) to the already-mounted
    /// NTFS volume at `mountedNTFS`. Streams progress through `onProgress` and
    /// honours Task cancellation: cancelling the parent task terminates wimlib.
    static func applyInstallWim(
        wim: URL,
        imageIndex: Int,
        mountedNTFS: URL,
        onProgress: (@Sendable (WimApplyProgress) -> Void)? = nil
    ) async throws -> WimApplyReport {
        try ensureGate()
        guard imageIndex >= 1 else {
            throw WTGError.parsingFailed("imageIndex must be >= 1, got \(imageIndex)")
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: wim.path) else {
            throw WTGError.unsupportedDisk("wim missing at \(wim.path)")
        }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: mountedNTFS.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WTGError.unsupportedDisk("mount missing at \(mountedNTFS.path)")
        }

        let wimlib = try BundledToolLocator.wimlibImagexExecutable()

        // wimlib writes progress on stderr in the form
        //   "Extracting file: 12 % done (1234/12345)"
        // we only need the percentage.
        let percentRegex = try NSRegularExpression(pattern: #"(\d{1,3})\s*%"#, options: [])
        let stderrCollector = SafeStringCollector()

        let started = Date()
        try await ProcessRunner.runCollectingOutput(
            executableURL: wimlib,
            arguments: [
                "apply",
                wim.path,
                String(imageIndex),
                mountedNTFS.path,
            ],
            currentDirectoryURL: nil,
            environment: HostToolPaths.environmentForBundledAndHostCLI(),
            onStdoutLine: nil,
            onStderrLine: { line in
                stderrCollector.append(line)
                if let onProgress {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    if let match = percentRegex.firstMatch(in: line, options: [], range: range),
                       match.numberOfRanges >= 2,
                       let r = Range(match.range(at: 1), in: line),
                       let pct = Double(line[r]) {
                        onProgress(WimApplyProgress(percent: max(0, min(1, pct / 100)), line: line))
                    }
                }
            }
        )

        try Task.checkCancellation()

        let elapsed = Date().timeIntervalSince(started)
        let count = countFiles(in: mountedNTFS)
        return WimApplyReport(
            durationSeconds: elapsed,
            filesAfterApply: count,
            stderrTail: stderrCollector.tail(maxLines: 12)
        )
    }

    private static func countFiles(in root: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
        return count
    }

    // MARK: - Slice 4: bootloader + BCD on the ESP

    struct BootloaderCopyReport: Sendable, Equatable {
        let copiedFiles: [String]   // paths relative to `esp`
        let bcdProvenance: String   // human-readable source description
    }

    /// Sources for the BCD store. `templateBundleResource` lets us swap in a
    /// known-good BCD shipped inside the .app once we have one; for now it
    /// defaults to copying the BCD-Template that ships inside `install.wim`.
    enum BCDSource: Sendable {
        case fromInstallWim                 // <ntfs>/Windows/System32/Config/BCD-Template
        case file(URL, provenance: String)  // user-supplied template
    }

    /// Copy the EFI bootloader and a minimal BCD onto `esp`.
    ///
    /// - Parameters:
    ///   - esp: Mounted ESP volume (typically `/Volumes/EFI`).
    ///   - ntfsMount: Mounted NTFS volume that already has Windows files (after Slice 3).
    ///   - bcdSource: Where to take the BCD hive from.
    static func copyBootloader(
        esp: URL,
        ntfsMount: URL,
        bcdSource: BCDSource = .fromInstallWim
    ) async throws -> BootloaderCopyReport {
        try ensureGate()
        let fm = FileManager.default
        let bootDir = esp.appendingPathComponent("EFI/Microsoft/Boot", isDirectory: true)
        try fm.createDirectory(at: bootDir, withIntermediateDirectories: true)

        var copied: [String] = []

        let bootmgfw = ntfsMount.appendingPathComponent("Windows/Boot/EFI/bootmgfw.efi")
        let bootmgr = ntfsMount.appendingPathComponent("Windows/Boot/EFI/bootmgr.efi")

        for src in [bootmgfw, bootmgr] {
            guard fm.fileExists(atPath: src.path) else {
                throw WTGError.unsupportedDisk("missing \(src.lastPathComponent) in NTFS image")
            }
            let dst = bootDir.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
            copied.append("EFI/Microsoft/Boot/\(src.lastPathComponent)")
        }

        let bcdDestination = bootDir.appendingPathComponent("BCD")
        let provenance: String

        switch bcdSource {
        case .fromInstallWim:
            // BCD-Template lives inside the applied Windows files; there is
            // no fully reliable single path, so we probe the common ones.
            let candidates = [
                ntfsMount.appendingPathComponent("Windows/System32/Config/BCD-Template"),
                ntfsMount.appendingPathComponent("Windows/System32/Boot/BCD-Template"),
                ntfsMount.appendingPathComponent("Windows/Boot/EFI/bootmgfw.efi.mui"),
            ]
            guard let src = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
                throw WTGError.unsupportedDisk("could not locate a BCD template inside the NTFS image; supply BCDSource.file(...)")
            }
            if fm.fileExists(atPath: bcdDestination.path) {
                try fm.removeItem(at: bcdDestination)
            }
            try fm.copyItem(at: src, to: bcdDestination)
            provenance = "Copied from \(src.path)"

        case .file(let url, let prov):
            guard fm.fileExists(atPath: url.path) else {
                throw WTGError.unsupportedDisk("BCD template not found at \(url.path)")
            }
            if fm.fileExists(atPath: bcdDestination.path) {
                try fm.removeItem(at: bcdDestination)
            }
            try fm.copyItem(at: url, to: bcdDestination)
            provenance = prov
        }
        copied.append("EFI/Microsoft/Boot/BCD")

        return BootloaderCopyReport(copiedFiles: copied, bcdProvenance: provenance)
    }

    static func validatePartitionDeviceID(_ name: String) throws {
        guard name.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil else {
            throw WTGError.unsupportedDisk("partition id must match diskNsM, got \(name)")
        }
        if name.hasPrefix("disk0") {
            throw WTGError.unsupportedDisk("refusing to operate on the boot disk (disk0)")
        }
    }

    // MARK: - Helpers (internal)

    private static func ensureGate() throws {
        #if !(DEBUG && WTG_LOCAL)
        throw WTGError.requiresWtgLocal
        #endif
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("wtg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Find an executable on PATH. We do not bundle ntfs-3g yet; callers must
    /// have installed it via Homebrew. Throws `ntfsToolMissing` otherwise.
    private static func locateExecutable(_ name: String, runner: ProcessRunning) async throws -> String {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/opt/homebrew/sbin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/local/sbin/\(name)",
            "/usr/bin/\(name)",
            "/sbin/\(name)",
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Last resort: ask /usr/bin/which.
        let which = try await runner.run(executable: "/usr/bin/which", arguments: [name])
        let trimmed = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if which.terminationStatus == 0, !trimmed.isEmpty, fm.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        throw WTGError.ntfsToolMissing(name)
    }

    /// Deterministic, fast bytes — we just need a unique payload to verify the
    /// round trip. Uses a counter-mode PRNG so there's no `/dev/urandom` cost.
    static func makeDeterministicPayload(byteCount: Int) -> Data {
        var data = Data(count: byteCount)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt64.self) else { return }
            let words = byteCount / MemoryLayout<UInt64>.size
            var state: UInt64 = 0xC2B2_AE3D_27D4_EB4F
            for i in 0..<words {
                state &+= 0x9E37_79B9_7F4A_7C15
                let z = (state ^ (state &>> 30)) &* 0xBF58_476D_1CE4_E5B9
                let z2 = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
                base[i] = z2 ^ (z2 &>> 31)
            }
        }
        return data
    }

    static func sha256(of data: Data) -> String {
        // Lightweight inline hash so the spike does not depend on SHA256Hasher's
        // file-handle path. Uses CryptoKit which is part of the macOS SDK.
        #if canImport(CryptoKit)
        return cryptoKitSha256Hex(data)
        #else
        // Should never happen on macOS; placeholder for future Linux ports.
        return "<sha256 unavailable>"
        #endif
    }

    /// Sanity-check the BSD name we pass to `diskutil`. We do not want a stray
    /// `/dev/disk0` (boot drive) or a path injection through this entry point.
    static func validateBsdName(_ name: String) throws {
        guard !name.isEmpty else {
            throw WTGError.unsupportedDisk("empty bsdName")
        }
        guard name.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else {
            throw WTGError.unsupportedDisk("BSD name must match diskN, got \(name)")
        }
        if name == "disk0" {
            throw WTGError.unsupportedDisk("refusing to operate on the boot disk (disk0)")
        }
    }
}

// MARK: - Process runner abstraction

/// Output of an external command invocation, used by Windows-To-Go prototype steps.
struct WTGProcessOutput: Sendable {
    var terminationStatus: Int32
    var stdout: String
    var stderr: String
    /// Concatenation of stdout + stderr, useful for error messages.
    var combinedOutput: String { stdout + (stdout.isEmpty || stderr.isEmpty ? "" : "\n") + stderr }
    /// Raw stdout bytes, needed when the consumer expects binary output (e.g. plist).
    var stdoutData: Data
}

protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String]) async throws -> WTGProcessOutput
}

/// Default implementation backed by `Foundation.Process`. Lives in the same
/// file because it's only used by the WTG prototype today.
struct SystemProcessRunner: ProcessRunning {
    func run(executable: String, arguments: [String]) async throws -> WTGProcessOutput {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<WTGProcessOutput, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.terminationHandler = { proc in
                let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                cont.resume(returning: WTGProcessOutput(
                    terminationStatus: proc.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    stdoutData: outData
                ))
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
