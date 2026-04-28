//
//  WistCache.swift
//  Wist
//

import Foundation

struct UUPCacheFolder: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let totalBytes: Int64
    /// Written when a UUP download completes (`FluffyFlash.cache.json`), or inferred from sibling UUP folder for `*-iso-build` dirs.
    let cachedMetadata: UUPCacheMetadata?
}

enum WistCache: Sendable {

    private static let legacyCachesFolderName = "Wist"
    private static let cachesFolderName = "FluffyFlash"

    /// `~/Library/Caches/FluffyFlash` (migrates from `Wist` on first access).
    static var cachesRootDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let newRoot = base.appendingPathComponent(cachesFolderName, isDirectory: true)
        let oldRoot = base.appendingPathComponent(legacyCachesFolderName, isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: newRoot.path), fm.fileExists(atPath: oldRoot.path) {
            try? fm.moveItem(at: oldRoot, to: newRoot)
        }
        return newRoot
    }

    static var uupRootDirectory: URL {
        cachesRootDirectory.appendingPathComponent("UUP", isDirectory: true)
    }

    /// Scans `~/Library/Caches/FluffyFlash/UUP/<uuid>/`.
    static func listUUPFolders() -> [UUPCacheFolder] {
        let fm = FileManager.default
        let root = uupRootDirectory
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var out: [UUPCacheFolder] = []
        for name in names {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let size = (try? directorySize(dir)) ?? 0
            let meta = resolveMetadata(root: root, folderName: name, folderURL: dir)
            out.append(UUPCacheFolder(url: dir, name: name, totalBytes: size, cachedMetadata: meta))
        }
        out.sort { $0.name > $1.name }
        return out
    }

    private static func directorySize(_ url: URL) throws -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let vals = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(vals.fileSize ?? 0)
        }
        return total
    }

    /// Reads `FluffyFlash.cache.json` in the folder, or from the sibling UUP folder when `name` ends with `-iso-build`.
    private static func resolveMetadata(root: URL, folderName: String, folderURL: URL) -> UUPCacheMetadata? {
        if let m = UUPCacheMetadata.read(from: folderURL) { return m }
        let suffix = "-iso-build"
        guard folderName.hasSuffix(suffix) else { return nil }
        let baseName = String(folderName.dropLast(suffix.count))
        let sibling = root.appendingPathComponent(baseName, isDirectory: true)
        return UUPCacheMetadata.read(from: sibling)
    }
}
