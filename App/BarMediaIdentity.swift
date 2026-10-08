import Foundation
import CryptoKit

/// Shared bounded hashing policy for developer-local prediction and frame exports.
enum BarMediaIdentity {
    static func verify(_ mediaURL: URL, expectedSHA256: String) throws -> String {
        guard mediaURL.isFileURL, mediaURL.host?.isEmpty != false else { throw BarPredictionError.file }
        let before = try URL(fileURLWithPath: mediaURL.path).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        let limit = 500 * 1024 * 1024
        guard before.isRegularFile == true, before.contentModificationDate != nil,
              let size = before.fileSize, size > 0, size <= limit else { throw BarPredictionError.file }
        let handle = try FileHandle(forReadingFrom: mediaURL); defer { try? handle.close() }
        let began = ProcessInfo.processInfo.systemUptime
        var hash = SHA256(), count = 0
        while true {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime - began < 60 else { throw BarPredictionError.budget }
            guard let chunk = try handle.read(upToCount: 128 * 1024), !chunk.isEmpty else { break }
            count += chunk.count; guard count <= limit else { throw BarPredictionError.budget }; hash.update(data: chunk)
        }
        let after = try URL(fileURLWithPath: mediaURL.path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let digest = hash.finalize().map { String(format: "%02x", Int($0)) }.joined()
        guard count == size, after.fileSize == size, before.contentModificationDate == after.contentModificationDate,
              digest == expectedSHA256 else { throw BarPredictionError.hash }
        return digest
    }
}
