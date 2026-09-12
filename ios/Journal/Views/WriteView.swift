import SwiftUI
import PhotosUI

/// The Write / Composer view matching `mac/src/renderer/index.html:view-write` and Screenshot 3.
///
/// Elements:
/// - Floating composer card on warm paper canvas
/// - Top row: Date selector pill (`09/11/2026 📅`) & `Dictate` pill button (`🎤 Dictate`)
/// - Title in large serif with hairline underline
/// - Body TextEditor in serif prose with "What happened today?" placeholder
/// - Dashed photo dropzone box: `Drop photos here, or click to choose`
/// - Sunken tag field: `Add tags...` with `#tag` chips
/// - Terracotta `Save entry` button (`#9a5b3d`) with shortcut hint
/// - Quiet filesystem footer with interactive `Move...` link
public struct WriteView: View {
    @EnvironmentObject var viewModel: JournalViewModel
    @StateObject private var dictation = DictationEngine()

    @State private var entryId: String? = nil
    @State private var entryDate: Date = Date()
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var tags: [String] = []
    @State private var newTagText: String = ""
    @State private var photoPaths: [String] = []

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isProcessingPhotos: Bool = false
    @Environment(\.dismiss) private var dismiss

    public var onOpenSettings: (() -> Void)? = nil

    public init(editingEntry: Entry? = nil, onOpenSettings: (() -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
        if let entry = editingEntry {
            _entryId = State(initialValue: entry.id)
            _title = State(initialValue: entry.title)
            _bodyText = State(initialValue: entry.body)
            _tags = State(initialValue: entry.tags)
            _photoPaths = State(initialValue: entry.photos)
            if let parsedDate = Self.parseDate(entry.date) {
                _entryDate = State(initialValue: parsedDate)
            }
        }
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // The Composer Card matching Screenshot 3
                VStack(alignment: .leading, spacing: 16) {
                    // Top Row: Date Pill & Dictate Button
                    HStack(alignment: .center) {
                        // Date Pill (09/11/2026 📅)
                        HStack(spacing: 6) {
                            DatePicker("", selection: $entryDate, displayedComponents: [.date])
                                .labelsHidden()
                                .datePickerStyle(.compact)
                        }

                        if entryId != nil {
                            Text("Editing")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(JournalTheme.accentSoft)
                                .foregroundColor(JournalTheme.accent)
                                .clipShape(Capsule())
                        }

                        Spacer()

                        // Dictate Pill Button (🎤 Dictate)
                        Button(action: toggleDictation) {
                            HStack(spacing: 6) {
                                Image(systemName: dictation.isRecording ? "waveform" : "mic")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(dictation.isRecording ? JournalTheme.danger : JournalTheme.textSoft)
                                    .scaleEffect(dictation.isRecording ? (1.0 + CGFloat(dictation.audioLevel) * 0.35) : 1.0)
                                    .animation(.easeInOut(duration: 0.1), value: dictation.audioLevel)

                                Text(dictationButtonTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(dictation.isRecording ? JournalTheme.danger : JournalTheme.text)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(dictation.isRecording ? JournalTheme.danger.opacity(0.12) : JournalTheme.bgRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(dictation.isRecording ? JournalTheme.danger : JournalTheme.border, lineWidth: 1)
                            )
                        }
                    }

                    // Title Input (#title in style.css)
                    TextField("Title (optional)", text: $title)
                        .font(JournalTheme.serifTitle(24, weight: .semibold))
                        .foregroundColor(JournalTheme.text)
                        .padding(.bottom, 8)
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(JournalTheme.border),
                            alignment: .bottom
                        )

                    // Markdown Body Textarea (#body in style.css)
                    ZStack(alignment: .topLeading) {
                        if bodyText.isEmpty && dictation.currentText.isEmpty {
                            Text("What happened today?")
                                .font(JournalTheme.serifProse(17))
                                .foregroundColor(JournalTheme.textFaint)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }

                        TextEditor(text: Binding(
                            get: {
                                if dictation.isRecording && !dictation.currentText.isEmpty {
                                    let separator = bodyText.isEmpty ? "" : (bodyText.hasSuffix("\n") ? "" : "\n")
                                    return bodyText.isEmpty ? dictation.currentText : "\(bodyText)\(separator)\(dictation.currentText)"
                                }
                                return bodyText
                            },
                            set: { bodyText = $0 }
                        ))
                        .font(JournalTheme.serifProse(17))
                        .foregroundColor(JournalTheme.text)
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                    }

                    // Photo Thumbnails Strip
                    if !photoPaths.isEmpty || isProcessingPhotos {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photoPaths, id: \.self) { path in
                                    if let url = viewModel.resolveThumbURL(photoRelPath: path),
                                       let image = UIImage(contentsOfFile: url.path) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 88, height: 88)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .stroke(JournalTheme.border, lineWidth: 1)
                                                )

                                            Button(action: {
                                                withAnimation { photoPaths.removeAll { $0 == path } }
                                            }) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .frame(width: 20, height: 20)
                                                    .background(Color.black.opacity(0.65))
                                                    .clipShape(Circle())
                                            }
                                            .offset(x: 4, y: -4)
                                        }
                                    }
                                }

                                if isProcessingPhotos {
                                    ProgressView()
                                        .frame(width: 88, height: 88)
                                        .background(JournalTheme.bgSunken)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                    }

                    // Dashed Photo Dropzone (.dropzone in Screenshot 3)
                    PhotosPicker(
                        selection: $selectedPhotos,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 8) {
                            Text("Drop photos here, or click to choose")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundColor(JournalTheme.accent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(JournalTheme.accentSoft.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                .foregroundColor(JournalTheme.borderStrong)
                        )
                    }
                    .onChange(of: selectedPhotos) { _, items in
                        Task { await processImportedPhotos(items: items) }
                    }

                    // Tag Field (.tag-field in Screenshot 3)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text("#\(tag)")
                                        .font(.system(size: 12.5, weight: .semibold))
                                    Button(action: { tags.removeAll { $0 == tag } }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(JournalTheme.accentSoft)
                                .foregroundColor(JournalTheme.accent)
                                .clipShape(Capsule())
                            }

                            TextField("Add tags…", text: $newTagText)
                                .font(.system(size: 13.5))
                                .foregroundColor(JournalTheme.text)
                                .onSubmit(commitTag)
                        }
                        .padding(10)
                        .background(JournalTheme.bgSunken)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(JournalTheme.border, lineWidth: 1)
                        )
                    }

                    // Bottom Row: Save button + Hint
                    HStack(alignment: .center, spacing: 12) {
                        Button(action: saveEntry) {
                            HStack(spacing: 6) {
                                if viewModel.isSaving {
                                    ProgressView().tint(.white)
                                }
                                Text(entryId == nil ? "Save entry" : "Update entry")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(JournalTheme.accent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(viewModel.isSaving || (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (dictation.isRecording ? dictation.currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : true) && photoPaths.isEmpty))

                        Text("Tap to save")
                            .font(.system(size: 12.5))
                            .foregroundColor(JournalTheme.textFaint)

                        Spacer()

                        if entryId != nil {
                            Button(action: { dismiss() }) {
                                Text("Cancel")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(JournalTheme.textSoft)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(JournalTheme.bgSunken)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(22)
                .journalCard()
                .padding(.horizontal, 18)
                .padding(.top, 14)

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
        }
        .background(JournalTheme.bg)
        .onDisappear {
            if dictation.isRecording {
                _ = dictation.stopImmediately()
            }
        }
    }

    // MARK: - Actions

    private var dictationButtonTitle: String {
        if dictation.isRecording {
            return "Listening…"
        }
        return "Dictate"
    }

    private func toggleDictation() {
        Task {
            if dictation.isRecording {
                let recognized = await dictation.stop()
                if !recognized.isEmpty {
                    let separator: String
                    if bodyText.isEmpty {
                        separator = ""
                    } else if bodyText.hasSuffix("\n") || bodyText.hasSuffix(" ") {
                        separator = ""
                    } else {
                        separator = "\n"
                    }
                    bodyText = bodyText.isEmpty ? recognized : "\(bodyText)\(separator)\(recognized)"
                }
            } else {
                do {
                    try await dictation.start()
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func commitTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        if !trimmed.isEmpty && !tags.contains(trimmed) {
            tags.append(trimmed)
            newTagText = ""
        }
    }

    private func processImportedPhotos(items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isProcessingPhotos = true
        defer { isProcessingPhotos = false }

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                do {
                    let relPath = try viewModel.saveMedia(data: data, date: entryDate)
                    if !photoPaths.contains(relPath) {
                        photoPaths.append(relPath)
                    }
                } catch {
                    viewModel.errorMessage = "Failed to process photo: \(error.localizedDescription)"
                }
            }
        }
        selectedPhotos.removeAll()
    }

    private func saveEntry() {
        // 1. Dismiss soft keyboard
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif

        // 2. Stop dictation immediately and commit whatever words were spoken
        if dictation.isRecording {
            let recognized = dictation.stopImmediately()
            if !recognized.isEmpty {
                let separator: String
                if bodyText.isEmpty {
                    separator = ""
                } else if bodyText.hasSuffix("\n") || bodyText.hasSuffix(" ") {
                    separator = ""
                } else {
                    separator = "\n"
                }
                bodyText = bodyText.isEmpty ? recognized : "\(bodyText)\(separator)\(recognized)"
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = formatter.string(from: entryDate)

        var finalId = entryId
        if finalId == nil {
            let idFormatter = DateFormatter()
            idFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
            finalId = idFormatter.string(from: entryDate)
        }

        guard let id = finalId else { return }

        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !finalTitle.isEmpty || !finalBody.isEmpty || !photoPaths.isEmpty else {
            return
        }

        let entry = Entry(
            id: id,
            date: dateString,
            title: finalTitle,
            tags: tags,
            photos: photoPaths,
            body: finalBody
        )

        // 3. Save to disk and transition view immediately without artificial delay
        Task { @MainActor in
            do {
                _ = try await viewModel.saveEntry(entry)
                if entryId != nil {
                    dismiss()
                } else {
                    title = ""
                    bodyText = ""
                    photoPaths.removeAll()
                    tags.removeAll()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = .calendar
                    }
                }
            } catch {
                viewModel.errorMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
    }

    private static func parseDate(_ str: String) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"]
        let formatter = DateFormatter()
        for fmt in formats {
            formatter.dateFormat = fmt
            if let d = formatter.date(from: str) {
                return d
            }
        }
        return nil
    }
}
