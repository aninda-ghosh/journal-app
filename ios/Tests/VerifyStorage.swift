import Foundation

@main
struct VerifyStorage {
    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") {
        if actual != expected {
            print("❌ Assertion Failed: \(message)")
            print("  Expected: \(expected)")
            print("  Actual:   \(actual)")
            exit(1)
        }
    }

    static func main() {
        print("Running JournalStorage.swift validation tests...")

        // Use an isolated temporary test folder
        let tempDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".cache/test_journal_sandbox", isDirectory: true)

        // Clean any existing test artifacts
        try? FileManager.default.removeItem(at: tempDir)

        let storage = JournalStorage(customRootURL: tempDir)

        do {
            // Test 1: Ensure directories
            try storage.ensureDirs()
            assertEqual(FileManager.default.fileExists(atPath: storage.entriesURL.path), true, "entries/ directory must exist")
            assertEqual(FileManager.default.fileExists(atPath: storage.mediaURL.path), true, "media/ directory must exist")

            // Test 2: Save media
            let fakePhotoData = "fake-jpeg-photo-content".data(using: .utf8)!
            let mediaPath = try storage.saveMedia(photoData: fakePhotoData, customUUID: "test-photo-1")

            assertEqual(mediaPath.hasPrefix("media/"), true, "Photo path must start with media/")

            // Test 3: Path traversal protection
            let safeURL = storage.resolveMedia(relPath: mediaPath)
            assertEqual(safeURL != nil, true, "Valid media path must resolve")

            let maliciousURL = storage.resolveMedia(relPath: "media/../../etc/passwd")
            assertEqual(maliciousURL == nil, true, "Path traversal attempt must be blocked (return nil)")

            // Test 4: Save entry
            let entry = Entry(
                id: "2026-09-08-143000",
                date: "2026-09-08T14:30:00",
                title: "Presidio coastal trail",
                tags: ["nature", "Fog", "nature"], // Should be cleaned & deduplicated
                photos: [mediaPath],
                body: "Walking through the coastal bluffs in heavy mist."
            )

            let savedEntry = try storage.save(entry)
            assertEqual(savedEntry.tags, ["nature", "fog"], "Tags must be normalized and deduplicated")

            let expectedFilePath = storage.entryURL(for: "2026-09-08-143000").path
            assertEqual(FileManager.default.fileExists(atPath: expectedFilePath), true, "Markdown file must exist on disk")

            // Test 5: Read all entries
            let allEntries = try storage.readAll()
            assertEqual(allEntries.count, 1, "Must find exactly 1 entry")
            assertEqual(allEntries[0].id, "2026-09-08-143000", "Read entry ID must match")
            assertEqual(allEntries[0].title, "Presidio coastal trail", "Read entry title must match")
            assertEqual(allEntries[0].photos, [mediaPath], "Read entry photos must match")

            // Test 6: Deletion safety (removes .md but keeps media)
            try storage.remove(id: "2026-09-08-143000")
            let afterDelete = try storage.readAll()
            assertEqual(afterDelete.count, 0, "Entry list must be empty after deletion")
            assertEqual(FileManager.default.fileExists(atPath: expectedFilePath), false, "Markdown file must be removed")

            let resolvedPhoto = storage.resolveMedia(relPath: mediaPath)
            assertEqual(FileManager.default.fileExists(atPath: resolvedPhoto!.path), true, "Photo must be preserved on disk after entry deletion")

            print("✓ All JournalStorage tests passed successfully!")

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
        } catch {
            print("❌ Unexpected error during storage test: \(error)")
            exit(1)
        }
    }
}
