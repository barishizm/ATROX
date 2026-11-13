@testable import DataKit
import Foundation
import Testing

private struct Fixture {
    let library: TemplateLibrary
    let records: [CatalogRecord]
    let infos: [TemplateExerciseInfo]
    let personalizer: TemplatePersonalizer
    let byId: [String: CatalogRecord]

    init() throws {
        library = try TemplateLibrary.bundled()
        records = try CatalogPackage.decode(Data(contentsOf: realCatalogURL)).exercises
        infos = records.map(TemplateExerciseInfo.init)
        personalizer = TemplatePersonalizer(catalog: infos)
        byId = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }
}

@Suite struct ProgramTemplateLoadingTests {
    @Test func allSevenTemplatesLoad() throws {
        let library = try TemplateLibrary.bundled()
        #expect(library.templates.map(\.id) == [
            "beginner-full-body-3", "upper-lower-4", "push-pull-legs-3", "push-pull-legs-6",
            "strength-5x5-3", "home-dumbbell-full-body-3", "bodyweight-3",
        ])
        #expect(library.templates.map(\.daysPerWeek) == [3, 4, 3, 6, 3, 3, 3])
        #expect(Set(library.templates.map(\.id)).count == library.templates.count)
    }

    @Test func rejectsANewerFormat() {
        let data = Data(#"{"format":9,"version":1,"templates":[]}"#.utf8)
        #expect(throws: TemplateLibrary.LoadError.unsupportedFormat(9)) { try TemplateLibrary.decode(data) }
    }

    @Test func everyTemplateIsCompleteAndInBothLanguages() throws {
        for template in try TemplateLibrary.bundled().templates {
            #expect(!template.name.en.isEmpty && !template.name.tr.isEmpty, "\(template.id) name")
            #expect(!template.audience.en.isEmpty && !template.audience.tr.isEmpty, "\(template.id) audience")
            #expect(!template.summary.en.isEmpty && !template.summary.tr.isEmpty, "\(template.id) summary")
            #expect(!template.goals.isEmpty)
            for day in template.days {
                #expect(!day.name.en.isEmpty && !day.name.tr.isEmpty && !day.exercises.isEmpty, "\(template.id)")
            }
        }
    }

    @Test func everyExerciseExistsAndRowsStayInTheRoutineLimits() throws {
        let fixture = try Fixture()
        for template in fixture.library.templates {
            for row in template.days.flatMap(\.exercises) {
                #expect(fixture.byId[row.id] != nil, "\(template.id): unknown exercise \(row.id)")
                // Same limits RoutineExerciseInput.validated() enforces.
                #expect(
                    (try? RoutineExerciseInput(
                        targetSets: row.sets, targetRepsMin: row.repsMin, targetRepsMax: row.repsMax,
                        targetRir: row.rir, restSeconds: row.restSeconds).validated()) != nil,
                    "\(template.id): \(row.id)")
            }
        }
    }

    @Test func noExerciseRepeatsWithinADay() throws {
        for template in try TemplateLibrary.bundled().templates {
            for day in template.days {
                let ids = day.exercises.map(\.id)
                #expect(Set(ids).count == ids.count, "\(template.id)/\(day.name.en)")
            }
        }
    }

    @Test func eachTemplateOnlyNeedsItsOwnEquipment() throws {
        let fixture = try Fixture()
        for template in fixture.library.templates {
            for row in template.days.flatMap(\.exercises) {
                let equipment = fixture.byId[row.id]?.equipment
                #expect(
                    EquipmentRules.allows(template.equipment, equipment: equipment),
                    "\(template.id): \(row.id) needs \(equipment ?? "none")")
            }
        }
    }

    @Test func sessionLengthIsRealistic() throws {
        for template in try TemplateLibrary.bundled().templates {
            #expect((30...75).contains(template.estimatedMinutes), "\(template.id): \(template.estimatedMinutes)")
            #expect(template.estimatedMinutes % 5 == 0)
        }
    }
}

@Suite struct ProgramTemplateBalanceTests {
    @Test func everyTemplatePullsAboutAsMuchAsItPushes() throws {
        let fixture = try Fixture()
        for template in fixture.library.templates {
            let balance = PushPullBalance(template: template) { fixture.byId[$0]?.movementPattern }
            let ratio = try #require(balance.pullToPushRatio, "\(template.id) pushes nothing")
            #expect((0.8...1.5).contains(ratio), "\(template.id): push \(balance.pushSets) pull \(balance.pullSets)")
        }
    }

    @Test func weeklyVolumePerMuscleIsReasonable() throws {
        let fixture = try Fixture()
        func muscles(_ ref: ExerciseRef) -> (primary: [String], secondary: [String])? {
            guard case .catalog(let id) = ref, let record = fixture.byId[id] else { return nil }
            return (record.primaryMuscles, record.secondaryMuscles)
        }
        for template in fixture.library.templates {
            let routine = RoutineSnapshot(template: template)
            let sets = Dictionary(
                uniqueKeysWithValues: RoutineVolume.weeklySets(in: routine, muscles: muscles).map { ($0.muscle, $0.sets) })
            for (muscle, count) in sets { #expect(count <= 36, "\(template.id): \(muscle) \(count)") }
            let back = (sets["lats"] ?? 0) + (sets["middle_back"] ?? 0)
            #expect(sets["chest", default: 0] >= 6, "\(template.id) chest")
            #expect(sets["quadriceps", default: 0] >= 6, "\(template.id) quadriceps")
            #expect(sets["hamstrings", default: 0] >= 6, "\(template.id) hamstrings")
            #expect(back >= 10, "\(template.id) back")
        }
    }
}

@Suite struct TemplatePersonalizerTests {
    @Test func fullGymKeepsEveryTemplateExactlyAsWritten() throws {
        let fixture = try Fixture()
        for template in fixture.library.templates {
            let result = fixture.personalizer.personalize(template, equipment: .fullGym)
            #expect(result.replacedCount == 0 && result.flaggedCount == 0 && result.unavailableCount == 0)
            #expect(result.days.flatMap(\.exercises).map(\.exerciseId) == template.days.flatMap(\.exercises).map(\.id))
        }
    }

    @Test func everyTemplateWorksForEveryEquipmentLevel() throws {
        let fixture = try Fixture()
        for template in fixture.library.templates {
            for access in EquipmentAccess.allCases {
                let result = fixture.personalizer.personalize(template, equipment: access)
                for row in result.days.flatMap(\.exercises) {
                    let equipment = fixture.byId[row.exerciseId]?.equipment
                    if !row.isUnavailable {
                        #expect(
                            EquipmentRules.allows(access, equipment: equipment),
                            "\(template.id)/\(access.rawValue): \(row.exerciseId)")
                    }
                }
                // Every swap keeps the number of rows and never doubles up an exercise within a day.
                for day in result.days {
                    #expect(Set(day.exercises.map(\.exerciseId)).count == day.exercises.count)
                }
            }
        }
    }

    @Test func gymTemplatesBecomeDumbbellOnlyWithSameMovementPatterns() throws {
        let fixture = try Fixture()
        let template = try #require(fixture.library.template(id: "beginner-full-body-3"))
        let result = fixture.personalizer.personalize(template, equipment: .homeDumbbell)
        #expect(result.replacedCount > 0)
        #expect(result.unavailableCount == 0, "dumbbells and bodyweight cover every pattern of this template")
        for row in result.days.flatMap(\.exercises) {
            let used = try #require(fixture.byId[row.exerciseId])
            #expect(EquipmentRules.allows(.homeDumbbell, equipment: used.equipment), Comment(rawValue: row.exerciseId))
            if let original = row.replacedId.flatMap({ fixture.byId[$0] }) {
                #expect(used.movementPattern == original.movementPattern, "\(original.id) -> \(used.id)")
                #expect(used.primaryMuscles.first == original.primaryMuscles.first, "\(original.id) -> \(used.id)")
            }
        }
    }

    @Test func bodyweightUserKeepsTheBodyweightTemplateAsWritten() throws {
        let fixture = try Fixture()
        let template = try #require(fixture.library.template(id: "bodyweight-3"))
        let result = fixture.personalizer.personalize(template, equipment: .bodyweightOnly)
        #expect(result.replacedCount == 0 && result.unavailableCount == 0)
    }

    @Test func replacementIsDeterministic() throws {
        let fixture = try Fixture()
        let template = try #require(fixture.library.template(id: "upper-lower-4"))
        let first = fixture.personalizer.personalize(template, equipment: .homeBarbell)
        let second = TemplatePersonalizer(catalog: fixture.infos.reversed()).personalize(template, equipment: .homeBarbell)
        #expect(first == second)
    }

    @Test func shoulderLimitationFlagsPressesAndSuggestsAnAlternative() throws {
        let fixture = try Fixture()
        let template = try #require(fixture.library.template(id: "upper-lower-4"))
        let result = fixture.personalizer.personalize(template, equipment: .fullGym, limitations: [.shoulder])
        let rows = result.days.flatMap(\.exercises)
        let press = try #require(rows.first { $0.exerciseId == "standing-military-press" })
        #expect(press.flaggedAreas == [.shoulder])
        let alternative = try #require(press.alternativeId)
        let info = try #require(fixture.personalizer.info(for: alternative))
        #expect(info.movementPattern == "horizontal_push", "no overhead press is shoulder-friendly, so a chest press stands in")
        #expect(LimitationRules.areas(for: info).isDisjoint(with: [.shoulder]))
        // Rows that do not load the shoulder stay unflagged.
        #expect(rows.first { $0.exerciseId == "seated-cable-rows" }?.isFlagged == false)
        // The template exercise is kept: the alternative is only a suggestion until the user takes it.
        #expect(press.exerciseId == "standing-military-press")
    }

    @Test func noLimitationsMeansNoFlags() throws {
        let fixture = try Fixture()
        for template in fixture.library.templates {
            #expect(fixture.personalizer.personalize(template, equipment: .fullGym).flaggedCount == 0)
        }
    }

    @Test func unknownExerciseIsMarkedUnavailable() throws {
        let fixture = try Fixture()
        let template = ProgramTemplate(
            id: "x", name: TemplateText(en: "X", tr: "X"), audience: TemplateText(en: "a", tr: "a"),
            summary: TemplateText(en: "s", tr: "s"), level: .beginner, goals: [.strength], equipment: .fullGym,
            days: [ProgramTemplate.Day(
                name: TemplateText(en: "D", tr: "D"),
                exercises: [ProgramTemplate.Exercise(id: "no-such-exercise", sets: 3, repsMin: 5, repsMax: 8)])])
        let result = fixture.personalizer.personalize(template, equipment: .fullGym)
        #expect(result.unavailableCount == 1)
    }
}

@Suite struct TemplateRecommenderTests {
    private func top(_ profile: TemplateProfile) throws -> [String] {
        TemplateRecommender.recommend(try TemplateLibrary.bundled().templates, for: profile).map(\.template.id)
    }

    @Test func returnsTwoDistinctTemplates() throws {
        let ids = try top(TemplateProfile(experience: .noExperience, goal: .generalHealth, weeklyFrequency: 3, equipment: .fullGym))
        #expect(ids.count == 2 && Set(ids).count == 2)
    }

    @Test func gymBeginnerWithThreeDaysGetsABeginnerTemplate() throws {
        let ids = try top(TemplateProfile(experience: .noExperience, goal: .muscleGain, weeklyFrequency: 3, equipment: .fullGym))
        #expect(ids.first == "beginner-full-body-3" || ids.first == "push-pull-legs-3")
        #expect(!ids.contains("push-pull-legs-6"))
    }

    @Test func experiencedSixDayLifterGetsPushPullLegsSix() throws {
        let ids = try top(TemplateProfile(experience: .twoToFiveYears, goal: .muscleGain, weeklyFrequency: 6, equipment: .fullGym))
        #expect(ids.first == "push-pull-legs-6")
    }

    @Test func fourDaysPointsToUpperLower() throws {
        let ids = try top(TemplateProfile(experience: .sixMonthsToTwoYears, goal: .strength, weeklyFrequency: 4, equipment: .fullGym))
        #expect(ids.first == "upper-lower-4")
    }

    @Test func homeEquipmentLimitsTheChoice() throws {
        let dumbbells = try top(TemplateProfile(experience: .noExperience, goal: .generalHealth, weeklyFrequency: 3, equipment: .homeDumbbell))
        #expect(dumbbells.first == "home-dumbbell-full-body-3")
        let bodyweight = try top(TemplateProfile(experience: .noExperience, goal: .fatLoss, weeklyFrequency: 3, equipment: .bodyweightOnly))
        #expect(bodyweight.first == "bodyweight-3")
        // A gym-only template is never first for someone without a gym.
        #expect(!bodyweight.contains("push-pull-legs-6") && !dumbbells.contains("push-pull-legs-6"))
    }

    @Test func strengthGoalFavorsTheFiveByFive() throws {
        let ids = try top(TemplateProfile(experience: .under6Months, goal: .strength, weeklyFrequency: 3, equipment: .fullGym))
        #expect(ids.contains("strength-5x5-3"))
    }
}

@Suite struct TemplateInstallerTests {
    private func makeRepo() throws -> SwiftDataRoutineRepository {
        SwiftDataRoutineRepository(modelContainer: try DataStore.inMemory(), clock: TestClock().closure)
    }

    @Test func installCreatesAnEditableCopyWithAllTargets() async throws {
        let fixture = try Fixture()
        let repo = try makeRepo()
        let template = try #require(fixture.library.template(id: "upper-lower-4"))
        let personalized = fixture.personalizer.personalize(template, equipment: .fullGym)
        let routine = try await repo.install(personalized, languageCode: "en", useAlternatives: false, userId: testUser)
        #expect(routine.name == template.name.en)
        #expect(routine.days.map(\.name) == template.days.map(\.name.en))
        #expect(routine.exerciseCount == template.exerciseCount)
        #expect(routine.positionsAreContiguous)
        let first = try #require(routine.days.first?.exercises.first)
        #expect(first.ref == .catalog("barbell-bench-press-medium-grip"))
        #expect(first.input.targetSets == 4 && first.input.targetRepsMin == 6 && first.input.targetRepsMax == 8)
        #expect(first.input.targetRir == 2 && first.input.restSeconds == 150)
        // Editing the copy leaves a second install (and the template) alone.
        try await repo.deleteExercise(id: first.id)
        let again = try await repo.install(personalized, languageCode: "tr", useAlternatives: false, userId: testUser)
        #expect(again.name == template.name.tr)
        #expect(again.exerciseCount == template.exerciseCount)
    }

    @Test func installCanTakeTheSaferAlternatives() async throws {
        let fixture = try Fixture()
        let repo = try makeRepo()
        let template = try #require(fixture.library.template(id: "upper-lower-4"))
        let personalized = fixture.personalizer.personalize(template, equipment: .fullGym, limitations: [.shoulder])
        let routine = try await repo.install(personalized, languageCode: "en", useAlternatives: true, userId: testUser)
        let used = routine.days.flatMap(\.exercises).map(\.ref)
        #expect(!used.contains(.catalog("standing-military-press")))
        #expect(routine.exerciseCount == template.exerciseCount)
    }
}

extension RoutineSnapshot {
    /// A snapshot of a template as one routine, for volume checks without a store.
    fileprivate init(template: ProgramTemplate) {
        let routineId = UUID()
        self.init(
            id: routineId, userId: testUser, name: template.name.en, notes: nil, createdAt: Date(), updatedAt: Date(),
            syncState: .pending,
            days: template.days.enumerated().map { dayIndex, day in
                let dayId = UUID()
                return RoutineDaySnapshot(
                    id: dayId, routineId: routineId, position: dayIndex, name: day.name.en,
                    exercises: day.exercises.enumerated().map { index, row in
                        RoutineExerciseSnapshot(
                            id: UUID(), routineDayId: dayId, position: index, ref: .catalog(row.id),
                            input: RoutineExerciseInput(targetSets: row.sets))
                    })
            })
    }
}
