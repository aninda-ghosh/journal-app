import Foundation

/// The entry format, checked against the shared fixtures in `spec/fixtures/`.
///
/// The Mac checks the very same files in `mac/tools/format-conformance.js`. Two
/// implementations of one on-disk format drift unless something makes them
/// answer the same questions — and every cross-device bug this app has had came
/// from exactly that drift.
///
/// Run from the repository root:
///
///   xcrun swiftc -parse-as-library ios/Tests/VerifyFormat.swift \
///     ios/Journal/Models/Entry.swift -o .cache/verify_format && .cache/verify_format
@main
struct VerifyFormat {
    struct Expected: Decodable {
        let id: String
        let date: String
        let title: String
        let tags: [String]
        let photos: [String]
        let body: String
    }

    /// Every fixture is parsed with this fallback, so a file with no `id:` line
    /// reports the id its filename would have given it.
    static let fallbackId = "2026-09-08-143000"
    static var failures = 0

    static func quoted(_ text: String) -> String {
        return "\"" + text.replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            print("  ok   \(name)")
        } else {
            failures += 1
            print(" FAIL  \(name)" + (detail.isEmpty ? "" : "  — " + detail))
        }
    }

    static func problems(expected: Expected, actual: Entry) -> [String] {
        var found: [String] = []
        if actual.id != expected.id {
            found.append("id: expected \(quoted(expected.id)), got \(quoted(actual.id))")
        }
        if actual.date != expected.date {
            found.append("date: expected \(quoted(expected.date)), got \(quoted(actual.date))")
        }
        if actual.title != expected.title {
            found.append("title: expected \(quoted(expected.title)), got \(quoted(actual.title))")
        }
        if actual.tags != expected.tags {
            found.append("tags: expected \(expected.tags), got \(actual.tags)")
        }
        if actual.photos != expected.photos {
            found.append("photos: expected \(expected.photos), got \(actual.photos)")
        }
        if actual.body != expected.body {
            found.append("body: expected \(quoted(expected.body)), got \(quoted(actual.body))")
        }
        return found
    }

    static func main() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixtures = root.appendingPathComponent("spec/fixtures", isDirectory: true)

        guard let names = try? FileManager.default.contentsOfDirectory(atPath: fixtures.path) else {
            print("❌ No fixtures at \(fixtures.path) — run this from the repository root.")
            exit(1)
        }

        let cases = names.filter { $0.hasSuffix(".md") }
                         .map { String($0.dropLast(3)) }
                         .sorted()

        print("Entry format conformance — \(cases.count) fixtures\n")

        for name in cases {
            let markdown = fixtures.appendingPathComponent(name + ".md")
            let expectation = fixtures.appendingPathComponent(name + ".json")

            guard let raw = try? String(contentsOf: markdown, encoding: .utf8),
                  let data = try? Data(contentsOf: expectation),
                  let expected = try? JSONDecoder().decode(Expected.self, from: data) else {
                check(name, false, "could not read the fixture or its expectation")
                continue
            }

            let found = problems(expected: expected, actual: Entry.parse(raw, fallbackId: fallbackId))
            check(name, found.isEmpty, found.joined(separator: "; "))
        }

        // Serialising a parsed entry and parsing it back must change nothing.
        // This is what makes an entry safe to open and re-save on either device.
        print("")
        for name in cases {
            let markdown = fixtures.appendingPathComponent(name + ".md")
            guard let raw = try? String(contentsOf: markdown, encoding: .utf8) else { continue }
            let once = Entry.parse(raw, fallbackId: fallbackId)
            let twice = Entry.parse(once.serialize(), fallbackId: fallbackId)
            check("\(name) (round trip)", once == twice,
                  once == twice ? "" : "re-parsing the serialized entry changed it")
        }

        if failures > 0 {
            print("\n❌ \(failures) failed")
            exit(1)
        }
        print("\n✓ The format matches the Mac on every fixture.")
    }
}
