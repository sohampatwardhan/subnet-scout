import Foundation
import Testing
@testable import ScannerCore

@Test func favoriteRoundTripKeepsTheFields() throws {
    // Requirements 10.1 and 10.5
    let store = FileFavoriteStore(fileURL: temporaryFavoritesURL())
    let favorite = FavoriteRange(
        id: UUID(),
        name: "Lab",
        targetText: "10.0.0.0/24",
        portText: "22,80",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try store.save(favorite)
    let loaded = try store.load()
    #expect(loaded.count == 1)
    #expect(loaded[0].name == "Lab")
    #expect(loaded[0].targetText == "10.0.0.0/24")
    #expect(loaded[0].portText == "22,80")
}

@Test func emptyAndDuplicateNamesDoNotChangeTheFile() throws {
    // Requirement 10.3
    let store = FileFavoriteStore(fileURL: temporaryFavoritesURL())
    let first = FavoriteRange(
        id: UUID(),
        name: "Lab",
        targetText: "10.0.0.0/24",
        portText: "",
        createdAt: Date()
    )
    try store.save(first)
    #expect(throws: FavoriteStoreError.emptyName) {
        try store.save(FavoriteRange(id: UUID(), name: "  ", targetText: "10.0.0.1", portText: "", createdAt: Date()))
    }
    #expect(throws: FavoriteStoreError.duplicateName("lab")) {
        try store.save(FavoriteRange(id: UUID(), name: "lab", targetText: "10.0.0.2", portText: "", createdAt: Date()))
    }
    let loaded = try store.load()
    #expect(loaded.map(\.id) == [first.id])
}

@Test func deleteRemovesOnlyThatFavorite() throws {
    // Requirement 10.4
    let store = FileFavoriteStore(fileURL: temporaryFavoritesURL())
    let kept = FavoriteRange(id: UUID(), name: "Home", targetText: "192.168.1.0/24", portText: "", createdAt: Date())
    let gone = FavoriteRange(id: UUID(), name: "Lab", targetText: "10.0.0.0/24", portText: "", createdAt: Date())
    try store.save(kept)
    try store.save(gone)
    try store.delete(id: gone.id)
    try store.delete(id: UUID())
    let loaded = try store.load()
    #expect(loaded.map(\.id) == [kept.id])
}

@Test func missingFavoriteFileLoadsEmpty() throws {
    // Requirement 10.5
    let store = FileFavoriteStore(fileURL: temporaryFavoritesURL())
    #expect(try store.load().isEmpty)
}

private func temporaryFavoritesURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("subnet-scout-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("favorites.json")
}
