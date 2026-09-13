import SwiftUI

/// The Entries List View matching `mac/src/renderer/index.html:view-entries` and Screenshot 2.
///
/// Elements:
/// - Top search pill with magnifying glass
/// - Horizontal filterable tag chips
/// - Chronological `.entry` cards matching Screenshot 2:
///   - Uppercase tracked date caption: e.g. `FRIDAY, SEPTEMBER 11, 2026 · 5:35 PM`
///   - Right-aligned `Edit` and `Delete` text actions
///   - Full-width photo preview matching Grand Canyon card in Screenshot 2
///   - Book-like serif body prose with relaxed line spacing
/// - Quiet filesystem footer with interactive `Move...` link
public struct EntriesView: View {
    @EnvironmentObject var viewModel: JournalViewModel
    @State private var editingEntry: Entry? = nil
    @State private var entryToDelete: Entry? = nil
    @State private var showDeleteConfirmation: Bool = false

    public var onOpenSettings: (() -> Void)? = nil

    public init(onOpenSettings: (() -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Search Pill Input matching Screenshot 2
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(JournalTheme.textFaint)

                    TextField("Search entries", text: $viewModel.searchQuery)
                        .font(.system(size: 14))
                        .foregroundColor(JournalTheme.text)

                    if !viewModel.searchQuery.isEmpty {
                        Button(action: { viewModel.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(JournalTheme.textFaint)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(JournalTheme.bgRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(JournalTheme.border, lineWidth: 1)
                )
                .padding(.horizontal, 18)
                // Active Day Filter Chip (if selected from Calendar)
                if let day = viewModel.dayFilter {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(JournalTheme.accent)

                        Text(formattedDayHeader(day))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(JournalTheme.text)

                        Spacer()

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.dayFilter = nil
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text("Show all")
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(JournalTheme.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(JournalTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 18)
                }

                // Tag Filter Strip
                if !viewModel.allTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) { viewModel.selectedTag = nil }
                            }) {
                                Text("All")
                                    .font(.system(size: 13, weight: viewModel.selectedTag == nil ? .bold : .medium))
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 5)
                                    .background(viewModel.selectedTag == nil ? JournalTheme.accent : JournalTheme.bgSunken)
                                    .foregroundColor(viewModel.selectedTag == nil ? .white : JournalTheme.textSoft)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(viewModel.selectedTag == nil ? JournalTheme.accent : JournalTheme.border, lineWidth: 1)
                                    )
                            }

                            ForEach(viewModel.allTags, id: \.self) { tag in
                                let isSelected = viewModel.selectedTag == tag
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        viewModel.selectedTag = isSelected ? nil : tag
                                    }
                                }) {
                                    Text("#\(tag)")
                                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 5)
                                        .background(isSelected ? JournalTheme.accent : JournalTheme.bgSunken)
                                        .foregroundColor(isSelected ? .white : JournalTheme.textSoft)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(isSelected ? JournalTheme.accent : JournalTheme.border, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                    .clipped()
                }

                // Feed Cards
                if viewModel.filteredEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .opacity(0.85)

                        Text(viewModel.entries.isEmpty ? "A quiet room for writing." : "No matching entries.")
                            .font(JournalTheme.serifTitle(22, weight: .medium))
                            .foregroundColor(JournalTheme.textSoft)

                        Text(viewModel.entries.isEmpty ? "Your words and photos stay on your device and in your iCloud Drive." : "Try adjusting your search or filter tags.")
                            .font(.system(size: 14))
                            .foregroundColor(JournalTheme.textFaint)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 60)
                } else {
                    LazyVStack(spacing: 18) {
                        ForEach(viewModel.filteredEntries) { entry in
                            EntryCard(
                                entry: entry,
                                onEdit: { editingEntry = entry },
                                onDelete: {
                                    entryToDelete = entry
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                }

                // Divider Line
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(JournalTheme.border)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                // Quiet Storage Footer (#where)
                HStack(spacing: 6) {
                    Spacer()
                    Text("Your entries and photos are plain files in")
                        .font(.system(size: 12))
                        .foregroundColor(JournalTheme.textFaint)
                    Text(viewModel.locationDisplayName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(JournalTheme.textSoft)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button(action: { onOpenSettings?() }) {
                        Text("Move…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(JournalTheme.accent)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .clipped()
        .background(JournalTheme.bg.ignoresSafeArea())
        .refreshable {
            viewModel.loadEntries()
        }
        .sheet(item: $editingEntry) { entry in
            WriteView(editingEntry: entry)
                .environmentObject(viewModel)
        }
        .confirmationDialog(
            "Delete Entry?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible,
            presenting: entryToDelete
        ) { entry in
            Button("Delete Entry", role: .destructive) {
                viewModel.deleteEntry(id: entry.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The writing is removed. Photos are kept in your media folder.")
        }
    }

    private func formattedDayHeader(_ dayKey: String) -> String {
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = inFormatter.date(from: dayKey) else { return dayKey }
        let outFormatter = DateFormatter()
        outFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        return outFormatter.string(from: date)
    }
}

/// Card component rendering an entry in the feed (.entry in style.css and Screenshot 2).
struct EntryCard: View {
    @EnvironmentObject var viewModel: JournalViewModel
    let entry: Entry
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Line: "FRIDAY, SEPTEMBER 11, 2026 · 5:35 PM" and [Edit] [Delete]
            HStack(alignment: .firstTextBaseline) {
                Text(formattedDate(entry.date))
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(JournalTheme.textFaint)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: { onEdit?() }) {
                        Text("Edit")
                            .font(.system(size: 12))
                            .foregroundColor(JournalTheme.textFaint)
                    }

                    Button(action: { onDelete?() }) {
                        Text("Delete")
                            .font(.system(size: 12))
                            .foregroundColor(JournalTheme.textFaint)
                    }
                }
            }

            // Title in serif (.entry h3)
            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(JournalTheme.serifTitle(21, weight: .semibold))
                    .foregroundColor(JournalTheme.text)
            }

            // Photo Gallery (Full width matching Grand Canyon photo in Screenshot 2)
            if !entry.photos.isEmpty {
                EntryGalleryView(photos: entry.photos)
            }

            // Body text in book-like serif prose (.prose in style.css)
            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(JournalTheme.serifProse(16.5))
                    .foregroundColor(JournalTheme.text)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Tags Strip
            if !entry.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(JournalTheme.accentSoft)
                            .foregroundColor(JournalTheme.accent)
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .journalCard()
    }

    private func formattedDate(_ rawDate: String) -> String {
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = inFormatter.date(from: rawDate) {
            let outFormatter = DateFormatter()
            outFormatter.dateFormat = "EEEE, MMMM d, yyyy · h:mm a"
            return outFormatter.string(from: date).uppercased()
        }

        // Try date-only format
        inFormatter.dateFormat = "yyyy-MM-dd"
        if let date = inFormatter.date(from: rawDate) {
            let outFormatter = DateFormatter()
            outFormatter.dateFormat = "EEEE, MMMM d, yyyy"
            return outFormatter.string(from: date).uppercased()
        }

        return rawDate.uppercased()
    }
}

/// Gallery layout matching `.gallery` in style.css.
struct EntryGalleryView: View {
    @EnvironmentObject var viewModel: JournalViewModel
    let photos: [String]

    var body: some View {
        Group {
            if photos.count == 1 {
                // Single photo: Full width inside card (Grand Canyon layout in Screenshot 2)
                if let url = viewModel.resolveMediaURL(relPath: photos[0]),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(JournalTheme.border, lineWidth: 1)
                        )
                }
            } else if photos.count == 2 {
                // Two photos: 2-column split
                HStack(spacing: 6) {
                    ForEach(photos, id: \.self) { path in
                        if let url = viewModel.resolveThumbURL(photoRelPath: path),
                           let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(JournalTheme.border, lineWidth: 1)
                                )
                        }
                    }
                }
            } else {
                // 3 or more photos: 3-column grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(photos.prefix(6), id: \.self) { path in
                        if let url = viewModel.resolveThumbURL(photoRelPath: path),
                           let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(JournalTheme.border, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
    }
}
