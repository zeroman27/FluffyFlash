//
//  VolumeBytes.swift
//  Wist
//

import Darwin
import Foundation

enum VolumeBytes: Sendable {
    /// Free space on the volume that contains `url` (usually the volume root).
    static func freeBytes(onVolumeContaining url: URL) -> UInt64? {
        var st = statfs()
        let path = url.path
        guard statfs(path, &st) == 0 else { return nil }
        return UInt64(st.f_bavail) * UInt64(st.f_bsize)
    }

    /// Tree size in bytes (`du -sk`: value is KiB × 1024).
    static func directoryUsageBytesShell(at url: URL) -> UInt64? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let s = String(data: data, encoding: .utf8) else { return nil }
            let first = s.split(whereSeparator: \.isWhitespace).first
            guard let kb = first.flatMap({ UInt64($0) }) else { return nil }
            return kb * 1024
        } catch {
            return nil
        }
    }
}
