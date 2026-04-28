//
//  MacOSCache.swift
//  Wist
//

import Foundation

enum MacOSCache: Sendable {
    enum ArtefactKind: String, Sendable {
        case installerApp
        case dmg
        case iso
        case pkg
        case ipsw
        case other
    }

    struct Artefact: Identifiable, Hashable, Sendable {
        var id: URL { url }
        let url: URL
        let kind: ArtefactKind
        let fileSizeBytes: Int64?
        let modifiedAt: Date?
    }

    static var rootDirectory: URL {
        WistCache.cachesRootDirectory.appendingPathComponent("macOS", isDirectory: true)
    }

    static func listArtefacts() -> [Artefact] {
        let fm = FileManager.default
        let root = rootDirectory
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            return []
        }

        var out: [Artefact] = []
        out.reserveCapacity(urls.count)
        for u in urls {
            let rv = try? u.resourceValues(forKeys: keys)
            if rv?.isDirectory == true, u.pathExtension.lowercased() == "app" {
                // Treat *.app bundles as a single artefact (size is expensive to compute; skip for v1).
                out.append(
                    Artefact(
                        url: u,
                        kind: .installerApp,
                        fileSizeBytes: nil,
                        modifiedAt: rv?.contentModificationDate
                    )
                )
                continue
            }

            if rv?.isDirectory == true { continue }

            let ext = u.pathExtension.lowercased()
            let kind: ArtefactKind = switch ext {
            case "dmg": .dmg
            case "iso": .iso
            case "pkg": .pkg
            case "ipsw": .ipsw
            default: .other
            }

            out.append(
                Artefact(
                    url: u,
                    kind: kind,
                    fileSizeBytes: rv?.fileSize.map { Int64($0) },
                    modifiedAt: rv?.contentModificationDate
                )
            )
        }

        out.sort {
            ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
        }
        return out
    }
}

