import SwiftUI

/// Settings sheet allowing the user to select an iCloud Drive folder for free cross-device sync.
public struct StorageSettingsView: View {
    @EnvironmentObject var viewModel: JournalViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showFolderPicker: Bool = false
    @State private var showResetAlert: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // Brand Header
                Section {
                    HStack(spacing: 16) {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Journal")
                                .font(JournalTheme.wordmark)
                                .foregroundColor(JournalTheme.text)
                            Text("Mac & iPhone Companion")
                                .font(.caption)
                                .foregroundColor(JournalTheme.textSoft)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Current Status Section
                Section(header: Text("Storage Location")) {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.isUsingiCloud ? "icloud.fill" : "iphone")
                            .font(.title2)
                            .foregroundColor(viewModel.isUsingiCloud ? .accentColor : .secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(viewModel.locationDisplayName)
                                .font(.headline)
                            Text(viewModel.isUsingiCloud ? "Syncing with iCloud Drive" : "Stored locally on this device")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Sync Action Section
                Section(header: Text("Sync with Mac (100% Free)")) {
                    Button(action: { showFolderPicker = true }) {
                        HStack {
                            Image(systemName: "folder.badge.gearshape")
                            Text(viewModel.isUsingiCloud ? "Change iCloud Folder…" : "Select Folder in iCloud Drive…")
                                .fontWeight(.medium)
                        }
                    }

                    if viewModel.isUsingiCloud {
                        Button(role: .destructive, action: { showResetAlert = true }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Local Storage")
                            }
                        }
                    }
                }

                // Instructions Section
                Section(header: Text("How Free iCloud Sync Works")) {
                    VStack(alignment: .leading, spacing: 10) {
                        instructionRow(
                            step: "1",
                            text: "Tap 'Select Folder in iCloud Drive…' and pick or create a folder named 'Journal'."
                        )
                        instructionRow(
                            step: "2",
                            text: "On your Mac, open the Journal menu → 'Move Journal Folder…' and select the same iCloud Drive folder."
                        )
                        instructionRow(
                            step: "3",
                            text: "Your entries and photos now sync seamlessly between iPhone and Mac with zero subscriptions or fees."
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Storage & Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let selectedURL = urls.first {
                        viewModel.selectCustomFolder(url: selectedURL)
                    }
                case .failure(let error):
                    viewModel.errorMessage = "Failed to select folder: \(error.localizedDescription)"
                }
            }
            .alert("Reset to Local Storage?", isPresented: $showResetAlert) {
                Button("Reset", role: .destructive) {
                    viewModel.resetFolderToDefault()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your journal files will remain safely in iCloud Drive, but this iPhone app will switch back to local storage.")
            }
        }
    }

    private func instructionRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(step)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
