#if DEBUG
import CoachKit
import Foundation

/// `-uitest-fake-coach`: a scripted food analysis (no network), so the capture, editor and save flow can be exercised
/// in the Simulator and in UI tests.
struct ScriptedFoodService: FoodAnalyzeService {
    func analyze(_ input: FoodAnalyzeInput, locale: String) async throws -> FoodAnalysis {
        try await Task.sleep(for: .milliseconds(700))
        let turkish = locale.hasPrefix("tr")
        return FoodAnalysis(
            mealName: turkish ? "Tavuk ve pilav" : "Chicken and rice",
            items: [
                FoodAnalysisItem(
                    name: turkish ? "Izgara tavuk göğsü" : "Grilled chicken breast",
                    grams: 150,
                    calories: 248,
                    proteinG: 46,
                    carbsG: 0,
                    fatG: 5.4,
                    confidence: 0.8
                ),
                FoodAnalysisItem(name: turkish ? "Pirinç pilavı" : "Rice", grams: 200, calories: 260, proteinG: 5, carbsG: 56, fatG: 0.5, confidence: 0.7),
                FoodAnalysisItem(name: turkish ? "Çoban salata" : "Side salad", grams: 120, calories: 45, proteinG: 1.5, carbsG: 7, fatG: 1.5, confidence: 0.6),
            ],
            notes: turkish ? "Sos miktarı tahmindir." : "Sauce amount is a guess.", remaining: 2, limit: 3
        )
    }
}
#endif
