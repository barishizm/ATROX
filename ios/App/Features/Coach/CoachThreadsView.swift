import CoachKit
import DesignSystem
import SwiftUI

/// Conversation list: open, rename, delete one or all (P078 deletes are permanent, also on the server).
struct CoachThreadsView: View {
    let model: CoachModel
    let close: () -> Void
    @State private var renaming: CoachThread?
    @State private var newTitle = ""
    @State private var confirmsDeleteAll = false

    var body: some View {
        Group {
            if model.threads.isEmpty {
                EmptyState(systemImage: "tray", title: "coach.threads.empty")
            } else {
                List {
                    ForEach(model.threads) { thread in
                        Button {
                            Task {
                                await model.open(thread)
                                close()
                            }
                        } label: { row(thread) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Task { await model.delete(thread) } } label: { Label("coach.threads.delete", systemImage: "trash") }
                                Button {
                                    newTitle = thread.title ?? ""
                                    renaming = thread
                                } label: { Label("coach.threads.rename", systemImage: "pencil") }
                                    .tint(DSColor.accent)
                            }
                            .accessibilityIdentifier("coach-thread-row")
                    }
                }
            }
        }
        .navigationTitle("coach.threads.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("coach.preview.close", action: close) }
            if !model.threads.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) { confirmsDeleteAll = true } label: { Text("coach.threads.deleteAll") }
                        .accessibilityIdentifier("coach-delete-all")
                }
            }
        }
        .alert("coach.threads.rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("coach.threads.name", text: $newTitle)
            Button("coach.threads.save") {
                if let thread = renaming { Task { await model.rename(thread, to: newTitle) } }
                renaming = nil
            }
            Button("coach.threads.cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("coach.threads.deleteAll.confirm", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
            Button("coach.threads.deleteAll", role: .destructive) {
                Task {
                    await model.deleteAll()
                    close()
                }
            }
        } message: {
            Text("coach.threads.deleteAll.message")
        }
    }

    private func row(_ thread: CoachThread) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            if let title = thread.title, !title.isEmpty {
                Text(verbatim: title).font(DSFont.body).foregroundStyle(DSColor.textPrimary).lineLimit(2)
            } else {
                Text("coach.threads.untitled").font(DSFont.body).foregroundStyle(DSColor.textPrimary)
            }
            Text(thread.updatedAt, style: .relative).font(DSFont.caption).foregroundStyle(DSColor.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: HitTarget.minimum, alignment: .leading)
    }
}
