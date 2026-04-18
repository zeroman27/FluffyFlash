//
//  WindowsISOFileCopy.swift
//  Wist
//
//  Copy from a mounted ISO to FAT32 without rsync (FileManager-based, WinDiskWriter-style).
//

import Foundation

enum WindowsISOFileCopyError: LocalizedError {
    case copyFailed(path: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .copyFailed(let path, let underlying):
            return String(format: String(localized: "Could not copy “%@”: %@"), path, underlying)
        }
    }
}

enum WindowsISOFileCopy: Sendable {

    private static func shouldSkipRootFile(name: String) -> Bool {
        let lower = name.lowercased()
        if lower == "boot.catalog" { return true }
        if lower == ".ds_store" { return true }
        return false
    }

    private static func shouldSkipRelativePath(_ relative: String) -> Bool {
        let lower = relative.lowercased().replacingOccurrences(of: "\\", with: "/")
        if lower == "sources/install.wim" { return true }
        if lower == "sources/install.esd" { return true }
        return false
    }

    /// Recursively copies ISO → USB, skipping install.wim/esd (split later) and boot.catalog.
    static func copyTree(
        from isoRoot: URL,
        to usbRoot: URL,
        log: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.syncCopyTree(from: isoRoot, to: usbRoot, log: log)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private static func syncCopyTree(
        from isoRoot: URL,
        to usbRoot: URL,
        log: @Sendable (String) -> Void
    ) throws {
        let fm = FileManager.default
        let isoPath = isoRoot.path

        func relativePath(for url: URL) -> String {
            var rel = String(url.path.dropFirst(isoPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel.replacingOccurrences(of: "\\", with: "/")
        }

        func ensureParentDir(for fileURL: URL) throws {
            let parent = fileURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parent.path) {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            }
        }

        func copyOneFile(from src: URL, to dst: URL, rel: String) throws {
            try ensureParentDir(for: dst)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                throw WindowsISOFileCopyError.copyFailed(path: rel, underlying: error.localizedDescription)
            }
        }

        func walk(_ srcDir: URL, _ dstDir: URL) throws {
            let entries = try fm.contentsOfDirectory(
                at: srcDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )

            for src in entries {
                let rel = relativePath(for: src)
                if shouldSkipRelativePath(rel) {
                    log(String(format: String(localized: "Skipping (split later): %@"), rel))
                    continue
                }

                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else { continue }

                let name = src.lastPathComponent
                let dst = dstDir.appendingPathComponent(name)

                if isDir.boolValue {
                    if !fm.fileExists(atPath: dst.path) {
                        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
                    }
                    try walk(src, dst)
                } else {
                    try copyOneFile(from: src, to: dst, rel: rel)
                }
            }
        }

        let rootEntries = try fm.contentsOfDirectory(
            at: isoRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        for src in rootEntries {
            let name = src.lastPathComponent
            if shouldSkipRootFile(name: name) {
                log(String(format: String(localized: "Skipping: %@"), name))
                continue
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else { continue }

            let dst = usbRoot.appendingPathComponent(name)
            let rel = relativePath(for: src)

            if isDir.boolValue {
                if !fm.fileExists(atPath: dst.path) {
                    try fm.createDirectory(at: dst, withIntermediateDirectories: true)
                }
                log(String(format: String(localized: "Copying: %@/ …"), name))
                try walk(src, dst)
            } else {
                try copyOneFile(from: src, to: dst, rel: rel)
            }
        }
    }
}
