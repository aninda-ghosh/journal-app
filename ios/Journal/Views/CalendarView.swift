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
    private var displayedDate: Date {
        get { viewModel.calendarDisplayedDate }
        nonmutating set { viewModel.calendarDisplayedDate = newValue }
    }
    private var selectedDayKey: String? {
        get { viewModel.calendarSelectedDayKey }
        nonmutating set { viewModel.calendarSelectedDayKey = newValue }
    }

    public var onOpenSettings: (() -> Void)? = nil

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)

    public init(onOpenSettings: (() -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
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
                    ForEach(daysInMonth()) { day in
                        if let date = day.date {
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
                        onSelectEntry: { _ in
                            viewModel.dayFilter = key
                            viewModel.selectedTab = .entries
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .clipped()
        .background(JournalTheme.bg.ignoresSafeArea())
    }

    // MARK: - Actions & Helpers

    private func handleDaySelection(key: String, dayEntries: [Entry]) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedDayKey == key {
                selectedDayKey = nil
            } else if !dayEntries.isEmpty {
                selectedDayKey = key
            } else {
                selectedDayKey = nil
            }
        }
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func dayKey(from date: Date) -> String {
        // A key, not a label: it has to match the ids on disk exactly, so it is
        // built with the same fixed calendar the entry ids use.
        return Entry.dayKey(from: date)
    }

    private func previousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: displayedDate) {
            displayedDate = newDate
            selectedDayKey = nil
        }
    }

    private func nextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: displayedDate) {
            displayedDate = newDate
            selectedDayKey = nil
        }
    }

    struct CalendarGridDay: Identifiable {
        let id: String
        let date: Date?
    }

    private func daysInMonth() -> [CalendarGridDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedDate) else { return [] }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingPadding = firstWeekday - 1

        var days: [CalendarGridDay] = []
        for i in 0..<leadingPadding {
            days.append(CalendarGridDay(id: "pad-\(i)", date: nil))
        }

        let numberOfDays = calendar.range(of: .day, in: .month, for: displayedDate)?.count ?? 30
        for dayOffset in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) {
                let key = dayKey(from: date)
                days.append(CalendarGridDay(id: "day-\(key)", date: date))
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
    @ObservedObject private var photos = PhotoStore.shared
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
                   let photoURL = viewModel.resolveMediaURL(relPath: photoPath),
                   let image = photos.image(at: photoURL) {
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
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(JournalTheme.bgRaised)
                    .shadow(color: JournalTheme.shadowColor, radius: 1, x: 0, y: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? JournalTheme.accent : (isToday ? JournalTheme.accent : JournalTheme.border),
                        lineWidth: (isSelected || isToday) ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct CalendarDayPreviewCard: View {
    let dayKey: String
    let entries: [Entry]
    var onSelectEntry: (Entry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Day title on left, count pill on right
            HStack(alignment: .center) {
                Text(formattedDayHeader(dayKey))
                    .font(JournalTheme.serifTitle(18, weight: .semibold))
                    .foregroundColor(JournalTheme.text)

                Spacer()

                Button(action: {
                    if let first = entries.first {
                        onSelectEntry(first)
                    }
                }) {
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

            // Entry Glimpse Rows
            ForEach(entries) { entry in
                Button(action: { onSelectEntry(entry) }) {
                    CalendarEntryGlimpseRow(entry: entry)
                }
                .buttonStyle(.plain)

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
    }

    private func formattedDayHeader(_ dayKey: String) -> String {
        guard let date = Entry.parseStamp(dayKey) else { return dayKey }
        let outFormatter = DateFormatter()
        outFormatter.dateFormat = "EEEE, MMMM d"
        return outFormatter.string(from: date)
    }
}

/// Concise short glimpse row for CalendarView preview
struct CalendarEntryGlimpseRow: View {
    @EnvironmentObject var viewModel: JournalViewModel
    @ObservedObject private var photos = PhotoStore.shared
    let entry: Entry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left: Time, Title, & 2-Line Body Glimpse
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let timeStr = formattedEntryTime(entry.date) {
                        Text(timeStr)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(JournalTheme.accent)
                    }

                    if !entry.tags.isEmpty {
                        Text("#\(entry.tags[0])")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(JournalTheme.textFaint)
                    }
                }

                Text(entry.title.isEmpty ? "Untitled Entry" : entry.title)
                    .font(JournalTheme.serifTitle(16, weight: .medium))
                    .foregroundColor(JournalTheme.text)
                    .lineLimit(1)

                if !entry.body.isEmpty {
                    Text(JournalMarkdown.rendered(entry.body))
                        .font(JournalTheme.serifProse(13.5))
                        .foregroundColor(JournalTheme.textSoft)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 8)

            // Right: Photo Thumbnail (if available) + Navigation Chevron
            HStack(spacing: 8) {
                if let photoPath = entry.photos.first,
                   let photoURL = viewModel.resolveMediaURL(relPath: photoPath),
                   let image = photos.image(at: photoURL) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(JournalTheme.border, lineWidth: 1)
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(JournalTheme.textFaint)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func formattedEntryTime(_ rawDate: String) -> String? {
        // Both separator forms, fixed calendar: a Mac-written entry used to show
        // no time here at all, because only the space form was accepted.
        guard rawDate.count > 10, let date = Entry.parseStamp(rawDate) else { return nil }
        let outFormatter = DateFormatter()
        outFormatter.dateFormat = "h:mm a"
        return outFormatter.string(from: date)
    }
}
