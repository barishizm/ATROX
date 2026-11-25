import CoachKit
import DataKit
import Foundation
import Observation

/// One capture: a photo or a description goes to the server, the answer is edited, then saved as an entry.
@MainActor
@Observable
final class FoodAnalyzeModel {
    enum Source: Equatable {
        case photo(jpeg: Data, thumbnail: Data?)
        case text
        case barcode
        case search
    }

    enum Phase: Equatable {
        /// Waiting for the user's description (text source).
        case input
        case analyzing
        case result
        case failed(FoodAnalyzeError)
    }

    let source: Source
    private(set) var phase: Phase
    var mealName = ""
    var meal: MealType
    var eatenAt: Date
    var items: [FoodItemDetail] = []
    var hint = ""
    var description = ""
    private(set) var notes: String?
    private(set) var remaining: Int?
    private(set) var limit: Int?

    @ObservationIgnored private let service: (any FoodAnalyzeService)?
    @ObservationIgnored private let locale: String

    init(source: Source, service: (any FoodAnalyzeService)?, locale: String, now: Date = Date(), calendar: Calendar = .current) {
        self.source = source
        self.service = service
        self.locale = locale
        meal = MealType.suggested(for: now, calendar: calendar)
        eatenAt = now
        switch source {
        case .photo: phase = .analyzing
        case .text: phase = .input
        case .barcode, .search: phase = .result
        }
    }

    /// A model that starts on an already known food (barcode or search): straight to the editor.
    convenience init(food: PackagedFood, grams: Double? = nil, source: Source = .barcode, now: Date = Date()) {
        self.init(source: source, service: nil, locale: "en", now: now)
        mealName = food.name
        items = [food.item(grams: grams ?? food.defaultGrams)]
    }

    var totals: FoodEntryInput {
        FoodEntryInput(eatenAt: eatenAt, meal: meal, name: mealName, source: foodSource, items: items)
    }

    var foodSource: FoodSource {
        switch source {
        case .photo: .photo
        case .text: .text
        case .barcode: .barcode
        // Picked from the common foods list: typed in by the user, not scanned.
        case .search: .manual
        }
    }

    var canSave: Bool { !items.isEmpty && !mealName.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Starts on its own where the input is already there: a photo, or a description typed before the sheet opened.
    func startIfNeeded() async {
        switch phase {
        case .analyzing: await analyze()
        case .input where source == .text && description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2: await analyze()
        default: break
        }
    }

    /// Runs the analysis for a photo, or for the typed description.
    func analyze() async {
        guard let service else {
            phase = .failed(.unavailable)
            return
        }
        let input: FoodAnalyzeInput
        switch source {
        case .photo(let jpeg, _): input = .photo(jpeg: jpeg, hint: hint)
        case .text:
            let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else { return }
            input = .text(text)
        case .barcode, .search: return
        }
        phase = .analyzing
        do {
            let analysis = try await service.analyze(input, locale: locale)
            apply(analysis)
            phase = .result
        } catch let error as FoodAnalyzeError {
            phase = .failed(error)
        } catch {
            phase = .failed(.failed)
        }
    }

    func apply(_ analysis: FoodAnalysis) {
        mealName = analysis.mealName
        notes = analysis.notes
        remaining = analysis.remaining
        limit = analysis.limit
        items = analysis.items.map {
            FoodItemDetail(name: $0.name, grams: $0.grams, calories: $0.calories, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG)
        }
    }

    func setGrams(_ grams: Double, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = items[index].scaled(toGrams: min(max(grams, 1), 5000))
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    func backToInput() { if source == .text { phase = .input } }

    func makeInput() -> FoodEntryInput {
        var input = FoodEntryInput(eatenAt: eatenAt, meal: meal, name: mealName.trimmingCharacters(in: .whitespaces), source: foodSource, items: items)
        if case .photo(_, let thumbnail) = source { input.thumbnail = thumbnail }
        return input
    }
}
