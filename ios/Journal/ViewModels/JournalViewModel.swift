import Foundation
import SwiftUI
import UIKit
import Combine

/// Main application view model coordinating data flow between SwiftUI views,
/// the filesystem storage engine (`JournalStorage`), and the dictation engine.
@MainActor
public class JournalViewModel: ObservableObject {
    @Published public var entries: [Entry] = []
    @Published public var selectedTab: Tab = .calendar
    @Published public var searchQuery: String = ""
    @Published public var selectedTag: String? = nil
    @Published public var dayFilter: String? = nil // YYYY-MM-DD
    @Published public var isSaving: Bool = false
    @Published public var errorMessage: String? = nil

    // Calendar state persistence across tab switches
    @Published public var calendarDisplayedDate: Date = Date()
    @Published public var calendarSelectedDayKey: String? = nil
    @Published public var calendarExpandedEntryIds: Set<String> = []

    // Draft entry state persistence across tab switches
    public struct DraftEntry: Codable, Equatable {
        public var title: String = ""
        public var body: String = ""
        public var date: Date = Date()
        public var tags: [String] = []
        public var photoPaths: [String] = []

        public init(title: String = "", body: String = "", date: Date = Date(), tags: [String] = [], photoPaths: [String] = []) {
            self.title = title
            self.body = body
            self.date = date
            self.tags = tags
            self.photoPaths = photoPaths
        }

        public var isEmpty: Bool {
            title.isEmpty && body.isEmpty && tags.isEmpty && photoPaths.isEmpty
        }
    }

    @Published public var draft: DraftEntry = DraftEntry() {
        didSet { persistDraft() }
    }

    private static let draftKey = "journal_composer_draft"

    /// An unsaved draft should survive the app being swapped out or killed —
    /// it only lived in memory before, so a half-written entry died with the
    /// process. The Mac has kept drafts across a closed window since 1.0.
    private func persistDraft() {
        if draft.isEmpty {
            UserDefaults.standard.removeObject(forKey: JournalViewModel.draftKey)
        } else if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: JournalViewModel.draftKey)
        }
    }

    private static func loadDraft() -> DraftEntry {
        guard let data = UserDefaults.standard.data(forKey: draftKey),
              let saved = try? JSONDecoder().decode(DraftEntry.self, from: data) else {
            return DraftEntry()
        }
        return saved
    }

    public enum Tab: String, CaseIterable, Identifiable {
        case write = "Write"
        case calendar = "Calendar"
        case entries = "Entries"

        public var id: String { rawValue }
        public var iconName: String {
            switch self {
            case .write: return "square.and.pencil"
            case .calendar: return "calendar"
            case .entries: return "list.bullet.rectangle"
            }
        }
    }

    public let storage: JournalStorage
    public let dictationEngine: DictationEngine

    public init(storage: JournalStorage = JournalStorage(), dictationEngine: DictationEngine? = nil) {
        self.storage = storage
        self.dictationEngine = dictationEngine ?? DictationEngine()
        self.draft = JournalViewModel.loadDraft()
        loadEntries()
    }

    // MARK: - Data Loading

    public func loadEntries() {
        do {
            self.entries = try storage.readAll()
        } catch {
            self.errorMessage = "Failed to load entries: \(error.localizedDescription)"
        }
    }

    // MARK: - Folder & Storage Location

    public var locationDisplayName: String {
        storage.locationDisplayName
    }

    public var isUsingiCloud: Bool {
        storage.isUsingiCloud
    }

    public func selectCustomFolder(url: URL) {
        do {
            try storage.setSecurityScopedFolder(url: url)
            loadEntries()
        } catch {
            self.errorMessage = "Failed to select folder: \(error.localizedDescription)"
        }
    }

    public func resetFolderToDefault() {
        storage.resetToDefaultLocation()
        loadEntries()
    }

    // MARK: - Filtered Queries

    /// All unique tags sorted alphabetically.
    public var allTags: [String] {
        var tagsSet = Set<String>()
        for entry in entries {
            for tag in entry.tags {
                tagsSet.insert(tag)
            }
        }
        return tagsSet.sorted()
    }

    /// Entries filtered by search query, selected tag, or day filter.
    public var filteredEntries: [Entry] {
        entries.filter { entry in
            // Search query filter (matches title, body, or tags)
            if !searchQuery.isEmpty {
                let query = searchQuery.lowercased()
                let matchTitle = entry.title.lowercased().contains(query)
                let matchBody = entry.body.lowercased().contains(query)
                let matchTag = entry.tags.contains { $0.contains(query) }
                guard matchTitle || matchBody || matchTag else { return false }
            }

            // Tag filter
            if let tag = selectedTag, !entry.tags.contains(tag) {
                return false
            }

            // Day filter (YYYY-MM-DD)
            if let day = dayFilter, entry.dayKey != day {
                return false
            }

            return true
        }
    }

    /// Entries grouped by day key (YYYY-MM-DD).
    public var entriesByDay: [String: [Entry]] {
        Dictionary(grouping: entries, by: { $0.dayKey })
    }

    /// Selects the representative photo for a given calendar day.
    /// Matches the exact heuristic of `mac/src/renderer/app.js:dayPhoto`:
    /// Picks the entry with the longest body text length (longest writing = most significant moment).
    public func representativePhoto(for dayEntries: [Entry]) -> String? {
        var lead: Entry? = nil
        for entry in dayEntries {
            guard !entry.photos.isEmpty else { continue }
            guard let currentLead = lead else {
                lead = entry
                continue
            }
            let size = entry.body.trimmingCharacters(in: .whitespacesAndNewlines).count
            let best = currentLead.body.trimmingCharacters(in: .whitespacesAndNewlines).count
            if size > best || (size == best && entry.id < currentLead.id) {
                lead = entry
            }
        }
        return lead?.photos.first
    }

    // MARK: - CRUD Actions

    public func saveEntry(_ entry: Entry) async throws -> Entry {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try storage.save(entry)
            loadEntries()
            return saved
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func deleteEntry(id: String) {
        do {
            try storage.remove(id: id)
            loadEntries()
        } catch {
            errorMessage = "Failed to delete entry: \(error.localizedDescription)"
        }
    }

    /// Centre-crops, scales and saves a picked photo, returning its relative path.
    ///
    /// The decode, crop and encode run off the main actor. A 12MP photo is
    /// enough work to visibly freeze the composer if it happens on the way
    /// through the UI thread, and importing several at once made it obvious.
    public func saveMedia(data: Data) async throws -> String {
        let storage = self.storage
        return try await Task.detached(priority: .userInitiated) {
            let processed = try ImageProcessor.process(rawImageData: data)
            return try storage.saveMedia(photoData: processed.photoData)
        }.value
    }

    /// Resolves an entry's relative photo path (e.g. media/2026/09/uuid.jpg) to a file URL.
    public func resolveMediaURL(relPath: String) -> URL? {
        return storage.resolveMedia(relPath: relPath)
    }
}

// MARK: - Photo Loading

/// A small cache in front of the stored photos.
///
/// `UIImage(contentsOfFile:)` decodes the file every single time it is called,
/// and SwiftUI calls `body` often — a month of calendar tiles was decoding up to
/// 31 JPEGs on the main thread on every redraw, including twice a second while
/// the dictation clock ticked. This decodes once, off the main thread, and
/// remembers the result.
public final class PhotoStore: ObservableObject {
    public static let shared = PhotoStore()

    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var inFlight: Set<String> = []

    private init() {
        cache.countLimit = 300
    }

    /// The decoded photo, or nil while it is still being read from disk.
    /// Views observing this store are told when it arrives.
    public func image(at url: URL) -> UIImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        beginLoading(url)
        return nil
    }

    /// Forget everything — for when the journal folder itself changes.
    public func empty() {
        cache.removeAllObjects()
    }

    private func beginLoading(_ url: URL) {
        let key = url.path

        lock.lock()
        let already = inFlight.contains(key)
        if !already { inFlight.insert(key) }
        lock.unlock()
        guard !already else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let decoded = UIImage(contentsOfFile: url.path)
            if let decoded = decoded {
                self.cache.setObject(decoded, forKey: key as NSString)
            }

            self.lock.lock()
            self.inFlight.remove(key)
            self.lock.unlock()

            guard decoded != nil else { return }
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }
}
