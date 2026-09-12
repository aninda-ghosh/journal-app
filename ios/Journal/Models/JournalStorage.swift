import Foundation

/// Errors that can occur during journal storage operations.
public enum JournalStorageError: LocalizedError {
    case badId(String)
    case emptyEntry
    case invalidMediaData
    case pathEscapedRoot(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .badId(let id):
            return "Invalid entry ID: '\(id)'. Expected format YYYY-MM-DD-HHmmss."
        case .emptyEntry:
            return "An entry needs some words or a photo."
        case .invalidMediaData:
            return "No image data provided."
        case .pathEscapedRoot(let path):
            return "Security violation: '\(path)' attempted to escape the journal directory."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}

/// The local-first storage engine for Journal on iOS.
///
/// Manages plain Markdown files and photos inside an iCloud Ubiquitous Container
/// (or local Documents directory), maintaining 100% format and path reciprocity
/// with `mac/src/journal.js`.
public class JournalStorage {
    public private(set) var rootURL: URL
    public private(set) var isUsingiCloud: Bool

    public var entriesURL: URL {
        rootURL.appendingPathComponent("entries", isDirectory: true)
    }

    public var mediaURL: URL {
        rootURL.appendingPathComponent("media", isDirectory: true)
    }

    private static let bookmarkKey = "journal_scoped_folder_bookmark"
    private var isAccessingSecurityScopedResource = false

    /// Initializes storage.
    /// 1. If `customRootURL` is provided (e.g. for testing), uses it directly.
    /// 2. If a previously selected security-scoped bookmark exists (e.g. iCloud Drive/Journal), restores it.
    /// 3. Otherwise, defaults to local Documents directory.
    public init(customRootURL: URL? = nil) {
        if let custom = customRootURL {
            self.rootURL = custom.standardizedFileURL
            self.isUsingiCloud = false
        } else if let (restoredURL, _) = JournalStorage.resolveStoredBookmark() {
            self.rootURL = restoredURL.standardizedFileURL
            self.isUsingiCloud = true
            self.isAccessingSecurityScopedResource = true
        } else {
            // Local fallback for when no custom folder has been chosen yet
            let localDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let journalFolder = localDocs.appendingPathComponent("Journal", isDirectory: true)
            self.rootURL = journalFolder.standardizedFileURL
            self.isUsingiCloud = false
        }
    }

    deinit {
        if isAccessingSecurityScopedResource {
            rootURL.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Security-Scoped Bookmark Management

    /// Connects to a user-selected folder (such as a folder inside iCloud Drive).
    /// Creates and persists a security-scoped bookmark so the app can access it across restarts.
    public func setSecurityScopedFolder(url: URL) throws {
        // Release previous scoped access if any
        if isAccessingSecurityScopedResource {
            rootURL.stopAccessingSecurityScopedResource()
            isAccessingSecurityScopedResource = false
        }

        guard url.startAccessingSecurityScopedResource() else {
            throw JournalStorageError.pathEscapedRoot("Could not start accessing security-scoped resource at \(url.path)")
        }

        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: JournalStorage.bookmarkKey)
            self.rootURL = url.standardizedFileURL
            self.isUsingiCloud = url.path.contains("Mobile Documents") || url.path.contains("CloudDocs")
            self.isAccessingSecurityScopedResource = true
            try ensureDirs()
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    /// Resolves the saved security-scoped bookmark from UserDefaults.
    public static func resolveStoredBookmark() -> (url: URL, isStale: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        do {
            let resolvedURL = try URL(
                resolvingBookmarkData: data,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard resolvedURL.startAccessingSecurityScopedResource() else { return nil }

            if isStale {
                // Refresh bookmark if stale
                if let refreshed = try? resolvedURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
                }
            }
            return (resolvedURL, isStale)
        } catch {
            return nil
        }
    }

    /// Clears any saved folder bookmark, resetting storage back to local documents.
    public func resetToDefaultLocation() {
        if isAccessingSecurityScopedResource {
            rootURL.stopAccessingSecurityScopedResource()
            isAccessingSecurityScopedResource = false
        }
        UserDefaults.standard.removeObject(forKey: JournalStorage.bookmarkKey)
        let localDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.rootURL = localDocs.appendingPathComponent("Journal", isDirectory: true).standardizedFileURL
        self.isUsingiCloud = false
        try? ensureDirs()
    }

    /// User-friendly name of the current storage location.
    public var locationDisplayName: String {
        if rootURL.path.contains("CloudDocs") || rootURL.path.contains("Mobile Documents") {
            return "iCloud Drive → \(rootURL.lastPathComponent)"
        }
        return "On My iPhone → \(rootURL.lastPathComponent)"
    }

    /// Ensures `entries/` and `media/` directories exist.
    public func ensureDirs() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: entriesURL, withIntermediateDirectories: true, attributes: nil)
        try fm.createDirectory(at: mediaURL, withIntermediateDirectories: true, attributes: nil)
    }

    // MARK: - Entry Path Resolution

    public func entryURL(for id: String) -> URL {
        let year = String(id.prefix(4))
        let month = String(id.dropFirst(5).prefix(2))
        return entriesURL
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent("\(id).md", isDirectory: false)
    }

    // MARK: - Reading

    /// Recursively walks `entries/` and reads all `.md` files.
    /// Automatically handles iCloud eviction by triggering downloads on `.icloud` placeholders.
    public func readAll() throws -> [Entry] {
        try ensureDirs()
        let fm = FileManager.default
        guard fm.fileExists(atPath: entriesURL.path) else { return [] }

        var entries: [Entry] = []
        let enumerator = fm.enumerator(
            at: entriesURL,
            includingPropertiesForKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let filename = fileURL.lastPathComponent

            // Handle iCloud eviction placeholder files (e.g. .2026-09-08-143000.md.icloud)
            if filename.hasPrefix(".") && filename.hasSuffix(".icloud") {
                try? fm.startDownloadingUbiquitousItem(at: fileURL)
                continue
            }

            guard filename.hasSuffix(".md") else { continue }
            let id = String(filename.dropLast(3))

            // Read safely using NSFileCoordinator to prevent race conditions during cloud sync
            var coordinatedError: NSError?
            var entryData: Data?

            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &coordinatedError) { readURL in
                entryData = try? Data(contentsOf: readURL)
            }

            guard let data = entryData, let rawText = String(data: data, encoding: .utf8) else {
                continue
            }

            var entry = Entry.parse(rawText, fallbackId: id)
            if entry.id.isEmpty { entry.id = id }
            if entry.date.isEmpty { entry.date = "\(entry.dayKey)T00:00:00" }
            entries.append(entry)
        }

        // Sort chronologically descending (newest first, matching mac/src/journal.js)
        entries.sort { $0.id > $1.id }
        return entries
    }

    // MARK: - Writing

    /// Saves an entry to disk as a Markdown file with frontmatter.
    public func save(_ input: Entry) throws -> Entry {
        let hasBody = !input.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhotos = !input.photos.isEmpty
        guard hasBody || hasPhotos else {
            throw JournalStorageError.emptyEntry
        }

        var entry = input

        // Validate or generate ID
        if !Entry.isValidId(entry.id) {
            let now = Date()
            if entry.date.count == 10 && entry.date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                // Backdated to a day picked in the calendar — preserve current time
                let cal = Calendar.current
                let parts = entry.date.components(separatedBy: "-").compactMap { Int($0) }
                if parts.count == 3 {
                    var components = DateComponents()
                    components.year = parts[0]
                    components.month = parts[1]
                    components.day = parts[2]
                    components.hour = cal.component(.hour, from: now)
                    components.minute = cal.component(.minute, from: now)
                    components.second = cal.component(.second, from: now)
                    let backdated = cal.date(from: components) ?? now
                    entry.date = Entry.localStamp(from: backdated)
                }
            } else if entry.date.isEmpty {
                entry.date = Entry.localStamp(from: now)
            }
            entry.id = Entry.id(from: entry.date)
        }

        // Clean fields
        entry.title = entry.title.replacingOccurrences(of: #"[\r\n]+"#, with: " ", options: .regularExpression)
                                 .trimmingCharacters(in: .whitespaces)

        // Deduplicate and clean tags
        var seenTags = Set<String>()
        entry.tags = entry.tags.compactMap { tag in
            let cleaned = tag.replacingOccurrences(of: #"[,\r\n]"#, with: " ", options: .regularExpression)
                             .trimmingCharacters(in: .whitespaces)
                             .lowercased()
            guard !cleaned.isEmpty && !seenTags.contains(cleaned) else { return nil }
            seenTags.insert(cleaned)
            return cleaned
        }

        // Validate photos (must start with media/)
        entry.photos = entry.photos.compactMap { photo in
            let cleaned = photo.trimmingCharacters(in: .whitespaces)
            return cleaned.hasPrefix("media/") ? cleaned : nil
        }

        let targetURL = entryURL(for: entry.id)
        let parentDir = targetURL.deletingLastPathComponent()

        let fm = FileManager.default
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)

        let serialized = entry.serialize()
        guard let data = serialized.data(using: .utf8) else {
            throw JournalStorageError.emptyEntry
        }

        // Safe coordinated write
        var coordinatedError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(writingItemAt: targetURL, options: .forReplacing, error: &coordinatedError) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let err = writeError ?? coordinatedError {
            throw err
        }

        return entry
    }

    // MARK: - Deletion

    /// Deletes an entry's markdown file.
    /// Photos are deliberately preserved to avoid unrecoverable photo loss.
    public func remove(id: String) throws {
        guard Entry.isValidId(id) else {
            throw JournalStorageError.badId(id)
        }

        let targetURL = entryURL(for: id)
        let fm = FileManager.default
        guard fm.fileExists(atPath: targetURL.path) else { return }

        var coordinatedError: NSError?
        var deleteError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(writingItemAt: targetURL, options: .forDeleting, error: &coordinatedError) { writeURL in
            do {
                try fm.removeItem(at: writeURL)
            } catch {
                deleteError = error
            }
        }

        if let err = deleteError ?? coordinatedError {
            throw err
        }
    }

    // MARK: - Media Storage

    /// Saves full photo and thumbnail JPEGs into `media/YYYY/MM/<id>.jpg`.
    public func saveMedia(
        photoData: Data,
        thumbData: Data? = nil,
        customUUID: String? = nil
    ) throws -> (path: String, thumbPath: String?) {
        guard !photoData.isEmpty else {
            throw JournalStorageError.invalidMediaData
        }

        let now = Date()
        let cal = Calendar.current
        let year = String(format: "%04d", cal.component(.year, from: now))
        let month = String(format: "%02d", cal.component(.month, from: now))

        let targetDir = mediaURL
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)

        let fm = FileManager.default
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)

        // Unique ID format matching mac/src/journal.js: <base36time>-<hex>
        let uuid = customUUID ?? "\(Int(now.timeIntervalSince1970).description)-\(UUID().uuidString.prefix(8).lowercased())"

        let photoFilename = "\(uuid).jpg"
        let photoURL = targetDir.appendingPathComponent(photoFilename, isDirectory: false)
        try photoData.write(to: photoURL, options: .atomic)

        let relPhotoPath = "media/\(year)/\(month)/\(photoFilename)"
        var relThumbPath: String? = nil

        if let thumb = thumbData, !thumb.isEmpty {
            let thumbFilename = "\(uuid).thumb.jpg"
            let thumbURL = targetDir.appendingPathComponent(thumbFilename, isDirectory: false)
            try thumb.write(to: thumbURL, options: .atomic)
            relThumbPath = "media/\(year)/\(month)/\(thumbFilename)"
        }

        return (path: relPhotoPath, thumbPath: relThumbPath)
    }

    /// Resolves a relative `media/...` path to an absolute URL, guaranteeing that
    /// path traversal attacks (e.g. `media/../../etc/passwd`) are blocked.
    public func resolveMedia(relPath: String) -> URL? {
        let clean = relPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard clean.hasPrefix("media/") else { return nil }

        let fullURL = rootURL.appendingPathComponent(clean).standardizedFileURL

        // Ensure resolved path starts with rootURL path
        guard fullURL.path.hasPrefix(rootURL.path) else { return nil }
        return fullURL
    }
}
