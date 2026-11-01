import Foundation

/// A named target saved on disk.
public struct FavoriteRange: Codable, Equatable, Sendable, Identifiable {
    /// Stable identifier.
    public var id: UUID
    /// Display name. Compared case-insensitively for duplicates.
    public var name: String
    /// Target text restored into the form.
    public var targetText: String
    /// Port text restored into the form.
    public var portText: String
    /// When the favorite was created.
    public var createdAt: Date

    /// Creates a favorite.
    ///
    /// - Parameters:
    ///   - id: Identifier. A new favorite uses a new UUID.
    ///   - name: Display name.
    ///   - targetText: Target text.
    ///   - portText: Port text.
    ///   - createdAt: Creation time.
    public init(id: UUID, name: String, targetText: String, portText: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.targetText = targetText
        self.portText = portText
        self.createdAt = createdAt
    }
}

/// A favorite could not be saved.
public enum FavoriteStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The trimmed name was empty.
    case emptyName
    /// Another favorite already uses this name, ignoring case.
    case duplicateName(String)

    public var description: String {
        switch self {
        case .emptyName:
            return "Enter a name for the favorite."
        case .duplicateName(let name):
            return "A favorite named \"\(name)\" already exists."
        }
    }
}

/// JSON file of favorite ranges.
public final class FileFavoriteStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    /// Creates a store.
    ///
    /// - Parameter fileURL: JSON file. A missing file loads as an empty list.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Loads favorites.
    ///
    /// - Returns: The decoded array, or an empty array when the file does not exist.
    /// - Throws: An error from `Data` or `JSONDecoder` when the file exists but is unreadable.
    public func load() throws -> [FavoriteRange] {
        try locked { try loadUnlocked() }
    }

    /// Inserts or replaces a favorite.
    ///
    /// - Parameter favorite: Favorite to write. The name is trimmed.
    /// - Throws: `FavoriteStoreError.emptyName` or `FavoriteStoreError.duplicateName`
    ///   without changing the file. Also throws when the current file cannot be read.
    public func save(_ favorite: FavoriteRange) throws {
        try locked {
            var current = try loadUnlocked()
            let trimmed = favorite.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw FavoriteStoreError.emptyName
            }
            let duplicate = current.contains { existing in
                existing.id != favorite.id
                    && existing.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            if duplicate {
                throw FavoriteStoreError.duplicateName(trimmed)
            }
            var stored = favorite
            stored.name = trimmed
            if let index = current.firstIndex(where: { $0.id == favorite.id }) {
                current[index] = stored
            } else {
                current.append(stored)
            }
            try writeUnlocked(current)
        }
    }

    /// Removes one favorite.
    ///
    /// - Parameter id: Identifier to remove. An unknown id leaves the other favorites in place.
    /// - Throws: When the file cannot be read or written.
    public func delete(id: UUID) throws {
        try locked {
            var current = try loadUnlocked()
            current.removeAll { $0.id == id }
            try writeUnlocked(current)
        }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func loadUnlocked() throws -> [FavoriteRange] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([FavoriteRange].self, from: data)
    }

    private func writeUnlocked(_ favorites: [FavoriteRange]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(favorites)
        try data.write(to: fileURL, options: .atomic)
    }
}
