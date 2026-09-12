import Foundation
import SwiftUI
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

    /// Preprocesses, center-crops, and saves media data (full + thumbnail) into the storage directory.
    public func saveMedia(data: Data, date: Date) throws -> String {
        let processed = try ImageProcessor.process(rawImageData: data)
        let (relPath, _) = try storage.saveMedia(photoData: processed.photoData, thumbData: processed.thumbData)
        return relPath
    }

    /// Resolves an entry's relative photo path (e.g. media/2026/09/uuid.jpg) to a file URL.
    public func resolveMediaURL(relPath: String) -> URL? {
        return storage.resolveMedia(relPath: relPath)
    }

    /// Resolves thumbnail URL for a given photo path.
    public func resolveThumbURL(photoRelPath: String) -> URL? {
        let thumbRel = photoRelPath.replacingOccurrences(of: #"\.[^./]+$"#, with: ".thumb.jpg", options: .regularExpression)
        return storage.resolveMedia(relPath: thumbRel) ?? storage.resolveMedia(relPath: photoRelPath)
    }
}
