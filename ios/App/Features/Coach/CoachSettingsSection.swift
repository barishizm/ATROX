import CoachKit
import DesignSystem
import SwiftUI

/// Settings > AI Coach (P081): withdraw or give the consent, delete conversations, see and edit the coach's memory,
/// and switch proactive comments on or off.
struct CoachSettingsSection: View {
    @Environment(AppContainer.self) private var container
    @AppStorage(CoachPreferences.proactiveKey) private var proactive = true
    @State private var consent: CoachConsentModel?
    @State private var confirmsWithdraw = false
    @State private var confirmsDelete = false
    @State private var deleted = false
    @State private var deleteFailed = false

    var body: some View {
        if container.coach != nil {
            Section {
                if let consent {
                    LabeledContent("settings.coach.sharing") {
                        Text(consent.isGranted ? "settings.coach.sharing.on" : "settings.coach.sharing.off")
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .accessibilityIdentifier("settings-coach-sharing")
                    if consent.isGranted {
                        Button("settings.coach.withdraw", role: .destructive) { confirmsWithdraw = true }
                            .accessibilityIdentifier("settings-coach-withdraw")
                    } else {
                        Button("settings.coach.grant") { Task { await consent.accept() } }
                            .accessibilityIdentifier("settings-coach-grant")
                    }
                }
                Toggle("settings.coach.proactive", isOn: $proactive).accessibilityIdentifier("settings-coach-proactive")
                NavigationLink { CoachMemoryView() } label: { Text("settings.coach.memory") }
                    .accessibilityIdentifier("settings-coach-memory")
                Button("settings.coach.deleteChats", role: .destructive) { confirmsDelete = true }
                    .accessibilityIdentifier("settings-coach-delete-chats")
                if deleted { Text("settings.coach.deleted").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary) }
                if deleteFailed { Text("settings.coach.deleteFailed").font(DSFont.footnote).foregroundStyle(DSColor.error) }
            } header: {
                Text("settings.coach.section")
            } footer: {
                Text("settings.coach.footer")
            }
            .task { consent = await container.coachConsent() }
            .confirmationDialog("settings.coach.withdraw.confirm", isPresented: $confirmsWithdraw, titleVisibility: .visible) {
                Button("settings.coach.withdraw", role: .destructive) { Task { await consent?.decline() } }
            } message: { Text("settings.coach.withdraw.message") }
            .confirmationDialog("settings.coach.deleteChats.confirm", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("settings.coach.deleteChats", role: .destructive) {
                    Task {
                        do {
                            try await container.coach?.repository.deleteAll()
                            deleted = true
                            deleteFailed = false
                        } catch {
                            deleteFailed = true
                            deleted = false
                        }
                    }
                }
            } message: { Text("settings.coach.deleteChats.message") }
        }
    }
}

/// What the coach remembers about the user (at most 20 short notes): view, edit, delete.
struct CoachMemoryView: View {
    @Environment(AppContainer.self) private var container
    @State private var notes: [CoachMemoryNote] = []
    @State private var loading = true
    @State private var failed = false
    @State private var editing: CoachMemoryNote?
    @State private var draft = ""

    var body: some View {
        List {
            if loading {
                ProgressView()
            } else if failed {
                Text("coach.memory.failed").foregroundStyle(DSColor.error)
            } else if notes.isEmpty {
                Text("coach.memory.empty").foregroundStyle(DSColor.textSecondary).accessibilityIdentifier("coach-memory-empty")
            }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: note.note)
                    Text(note.source == "user" ? "coach.memory.source.user" : "coach.memory.source.coach")
                        .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                }
                .swipeActions {
                    Button("coach.memory.delete", role: .destructive) { Task { await delete(note) } }
                    Button("coach.memory.edit") {
                        draft = note.note
                        editing = note
                    }.tint(DSColor.accent)
                }
                .listRowBackground(DSColor.surface)
            }
            if !notes.isEmpty {
                Text("coach.memory.footer").font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(DSColor.background)
        .navigationTitle("coach.memory.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("coach.memory.edit", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("coach.memory.edit", text: $draft)
            Button("coach.memory.save") { Task { await save() } }
            Button("common.cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("coach-memory")
    }

    private func load() async {
        defer { loading = false }
        guard let repository = container.coach?.repository else { return }
        do {
            notes = try await repository.memory()
            failed = false
        } catch {
            failed = true
        }
    }

    private func delete(_ note: CoachMemoryNote) async {
        guard (try? await container.coach?.repository.deleteMemory(id: note.id)) != nil else { return }
        notes.removeAll { $0.id == note.id }
    }

    private func save() async {
        guard let note = editing else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, (try? await container.coach?.repository.editMemory(id: note.id, note: text)) != nil else { return }
        await load()
    }
}
