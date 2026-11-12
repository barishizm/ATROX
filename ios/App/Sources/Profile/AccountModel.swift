import DataKit
import Foundation
import Observation

/// The word a user types to confirm deleting the account.
enum DeleteConfirmation {
    static func word(for locale: Locale) -> String {
        locale.language.languageCode?.identifier == "tr" ? "SİL" : "DELETE"
    }

    /// Case- and diacritic-insensitive, so "sil", "SIL" and "SİL" all work on a Turkish keyboard.
    static func matches(_ input: String, word: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: options, locale: nil)
        return !typed.isEmpty && typed == word.folding(options: options, locale: nil)
    }
}

/// Account actions: sign out, data export and the two-step account deletion.
/// Export and deletion run against `AccountService` (the Edge Functions in production, P045).
@MainActor
@Observable
final class AccountModel {
    enum DeletionStep: Equatable { case explain, confirm }

    private(set) var exportURL: URL?
    private(set) var isExporting = false
    private(set) var exportFailed = false

    /// nil while no deletion is in progress; the view shows the matching screen.
    private(set) var deletionStep: DeletionStep?
    var confirmationText = ""
    private(set) var isDeleting = false
    private(set) var deleteFailed = false

    let userId: UUID
    let confirmationWord: String
    private let service: any AccountService
    private let onDeleted: @MainActor () async -> Void

    init(
        userId: UUID, service: any AccountService, confirmationWord: String,
        onDeleted: @escaping @MainActor () async -> Void
    ) {
        self.userId = userId
        self.service = service
        self.confirmationWord = confirmationWord
        self.onDeleted = onDeleted
    }

    func export() async {
        guard !isExporting else { return }
        isExporting = true
        exportFailed = false
        exportURL = nil
        defer { isExporting = false }
        do {
            exportURL = try await service.exportData(userId: userId)
        } catch {
            Log.app.error("Data export failed: \(error)")
            exportFailed = true
        }
    }

    // MARK: Deletion

    func beginDeletion() {
        confirmationText = ""
        deleteFailed = false
        deletionStep = .explain
    }

    func continueToConfirmation() {
        guard deletionStep == .explain else { return }
        confirmationText = ""  // The word is typed on the next screen, never carried over.
        deletionStep = .confirm
    }

    func cancelDeletion() {
        guard !isDeleting else { return }
        deletionStep = nil
        confirmationText = ""
        deleteFailed = false
    }

    var canDelete: Bool {
        deletionStep == .confirm && !isDeleting && DeleteConfirmation.matches(confirmationText, word: confirmationWord)
    }

    /// Deletes the account once the confirmation word has been typed; nothing happens before that.
    func confirmDeletion() async {
        guard canDelete else { return }
        isDeleting = true
        deleteFailed = false
        defer { isDeleting = false }
        do {
            try await service.deleteAccount(userId: userId)
        } catch {
            Log.app.error("Account deletion failed: \(error)")
            deleteFailed = true
            return
        }
        deletionStep = nil
        confirmationText = ""
        await onDeleted()
    }
}
