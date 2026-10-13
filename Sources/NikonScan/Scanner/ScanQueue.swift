import Foundation

/// Serializes all hardware scanimage access so concurrent USB calls cannot collide.
actor ScanQueue {
    static let shared = ScanQueue()

    func run<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await operation()
    }
}
