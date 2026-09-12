import SwiftUI

/// Main container view coordinating the top navigation header and the 3 core views:
/// - Write (Composer)
/// - Calendar (Monthly visual overview - Default Home)
/// - Entries (Chronological reading feed)
///
/// Layout:
/// - Top Bar: `Journal` wordmark + icon on left, `+ New entry` terracotta button + iCloud sync on right.
/// - Body: Smooth TabView paging between Write, Calendar, and Entries.
/// - Bottom Bar: Selection tab pill at the bottom with matching theme colors, raised card states, and icons.
public struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = JournalViewModel()
    @State private var showSettings: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            JournalTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header Bar: Wordmark on Left, Actions on Right
                HStack(alignment: .center) {
                    // Wordmark + Icon
                    HStack(spacing: 7) {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                        Text("Journal")
                            .font(JournalTheme.wordmark)
                            .foregroundColor(JournalTheme.text)
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        // "New entry" terracotta button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.selectedTab = .write
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                Text("New entry")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(JournalTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }

                        // Cloud Sync & Settings Button
                        Button(action: { showSettings = true }) {
                            Image(systemName: viewModel.isUsingiCloud ? "icloud.fill" : "gearshape")
                                .font(.system(size: 16))
                                .foregroundColor(viewModel.isUsingiCloud ? JournalTheme.accent : JournalTheme.textSoft)
                                .frame(width: 28, height: 28)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background(JournalTheme.bg)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(JournalTheme.border),
                    alignment: .bottom
                )

                // Active View Body
                TabView(selection: $viewModel.selectedTab) {
                    WriteView()
                        .tag(JournalViewModel.Tab.write)

                    CalendarView(onOpenSettings: { showSettings = true })
                        .tag(JournalViewModel.Tab.calendar)

                    EntriesView(onOpenSettings: { showSettings = true })
                        .tag(JournalViewModel.Tab.entries)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Bottom Selection Tab Bar (matching theme colors, states, and styles)
                VStack(spacing: 0) {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(JournalTheme.border)

                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(JournalViewModel.Tab.allCases) { tab in
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if viewModel.selectedTab == tab && tab == .entries && viewModel.dayFilter != nil {
                                            viewModel.dayFilter = nil
                                        }
                                        viewModel.selectedTab = tab
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: tabIcon(for: tab))
                                            .font(.system(size: 12.5, weight: viewModel.selectedTab == tab ? .semibold : .medium))

                                        Text(tab.rawValue)
                                            .font(.system(size: 13, weight: viewModel.selectedTab == tab ? .semibold : .medium))
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }
                                    .foregroundColor(viewModel.selectedTab == tab ? JournalTheme.text : JournalTheme.textSoft)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(viewModel.selectedTab == tab ? JournalTheme.bgRaised : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(viewModel.selectedTab == tab ? JournalTheme.border : Color.clear, lineWidth: 1)
                                    )
                                    .shadow(color: viewModel.selectedTab == tab ? JournalTheme.shadowColor : Color.clear, radius: 2, x: 0, y: 1)
                                }
                            }
                        }
                        .padding(3)
                        .background(JournalTheme.bgSunken)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(JournalTheme.border, lineWidth: 1)
                        )
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .background(JournalTheme.bg)
                }
            }
        }
        .environmentObject(viewModel)
        .sheet(isPresented: $showSettings) {
            StorageSettingsView()
                .environmentObject(viewModel)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.loadEntries()
            }
        }
    }

    private func tabIcon(for tab: JournalViewModel.Tab) -> String {
        switch tab {
        case .write:
            return "square.and.pencil"
        case .calendar:
            return "calendar"
        case .entries:
            return "text.book.closed"
        }
    }
}
