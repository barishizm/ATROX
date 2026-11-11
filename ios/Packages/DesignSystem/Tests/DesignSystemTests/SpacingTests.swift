import Testing
@testable import DesignSystem

@Suite struct SpacingTests {
    @Test func spacingScaleIsStrictlyIncreasing() {
        let scale = [Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.xxl]
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
    }

    @Test func radiusScaleIsStrictlyIncreasing() {
        let scale = [Radius.sm, Radius.md, Radius.lg, Radius.xl]
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
    }

    @Test func hitTargetsMeetHIG() {
        #expect(HitTarget.minimum >= 44)
        #expect(HitTarget.button >= HitTarget.minimum)
    }
}
