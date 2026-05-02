//
//  ISOFat32Precheck.swift
//  Wist
//

import Foundation

/// FAT32: a single file cannot exceed 2³²−1 bytes (~4 GiB).
enum ISOFat32Precheck: Sendable {
    static let maxSingleFileBytes: UInt64 = 4_294_967_295

    struct OversizeEntry: Sendable {
        let relativePath: String
        let sizeBytes: UInt64
    }

    /// Files in the ISO that cannot be placed on FAT32 as a single file without split/exclusion.
    static func oversizeFiles(isoRoot: URL) throws -> [OversizeEntry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: isoRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        let rootPath = isoRoot.path
        var results: [OversizeEntry] = []

        while let item = enumerator.nextObject() as? URL {
            let vals = try item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard vals.isRegularFile == true else { continue }
            // On mounted ISO/UDF, `fileSizeKey` can be 0; `attributesOfItem` is more reliable.
            let attrSize: UInt64 = {
                guard let attrs = try? fm.attributesOfItem(atPath: item.path) else { return 0 }
                if let n = attrs[.size] as? NSNumber { return n.uint64Value }
                if let u = attrs[.size] as? UInt64 { return u }
                return 0
            }()
            let resSize = UInt64(vals.fileSize ?? 0)
            let size = max(attrSize, resSize)
            guard size > maxSingleFileBytes else { continue }

            var rel = String(item.path.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            rel = rel.replacingOccurrences(of: "\\", with: "/")
            results.append(OversizeEntry(relativePath: rel, sizeBytes: size))
        }

        return results.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    /// Only heavy `sources/install.wim` and `sources/install.esd` may exceed the limit (copied via split).
    static func validateOnlyInstallImagesAreOversize(_ entries: [OversizeEntry]) throws {
        let allowed: Set<String> = ["sources/install.wim", "sources/install.esd"]
        let bad = entries.filter { !allowed.contains($0.relativePath.lowercased()) }
        guard !bad.isEmpty else { return }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        let detail = bad.map { e in
            let size = formatter.string(fromByteCount: Int64(min(UInt64(Int64.max), e.sizeBytes)))
            return String(format: String(localized: "  • %@ — %@"), e.relativePath, size)
        }.joined(separator: "\n")
        throw USBWriterError.fat32OversizeUnsupported(detail)
    }

    /// Cross-check via `/usr/bin/find` (size in KiB, `+3800m`).
    static func oversizePathsViaFind(isoRoot: URL) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        p.arguments = [isoRoot.path, "-type", "f", "-size", "+3800m"]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return []
        }
        guard p.terminationStatus == 0 else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let s = String(data: data, encoding: .utf8), !s.isEmpty else { return [] }
        return s.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }
}
