import Foundation

/// JSON in the app's own Application Support folder, inside the sandbox container.
/// Anything unreadable, missing, or malformed loads as nil; only saving can throw.
actor FileMessageStore: MessageStoring {
    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        fileURL = base.appendingPathComponent("drafts.json")
    }

    func load() async -> SavedDrafts? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SavedDrafts.self, from: data)
    }

    func save(_ drafts: SavedDrafts) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(drafts).write(to: fileURL, options: .atomic)
    }

    private static var defaultDirectory: URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("LedFan", isDirectory: true)
    }
}

/// Keeps drafts for the life of the process. Used for previews and UI tests, which must
/// not read or write the real container.
actor TransientMessageStore: MessageStoring {
    private var drafts: SavedDrafts?

    init(initial: SavedDrafts? = .starter) {
        drafts = initial
    }

    func load() async -> SavedDrafts? { drafts }

    func save(_ drafts: SavedDrafts) async throws { self.drafts = drafts }
}
