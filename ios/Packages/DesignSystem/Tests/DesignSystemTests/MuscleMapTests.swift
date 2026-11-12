import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

@Suite struct MuscleMapTests {
    @Test func catalogHasSeventeenMusclesMatchingDatabaseVocabulary() {
        let expected: Set<String> = [
            "abdominals", "abductors", "adductors", "biceps", "calves", "chest", "forearms", "glutes", "hamstrings",
            "lats", "lower_back", "middle_back", "neck", "quadriceps", "shoulders", "traps", "triceps"
        ]
        #expect(Set(Muscle.allCases.map(\.rawValue)) == expected)
        #expect(Muscle.allCases.count == 17)
    }

    @Test func everyMuscleHasARegionOnAtLeastOneSide() {
        let drawn = Set((MuscleMapGeometry.front + MuscleMapGeometry.back).flatMap(\.muscles))
        #expect(drawn == Set(Muscle.allCases))
    }

    @Test func allRegionPathsParseAndStayInsideTheCanvas() {
        let canvas = CGRect(x: -2, y: -2, width: MuscleMapData.canvas.width + 4, height: MuscleMapData.canvas.height + 4)
        for region in MuscleMapGeometry.front + MuscleMapGeometry.back {
            #expect(!region.path.isEmpty, "\(region.id) is empty")
            #expect(canvas.contains(region.path.boundingRect), "\(region.id) leaves the canvas: \(region.path.boundingRect)")
        }
        #expect(!MuscleMapGeometry.frontOutline.isEmpty && !MuscleMapGeometry.backOutline.isEmpty)
    }

    @Test func parserHandlesAllCommandsAndRejectsGarbage() {
        let path = MuscleMapPathParser.path(from: "M 0 0 L 10 0 Q 15 5 10 10 C 8 12 2 12 0 10 Z")
        #expect(path.boundingRect.width >= 10)
        #expect(MuscleMapPathParser.path(from: "M 0 0 X 1 2").isEmpty)
        #expect(MuscleMapPathParser.path(from: "M 0").isEmpty)
    }

    @Test func intensityIsClampedAndSharedRegionsTakeTheMaximum() {
        let values: [Muscle: Double] = [.lats: 0.3, .middleBack: 0.8, .chest: 5, .neck: .nan, .traps: -1]
        #expect(MuscleMapView.intensity(of: [.lats, .middleBack], in: values) == 0.8)
        #expect(MuscleMapView.intensity(of: [.chest], in: values) == 1)
        #expect(MuscleMapView.intensity(of: [.neck], in: values) == 0)
        #expect(MuscleMapView.intensity(of: [.traps], in: values) == 0)
        #expect(MuscleMapView.intensity(of: [.biceps], in: values) == 0)
    }

    @Test func tapReportsTheStrongestMuscleOfASharedRegion() {
        #expect(MuscleMapView.tappedMuscle(in: [.lats, .middleBack], intensities: [.middleBack: 0.9, .lats: 0.2]) == .middleBack)
        #expect(MuscleMapView.tappedMuscle(in: [.lats, .middleBack], intensities: [:]) == .lats)  // tie -> first
        #expect(MuscleMapView.tappedMuscle(in: [], intensities: [:]) == nil)
    }

    @Test func exerciseHelperMakesPrimaryWinOverSecondary() {
        let map = MuscleIntensities.exercise(primary: [.chest, .shoulders], secondary: [.shoulders, .triceps])
        #expect(map[.chest] == 1 && map[.shoulders] == 1)
        #expect(map[.triceps] == MuscleIntensities.secondaryLevel)
        #expect(map[.biceps] == nil)
    }

    @Test func catalogNamesConvertAndUnknownOnesAreIgnored() {
        let map = MuscleIntensities.exercise(primaryNames: ["lower_back", "bogus"], secondaryNames: ["middle_back"])
        #expect(map == [.lowerBack: 1, .middleBack: MuscleIntensities.secondaryLevel])
    }

    @Test func heatmapNormalizesToTheLargestValueAndDropsInvalid() {
        let map = MuscleIntensities.heatmap([.chest: 20, .lats: 10, .neck: 0, .traps: -3, .calves: .infinity])
        #expect(map == [.chest: 1, .lats: 0.5])
        #expect(MuscleIntensities.heatmap([:]).isEmpty)
    }

    @Test func accessibilityTextCarriesNameAndValue() {
        let tr = Locale(identifier: "tr")
        let en = Locale(identifier: "en")
        #expect(MuscleMapView.accessibilityLabel(for: [.biceps], locale: en) == "Biceps")
        #expect(MuscleMapView.accessibilityLabel(for: [.chest], locale: tr) == "Göğüs")
        #expect(MuscleMapView.accessibilityValue(for: [.biceps], intensities: [.biceps: 0.754], locale: en) == "75%")
        #expect(
            MuscleMapView.accessibilityValue(for: [.lats, .middleBack], intensities: [.lats: 1, .middleBack: 0.4], locale: en)
                == "Lats 100%, Middle back 40%")
    }

    @Test func everyMuscleHasBothTranslations() {
        for muscle in Muscle.allCases {
            let en = muscle.localizedName(locale: Locale(identifier: "en"))
            let tr = muscle.localizedName(locale: Locale(identifier: "tr"))
            #expect(!en.isEmpty && !en.hasPrefix("muscle."), "\(muscle) en")
            #expect(!tr.isEmpty && !tr.hasPrefix("muscle."), "\(muscle) tr")
        }
    }
}
