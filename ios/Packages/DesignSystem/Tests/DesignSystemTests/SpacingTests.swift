import Testing
@testable import DesignSystem

@Suite struct SpacingTests {
    @Test func scaleIsStrictlyIncreasing() {
        let scale = [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl]
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
    }
}
