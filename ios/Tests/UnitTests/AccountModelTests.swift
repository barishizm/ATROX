import DataKit
import Foundation
import Testing

@testable import ATROX

@MainActor
struct AccountModelTests {
    private final class Flag: @unchecked Sendable { var signedOut = 0 }

    private func make(service: FakeAccountService, flag: Flag, word: String = "DELETE") -> AccountModel {
        AccountModel(userId: UUID(), service: service, confirmationWord: word) { flag.signedOut += 1 }
    }

    @Test func confirmationWordIsLocalizedAndForgiving() {
        #expect(DeleteConfirmation.word(for: Locale(identifier: "tr")) == "SİL")
        #expect(DeleteConfirmation.word(for: Locale(identifier: "en_US")) == "DELETE")
        #expect(DeleteConfirmation.matches("delete", word: "DELETE"))
        #expect(DeleteConfirmation.matches("  DELETE \n", word: "DELETE"))
        #expect(DeleteConfirmation.matches("sil", word: "SİL"))
        #expect(DeleteConfirmation.matches("SIL", word: "SİL"))
        #expect(DeleteConfirmation.matches("SİL", word: "SİL"))
        #expect(!DeleteConfirmation.matches("", word: "DELETE"))
        #expect(!DeleteConfirmation.matches("DELET", word: "DELETE"))
        #expect(!DeleteConfirmation.matches("DELETE ME", word: "DELETE"))
    }

    @Test func deletionNeedsTwoStepsAndTheWord() async {
        let service = FakeAccountService()
        let flag = Flag()
        let model = make(service: service, flag: flag)
        #expect(model.deletionStep == nil)
        await model.confirmDeletion()  // not started: nothing happens
        model.beginDeletion()
        #expect(model.deletionStep == .explain)
        model.confirmationText = "DELETE"
        #expect(!model.canDelete)  // still on the explanation step
        await model.confirmDeletion()
        model.continueToConfirmation()
        #expect(!model.canDelete)  // word not typed yet
        model.confirmationText = "delet"
        #expect(!model.canDelete)
        model.confirmationText = "delete"
        #expect(model.canDelete)
        #expect(await service.deletedUsers.isEmpty)
        await model.confirmDeletion()
        #expect(await service.deletedUsers == [model.userId])
        #expect(flag.signedOut == 1)
        #expect(model.deletionStep == nil)
        #expect(model.confirmationText.isEmpty)
    }

    @Test func failedDeletionKeepsTheAccountAndTheScreen() async {
        let service = FakeAccountService(shouldFail: true)
        let flag = Flag()
        let model = make(service: service, flag: flag)
        model.beginDeletion()
        model.continueToConfirmation()
        model.confirmationText = "DELETE"
        await model.confirmDeletion()
        #expect(model.deleteFailed)
        #expect(model.deletionStep == .confirm)
        #expect(flag.signedOut == 0)
        await service.setShouldFail(false)
        await model.confirmDeletion()
        #expect(!model.deleteFailed)
        #expect(flag.signedOut == 1)
    }

    @Test func cancelResetsTheFlow() {
        let model = make(service: FakeAccountService(), flag: Flag())
        model.beginDeletion()
        model.continueToConfirmation()
        model.confirmationText = "DELETE"
        model.cancelDeletion()
        #expect(model.deletionStep == nil)
        #expect(model.confirmationText.isEmpty)
        model.beginDeletion()
        #expect(model.deletionStep == .explain)
    }

    @Test func exportProducesAFileAndReportsFailure() async throws {
        let service = FakeAccountService()
        let model = make(service: service, flag: Flag())
        await model.export()
        let url = try #require(model.exportURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
        #expect(!model.exportFailed)

        await service.setShouldFail(true)
        await model.export()
        #expect(model.exportURL == nil)
        #expect(model.exportFailed)
    }
}

struct ProfileEditModelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func input(limitations: [String] = ["knee", "note:old shoulder"]) -> ProfileInput {
        ProfileInput(
            firstName: "Ada", lastName: nil, birthDate: now.addingTimeInterval(-30 * 365 * 86_400), sex: .female,
            heightCm: 170, unitSystem: .imperial, experience: .over5Years, goal: .strength, weeklyFrequency: 4,
            equipmentAccess: .homeBarbell, limitations: limitations, locale: "tr"
        )
    }

    @MainActor private func model(_ input: ProfileInput) -> ProfileEditModel {
        ProfileEditModel(profile: input, now: { now }, calendar: calendar)
    }

    @MainActor @Test func startsFromTheProfileWithoutChanges() {
        let base = input()
        let edit = model(base)
        #expect(edit.limitations == [.knee])
        #expect(edit.limitationNote == "old shoulder")
        #expect(!edit.hasChanges)
        #expect(edit.canSave)
        #expect(edit.input() == base)
    }

    @MainActor @Test func editsComeBackAndUntouchedFieldsAreCarriedOver() {
        let edit = model(input())
        edit.firstName = "  Augusta "
        edit.lastName = "   "
        edit.goal = .fatLoss
        edit.toggle(.knee)
        edit.toggle(.hip)
        edit.setNote("")
        let result = edit.input()
        #expect(edit.hasChanges)
        #expect(result.firstName == "Augusta")
        #expect(result.lastName == nil)
        #expect(result.goal == .fatLoss)
        #expect(result.limitations == ["hip"])
        #expect(result.unitSystem == .imperial)
        #expect(result.locale == "tr")
    }

    @MainActor @Test func invalidValuesBlockSaving() {
        let edit = model(input())
        edit.firstName = " "
        #expect(!edit.canSave)
        edit.firstName = "Ada"
        edit.birthDate = now.addingTimeInterval(-10 * 365 * 86_400)
        #expect(edit.birthDateCheck == .tooYoung)
        #expect(!edit.canSave)
        edit.birthDate = now.addingTimeInterval(-30 * 365 * 86_400)
        edit.heightCm = 90
        #expect(!edit.canSave)
        edit.heightCm = 170
        edit.weeklyFrequency = 9
        #expect(!edit.canSave)
    }

    @MainActor @Test func noteIsCapped() {
        let edit = model(input(limitations: []))
        edit.setNote(String(repeating: "x", count: 500))
        #expect(edit.limitationNote.count == OnboardingRules.limitationNoteLimit)
    }
}
