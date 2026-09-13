import Foundation

/// Represents a single Journal entry, stored as a plain Markdown file with frontmatter.
/// Maintains 100% format reciprocity with `mac/src/journal.js`.
public struct Entry: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var date: String
    public var title: String
    public var tags: [String]
    public var photos: [String]
    public var body: String

    public init(
        id: String,
        date: String = "",
        title: String = "",
        tags: [String] = [],
        photos: [String] = [],
        body: String = ""
    ) {
        self.id = id
        self.date = date.isEmpty ? Entry.localStamp() : date
        self.title = title
        self.tags = tags
        self.photos = photos
        self.body = body
    }

    // MARK: - Date & ID Helpers

    /// Formats an integer with a leading zero if needed (equivalent to pad(n)).
    private static func pad(_ n: Int) -> String {
        return String(format: "%02d", n)
    }

    /// Generates a local-time stamp (e.g. 2026-09-08T14:30:00). No timezone offset conversions.
    public static func localStamp(from date: Date = Date()) -> String {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)
        let month = pad(cal.component(.month, from: date))
        let day = pad(cal.component(.day, from: date))
        let hour = pad(cal.component(.hour, from: date))
        let minute = pad(cal.component(.minute, from: date))
        let second = pad(cal.component(.second, from: date))
        return "\(year)-\(month)-\(day)T\(hour):\(minute):\(second)"
    }

    /// A formatter pinned to the Gregorian calendar and a fixed locale.
    ///
    /// Entry timestamps are a wire format shared with the Mac, not something to
    /// render in the reader's own calendar system. Without pinning, a device set
    /// to a Buddhist or Japanese calendar writes era years — ids like
    /// `0008-09-13-142500` — and then fails to read its own files back.
    public static func fixedFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }

    /// Reads a stored `date` value, in either separator form.
    ///
    /// This app writes `2026-09-08T14:30:00`, and so does the Mac. Older iOS
    /// builds wrote a space instead, so both are accepted — a journal synced
    /// between two devices should never show a reader a raw timestamp.
    public static func parseStamp(_ raw: String) -> Date? {
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            if let date = fixedFormatter(format).date(from: raw) { return date }
        }
        return nil
    }

    /// The 'YYYY-MM-DD' key for a date, in the format entry ids use.
    public static func dayKey(from date: Date) -> String {
        return fixedFormatter("yyyy-MM-dd").string(from: date)
    }

    /// Converts a local timestamp into a sortable entry ID: 2026-09-08-143000.
    public static func id(from stamp: String) -> String {
        guard stamp.count >= 19 else { return stamp }
        let datePart = stamp.prefix(10) // YYYY-MM-DD
        let timePart = stamp.dropFirst(11).prefix(8).replacingOccurrences(of: ":", with: "") // HHmmss
        return "\(datePart)-\(timePart)"
    }

    /// Checks if a string conforms to the entry ID format: YYYY-MM-DD-HHmmss.
    public static func isValidId(_ id: String) -> Bool {
        let pattern = #"^\d{4}-\d{2}-\d{2}-\d{6}$"#
        return id.range(of: pattern, options: .regularExpression) != nil
    }

    /// Creates a new entry initialized with the current timestamp.
    public static func createNew(title: String = "", body: String = "", tags: [String] = [], photos: [String] = []) -> Entry {
        let stamp = localStamp()
        let newId = id(from: stamp)
        return Entry(id: newId, date: stamp, title: title, tags: tags, photos: photos, body: body)
    }

    // MARK: - Relative Paths

    /// The 'YYYY-MM-DD' key for calendar grouping.
    public var dayKey: String {
        return String(id.prefix(10))
    }

    /// The relative path inside the entries/ folder: YYYY/MM/<id>.md.
    public var relativePath: String {
        guard id.count >= 7 else { return "\(id).md" }
        let year = id.prefix(4)
        let month = id.dropFirst(5).prefix(2)
        return "\(year)/\(month)/\(id).md"
    }

    // MARK: - Parsing & Serialization

    /// Serializes the entry into plain text with frontmatter, matching `mac/src/journal.js:serialize`.
    public func serialize() -> String {
        let lines: [String] = [
            "---",
            "id: \(id)",
            "date: \(date)",
            "title: \(title)",
            "tags: \(tags.joined(separator: ", "))",
            "photos: \(photos.joined(separator: ", "))",
            "---",
            "",
            body,
            ""
        ]
        return lines.joined(separator: "\n")
    }

    /// Parses raw markdown text into an Entry, matching `mac/src/journal.js:parse`.
    public static func parse(_ raw: String, fallbackId: String) -> Entry {
        var entry = Entry(id: fallbackId, date: "", title: "", tags: [], photos: [], body: "")
        // `init` helpfully fills an empty date with "now". Parsing must not
        // invent one: a file with no `date:` line has no date, and the caller
        // derives it from the id — which is what the Mac does. Without this,
        // such an entry silently showed up as written today.
        entry.date = ""
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")

        guard text.hasPrefix("---\n") else {
            entry.body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return entry
        }

        // Find the closing --- after the opening
        let searchStartIndex = text.index(text.startIndex, offsetBy: 4)
        guard let endRange = text.range(of: "\n---", range: searchStartIndex..<text.endIndex) else {
            entry.body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return entry
        }

        // Extract body (after \n---)
        let bodyStartIndex = text.index(endRange.upperBound, offsetBy: 0)
        let rawBody = String(text[bodyStartIndex...])
        // Trim leading newlines and trailing whitespace
        entry.body = rawBody.replacingOccurrences(of: #"^\n+"#, with: "", options: .regularExpression)
                            .replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)

        // Parse frontmatter lines
        let frontmatter = String(text[searchStartIndex..<endRange.lowerBound])
        for line in frontmatter.components(separatedBy: "\n") {
            guard let sepIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<sepIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: sepIndex)...]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "id":
                if !value.isEmpty { entry.id = value }
            case "date":
                entry.date = value
            case "title":
                entry.title = value
            case "tags":
                entry.tags = value.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            case "photos":
                entry.photos = value.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            default:
                break
            }
        }

        return entry
    }
}
