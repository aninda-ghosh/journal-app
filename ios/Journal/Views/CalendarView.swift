import SwiftUI

/// The Calendar View matching `mac/src/renderer/index.html:view-calendar` and Screenshot 1.
///
/// Elements:
/// - Month title in large serif (`September 2026`)
/// - Navigation controls group alongside title: ‹, ›, and `Today` pill button
/// - Weekdays row: SUN MON TUE WED THU FRI SAT in uppercase tracked faint text
/// - 7-column grid of square day tiles with 1px border (`#e4ded5`)
/// - Day 11 (Today) highlighted with terracotta accent border (`#9a5b3d`)
/// - Daily representative photos covering tiles with legible white numbers
/// - Count badge in bottom right (e.g. `2` entries)
/// - Dynamic summary: `3 days written this month · 4 entries in all`
/// - Quiet filesystem footer with interactive `Move...` link
public struct CalendarView: View {
    @EnvironmentObject var viewModel: JournalViewModel
    @State private var displayedDate: Date = Date()
    @State private var selectedDayKey: String? = nil
    @State private var expandedEntryIds: Set<String> = []
    @State private var editingEntry: Entry? = nil
    @State private var entryToDelete: Entry? = nil
    @State private var showDeleteConfirmation: Bool = false

    public var onOpenSettings: (() -> Void)? = nil

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)

    public init(onOpenSettings: (() -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Month Header
                CalendarHeaderView(
                    title: monthYearString(from: displayedDate),
                    onPrevious: previousMonth,
                    onNext: nextMonth,
                    onToday: {
                        withAnimation(.easeInOut(duration: 0.2)) { displayedDate = Date() }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 14)

                // Weekday Row: SUN MON TUE WED THU FRI SAT
                CalendarWeekdayHeaderView()
                    .padding(.horizontal, 18)

                // 7-column Calendar Day Tiles Grid
                LazyVGrid(columns: columns, spacing: 7) {
                    ForEach(daysInMonth(), id: \.self) { date in
                        if let date = date {
                            let key = dayKey(from: date)
                            let dayEntries = viewModel.entriesByDay[key] ?? []
                            CalendarDayCell(
                                date: date,
                                isSelected: selectedDayKey == key,
                                isToday: calendar.isDateInToday(date),
                                dayEntries: dayEntries,
                                onSelect: {
                                    handleDaySelection(key: key, dayEntries: dayEntries)
                                }
                            )
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fill)
                        }
                    }
                }
                .padding(.horizontal, 18)

                // Month Summary Line (e.g. "3 days written this month · 4 entries in all")
                HStack {
                    Spacer()
                    Text(summaryString())
                        .font(.system(size: 13))
                        .foregroundColor(JournalTheme.textFaint)
                    Spacer()
                }
                .padding(.top, 6)

                // Selected Day Preview (if tapped)
                if let key = selectedDayKey, let dayEntries = viewModel.entriesByDay[key], !dayEntries.isEmpty {
                    CalendarDayPreviewCard(
                        dayKey: key,
                        entries: dayEntries,
                        expandedEntryIds: $expandedEntryIds,
                        onEdit: { editingEntry = $0 },
                        onDelete: {
                            entryToDelete = $0
                            showDeleteConfirmation = true
                        },
                        onViewInFeed: {
                            viewModel.dayFilter = key
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.selectedTab = .entries
                            }
                        }
                    )
                }

                // Divider Line
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(JournalTheme.border)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                // Quiet Storage Footer (#where in style.css)
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
        }
        .background(JournalTheme.bg)
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
                expandedEntryIds.remove(entry.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The writing is removed. Photos are kept in your media folder.")
        }
    }

    // MARK: - Actions & Helpers

    private func handleDaySelection(key: String, dayEntries: [Entry]) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedDayKey == key {
                selectedDayKey = nil
                expandedEntryIds.removeAll()
            } else if !dayEntries.isEmpty {
                selectedDayKey = key
                if let first = dayEntries.first {
                    expandedEntryIds = [first.id]
                }
            }
        }
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func dayKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func previousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: displayedDate) {
            displayedDate = newDate
            selectedDayKey = nil
            expandedEntryIds.removeAll()
        }
    }

    private func nextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: displayedDate) {
            displayedDate = newDate
            selectedDayKey = nil
            expandedEntryIds.removeAll()
        }
    }

    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedDate) else { return [] }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingPadding = firstWeekday - 1

        var days: [Date?] = Array(repeating: nil, count: leadingPadding)
        let numberOfDays = calendar.range(of: .day, in: .month, for: displayedDate)?.count ?? 30
        for dayOffset in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) {
                days.append(date)
            }
        }
        return days
    }

    private func summaryString() -> String {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedDate) else { return "" }
        let startKey = dayKey(from: monthInterval.start)
        let endKey = dayKey(from: monthInterval.end)

        let monthEntries = viewModel.entries.filter { $0.date >= startKey && $0.date < endKey }
        let uniqueDays = Set(monthEntries.map { String($0.date.prefix(10)) }).count
        let totalAll = viewModel.entries.count

        return "\(uniqueDays) days written this month · \(totalAll) entries in all"
    }
}

// MARK: - Subviews

struct CalendarHeaderView: View {
    let title: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .font(JournalTheme.serifTitle(24, weight: .bold))
                .foregroundColor(JournalTheme.text)

            HStack(spacing: 5) {
                Button(action: onPrevious) {
                    Text("‹")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(JournalTheme.textSoft)
                        .frame(width: 28, height: 28)
                        .background(JournalTheme.bgRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(JournalTheme.border, lineWidth: 1)
                        )
                }

                Button(action: onNext) {
                    Text("›")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(JournalTheme.textSoft)
                        .frame(width: 28, height: 28)
                        .background(JournalTheme.bgRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(JournalTheme.border, lineWidth: 1)
                        )
                }

                Button(action: onToday) {
                    Text("Today")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(JournalTheme.textSoft)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(JournalTheme.bgRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(JournalTheme.border, lineWidth: 1)
                        )
                }
            }

            Spacer()
        }
    }
}

struct CalendarWeekdayHeaderView: View {
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        HStack {
            ForEach(weekdays, id: \.self) { day in
                Text(day.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(JournalTheme.textFaint)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct CalendarDayCell: View {
    @EnvironmentObject var viewModel: JournalViewModel
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let dayEntries: [Entry]
    let onSelect: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        let repPhotoPath = viewModel.representativePhoto(for: dayEntries)
        let hasEntries = !dayEntries.isEmpty

        Button(action: onSelect) {
            ZStack {
                JournalTheme.bgRaised

                if let photoPath = repPhotoPath,
                   let thumbURL = viewModel.resolveThumbURL(photoRelPath: photoPath),
                   let image = UIImage(contentsOfFile: thumbURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay(Color.black.opacity(0.18))
                }

                VStack {
                    HStack {
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 12.5, weight: isToday ? .bold : .medium))
                            .foregroundColor(repPhotoPath != nil ? .white : (isToday ? JournalTheme.accent : JournalTheme.textFaint))
                            .shadow(color: repPhotoPath != nil ? Color.black.opacity(0.75) : Color.clear, radius: 2, x: 0, y: 1)
                        Spacer()
                    }
                    Spacer()

                    HStack(alignment: .bottom) {
                        if hasEntries && repPhotoPath == nil {
                            Circle()
                                .fill(JournalTheme.accent)
                                .frame(width: 5, height: 5)
                                .padding(.leading, 2)
                        }

                        Spacer()

                        if dayEntries.count > 1 {
                            Text("\(dayEntries.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.black.opacity(0.65)))
                        }
                    }
                }
                .padding(5)
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? JournalTheme.accent : (isToday ? JournalTheme.accent : JournalTheme.border),
                        lineWidth: (isSelected || isToday) ? 1.5 : 1
                    )
            )
            .shadow(color: JournalTheme.shadowColor, radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct CalendarDayPreviewCard: View {
    let dayKey: String
    let entries: [Entry]
    @Binding var expandedEntryIds: Set<String>
    var onEdit: (Entry) -> Void
    var onDelete: (Entry) -> Void
    var onViewInFeed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .center) {
                Text(formattedDayHeader(dayKey))
                    .font(JournalTheme.serifTitle(18, weight: .semibold))
                    .foregroundColor(JournalTheme.text)

                Spacer()

                Button(action: onViewInFeed) {
                    HStack(spacing: 4) {
                        Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(JournalTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(JournalTheme.accentSoft)
                    .clipShape(Capsule())
                }
            }

            // Entry Rows
            ForEach(entries) { entry in
                let isExpanded = expandedEntryIds.contains(entry.id)

                CalendarEntryRow(
                    entry: entry,
                    dayKey: dayKey,
                    isExpanded: isExpanded,
                    onToggleExpand: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            if isExpanded {
                                expandedEntryIds.remove(entry.id)
                            } else {
                                expandedEntryIds.insert(entry.id)
                            }
                        }
                    },
                    onEdit: { onEdit(entry) },
                    onDelete: { onDelete(entry) },
                    onViewInFeed: onViewInFeed
                )

                if entry.id != entries.last?.id {
                    Divider()
                        .foregroundColor(JournalTheme.border)
                        .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .journalCard()
        .padding(.horizontal, 18)
        .transition(.opacity)
    }

    private func formattedDayHeader(_ dayKey: String) -> String {
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = inFormatter.date(from: dayKey) else { return dayKey }
        let outFormatter = DateFormatter()
        outFormatter.dateFormat = "EEEE, MMMM d"
        return outFormatter.string(from: date)
    }
}

struct CalendarEntryRow: View {
    let entry: Entry
    let dayKey: String
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onViewInFeed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row
            Button(action: onToggleExpand) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let timeStr = formattedEntryTime(entry.date) {
                            Text(timeStr)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(JournalTheme.accent)
                        }

                        Text(entry.title.isEmpty ? "Untitled Entry" : entry.title)
                            .font(JournalTheme.serifTitle(16.5, weight: .medium))
                            .foregroundColor(JournalTheme.text)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    if !isExpanded && !entry.photos.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "photo")
                                .font(.system(size: 11))
                            Text("\(entry.photos.count)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(JournalTheme.textFaint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(JournalTheme.bgSunken)
                        .clipShape(Capsule())
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isExpanded ? JournalTheme.accent : JournalTheme.textFaint)
                        .frame(width: 24, height: 24)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if !isExpanded {
                if !entry.body.isEmpty {
                    Button(action: onToggleExpand) {
                        Text(entry.body)
                            .font(JournalTheme.serifProse(14))
                            .foregroundColor(JournalTheme.textSoft)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                expandedContent
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !entry.photos.isEmpty {
                EntryGalleryView(photos: entry.photos)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(JournalTheme.serifProse(15.5))
                    .foregroundColor(JournalTheme.text)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !entry.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(JournalTheme.accentSoft)
                            .foregroundColor(JournalTheme.accent)
                            .clipShape(Capsule())
                    }
                }
            }

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Edit")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(JournalTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(JournalTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                Button(action: onDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Delete")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(JournalTheme.textFaint)
                }

                Spacer()

                Button(action: onViewInFeed) {
                    HStack(spacing: 3) {
                        Text("View in feed")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(JournalTheme.textSoft)
                }
            }
            .padding(.top, 4)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func formattedEntryTime(_ rawDate: String) -> String? {
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = inFormatter.date(from: rawDate) {
            let outFormatter = DateFormatter()
            outFormatter.dateFormat = "h:mm a"
            return outFormatter.string(from: date)
        }
        return nil
    }
}
