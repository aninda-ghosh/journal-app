import Foundation

@main
struct VerifyEntry {
    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") {
        if actual != expected {
            print("❌ Assertion Failed: \(message)")
            print("  Expected: \(expected)")
            print("  Actual:   \(actual)")
            exit(1)
        }
    }

    static func main() {
        print("Running Entry.swift validation tests...")

        // Test 1: ID generation and validation
        let stamp = "2026-09-08T14:30:00"
        let id = Entry.id(from: stamp)
        assertEqual(id, "2026-09-08-143000", "id(from:) must format as YYYY-MM-DD-HHmmss")
        assertEqual(Entry.isValidId(id), true, "isValidId must be true for valid format")
        assertEqual(Entry.isValidId("invalid-id"), false, "isValidId must reject invalid strings")

        // Test 2: Serialization
        let original = Entry(
            id: "2026-09-08-143000",
            date: "2026-09-08T14:30:00",
            title: "Morning walk in Presidio",
            tags: ["nature", "walking", "fog"],
            photos: ["media/2026/09/photo1.jpg", "media/2026/09/photo2.jpg"],
            body: "The fog didn't lift until noon.\nWalked along the battery ridge."
        )

        let serialized = original.serialize()
        let expectedHeader = """
        ---
        id: 2026-09-08-143000
        date: 2026-09-08T14:30:00
        title: Morning walk in Presidio
        tags: nature, walking, fog
        photos: media/2026/09/photo1.jpg, media/2026/09/photo2.jpg
        ---
        """
        assertEqual(serialized.contains(expectedHeader), true, "Serialized text must match frontmatter specification")
        assertEqual(serialized.contains("The fog didn't lift until noon."), true, "Serialized text must contain body")

        // Test 3: Parsing (Roundtrip)
        let parsed = Entry.parse(serialized, fallbackId: "fallback")
        assertEqual(parsed.id, original.id, "Parsed ID must match")
        assertEqual(parsed.date, original.date, "Parsed date must match")
        assertEqual(parsed.title, original.title, "Parsed title must match")
        assertEqual(parsed.tags, original.tags, "Parsed tags must match")
        assertEqual(parsed.photos, original.photos, "Parsed photos must match")
        assertEqual(parsed.body, original.body, "Parsed body must match")
        assertEqual(parsed, original, "Roundtrip entry must be equal to original")

        // Test 4: Paths
        assertEqual(parsed.dayKey, "2026-09-08", "dayKey must return YYYY-MM-DD")
        assertEqual(parsed.relativePath, "2026/09/2026-09-08-143000.md", "relativePath must return YYYY/MM/<id>.md")

        // Test 5: Parsing raw markdown with no frontmatter
        let plainMarkdown = "Just some quick thoughts without frontmatter."
        let plainParsed = Entry.parse(plainMarkdown, fallbackId: "2026-09-09-120000")
        assertEqual(plainParsed.id, "2026-09-09-120000", "Plain markdown must use fallbackId")
        assertEqual(plainParsed.body, plainMarkdown, "Plain markdown body must be preserved")

        print("✓ All Entry tests passed successfully!")
    }
}
