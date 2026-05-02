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
    /// Honours `Task.checkCancellation()` between files so the user-facing Stop button
    /// terminates the copy promptly.
    static func copyTree(
        from isoRoot: URL,
        to usbRoot: URL,
        log: @escaping @Sendable (String) -> Void,
        onProgress: (@Sendable (_ copiedBytes: UInt64, _ totalBytes: UInt64, _ currentRelativePath: String?) -> Void)? = nil
    ) async throws {
        let cancelFlag = AtomicCancellationFlag()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try Self.syncCopyTree(
                            from: isoRoot,
                            to: usbRoot,
                            log: log,
                            onProgress: onProgress,
                            isCancelled: { cancelFlag.value }
                        )
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancelFlag.set()
        }
    }

    /// Tiny lock-free flag the background copy reads between files.
    private final class AtomicCancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        var value: Bool {
            lock.lock(); defer { lock.unlock() }
            return flag
        }
        func set() {
            lock.lock(); defer { lock.unlock() }
            flag = true
        }
    }

    private static func syncCopyTree(
        from isoRoot: URL,
        to usbRoot: URL,
        log: @Sendable (String) -> Void,
        onProgress: (@Sendable (_ copiedBytes: UInt64, _ totalBytes: UInt64, _ currentRelativePath: String?) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) throws {
        let fm = FileManager.default
        let isoPath = isoRoot.path
        let totalBytes = try totalCopyBytes(isoRoot: isoRoot)
        var copiedBytes: UInt64 = 0
        onProgress?(0, totalBytes, nil)

        func checkCancel() throws {
            if isCancelled() { throw CancellationError() }
        }

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
                // For progress, measure the source file size up-front.
                let srcSize: UInt64 = {
                    if let attrs = try? fm.attributesOfItem(atPath: src.path) {
                        if let n = attrs[.size] as? NSNumber { return n.uint64Value }
                        if let u = attrs[.size] as? UInt64 { return u }
                    }
                    return 0
                }()
                try fm.copyItem(at: src, to: dst)
                if srcSize > 0 {
                    copiedBytes = min(totalBytes, copiedBytes &+ srcSize)
                    onProgress?(copiedBytes, totalBytes, rel)
                }
            } catch {
                throw WindowsISOFileCopyError.copyFailed(path: rel, underlying: error.localizedDescription)
            }
        }

        func walk(_ srcDir: URL, _ dstDir: URL) throws {
            try checkCancel()
            let entries = try fm.contentsOfDirectory(
                at: srcDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )

            for src in entries {
                try checkCancel()
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
            try checkCancel()
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
        onProgress?(totalBytes, totalBytes, nil)
    }

    private static func totalCopyBytes(isoRoot: URL) throws -> UInt64 {
        let fm = FileManager.default
        let isoPath = isoRoot.path

        func relativePath(for url: URL) -> String {
            var rel = String(url.path.dropFirst(isoPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel.replacingOccurrences(of: "\\", with: "/")
        }

        var total: UInt64 = 0
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey]
        let opts: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        let e = fm.enumerator(at: isoRoot, includingPropertiesForKeys: Array(keys), options: opts)
        while let url = e?.nextObject() as? URL {
            let rel = relativePath(for: url)
            let name = url.lastPathComponent
            if rel.isEmpty { continue }
            if url.deletingLastPathComponent().path == isoRoot.path, shouldSkipRootFile(name: name) {
                continue
            }
            if shouldSkipRelativePath(rel) {
                // Skip install.wim/esd, counted separately (split later).
                continue
            }
            if let values = try? url.resourceValues(forKeys: keys),
               values.isDirectory == true {
                continue
            }
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                total &+= UInt64(max(0, size))
            }
        }
        return total
    }
}
