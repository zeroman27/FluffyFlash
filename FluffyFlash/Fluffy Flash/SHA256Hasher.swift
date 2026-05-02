//
//  SHA256Hasher.swift
//  Fluffy Flash
//
//  Streaming SHA-256 for large files (ISOs, .swm chunks). Reads in 1 MiB blocks
//  via a `FileHandle` so we never load the whole file into memory.
//

import CryptoKit
import Foundation

enum SHA256Hasher {

    /// Streams the file at `url` and returns the lower-case hex SHA-256.
    /// Throws if the file is unreadable. Honours `Task.checkCancellation()` between blocks.
    static func hashFile(at url: URL, blockSize: Int = 1 << 20) async throws -> String {
        try await Task.detached(priority: .utility) { () throws -> String in
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while true {
                try Task.checkCancellation()
                guard let chunk = try handle.read(upToCount: blockSize), !chunk.isEmpty else { break }
                hasher.update(data: chunk)
            }
            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }

    /// Best-effort variant that returns `nil` instead of throwing — handy when the
    /// hash is informational and we'd rather skip it than fail the whole pipeline.
    static func hashFileBestEffort(at url: URL) async -> String? {
        do { return try await hashFile(at: url) } catch { return nil }
    }
}
