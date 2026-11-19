import CoachKit
import DataKit
import Foundation

/// Food tracking wiring of the composition root.
extension AppContainer {
    /// Open Food Facts (stateless); the barcode or search words go straight from the device.
    var packagedFoods: any PackagedFoodService { OpenFoodFactsClient() }

    /// The nutrition screen's model; nil without a user or a local store.
    func makeNutritionModel() async -> NutritionModel? {
        guard let modelContainer, let user = await currentUser() else { return nil }
        let profiles = SwiftDataProfileRepository(modelContainer: modelContainer)
        let measurements = SwiftDataMeasurementRepository(modelContainer: modelContainer)
        let userId = user.id
        return NutritionModel(userId: userId, repository: SwiftDataNutritionRepository(modelContainer: modelContainer)) {
            guard let profile = try? await profiles.profile(userId: userId)?.input else { return nil }
            let weight = try? await measurements.latest(userId: userId)?.input.weightKg
            let age = Calendar.current.dateComponents([.year], from: profile.birthDate, to: Date()).year ?? 30
            return NutritionProfile(
                sex: profile.sex, ageYears: max(age, 10), heightCm: profile.heightCm, weightKg: weight, goal: profile.goal,
                weeklyFrequency: profile.weeklyFrequency
            )
        }
    }

    /// The user's food-photo consent; one per user.
    func foodConsent() async -> FoodConsentModel? {
        guard let modelContainer, let user = await currentUser() else { return nil }
        if let existing = foodConsentState, existing.userId == user.id { return existing }
        let model = FoodConsentModel(
            service: ConsentService(repository: SwiftDataConsentRepository(modelContainer: modelContainer)), userId: user.id,
            upload: coach?.uploadAISharingConsent
        )
        foodConsentState = model
        await model.load()
        return model
    }
}
