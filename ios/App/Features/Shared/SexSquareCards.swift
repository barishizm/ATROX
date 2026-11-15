import DataKit
import DesignSystem
import SwiftUI

/// Two square cards with outlined (line) icons for choosing male or female.
/// Shared by the onboarding step and the plan quiz.
struct SexSquareCards: View {
    let selection: Sex?
    let idPrefix: String
    let onSelect: (Sex) -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            square(.male, title: "onboarding.sex.male")
            square(.female, title: "onboarding.sex.female")
        }
        .frame(maxWidth: .infinity)
    }

    private func square(_ value: Sex, title: LocalizedStringKey) -> some View {
        let isSelected = selection == value
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        return Button {
            Haptics.play(.selection)
            onSelect(value)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(isSelected ? DSColor.accent : DSColor.surfaceRaised)
                                .overlay(Circle().strokeBorder(isSelected ? Color.clear : DSColor.textPrimary.opacity(0.9), lineWidth: 1))
                                .shadow(color: .black.opacity(isSelected ? 0 : 0.35), radius: 4, y: 2)
                            SexGlyph(isFemale: value == .female)
                                .stroke(DSColor.textPrimary,
                                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                                .frame(width: 52, height: 52)
                        }
                        .frame(width: 100, height: 100)
                        .accessibilityHidden(true)
                        Text(title)
                            .font(DSFont.headline)
                            .foregroundStyle(DSColor.textPrimary)
                    }
                }
                .background(DSColor.surface, in: shape)
                .overlay(shape.strokeBorder(isSelected ? DSColor.accent : DSColor.separator, lineWidth: isSelected ? 2 : 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(idPrefix)-\(value.rawValue)")
    }
}

/// Line-drawn Mars (♂) or Venus (♀) symbol inside the rect.
private struct SexGlyph: Shape {
    let isFemale: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let unit = min(rect.width, rect.height)
        let radius = unit * 0.30
        if isFemale {
            let center = CGPoint(x: rect.midX, y: rect.minY + radius + unit * 0.02)
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let stemTop = center.y + radius
            let stemBottom = rect.maxY
            path.move(to: CGPoint(x: center.x, y: stemTop))
            path.addLine(to: CGPoint(x: center.x, y: stemBottom))
            let crossY = stemTop + (stemBottom - stemTop) * 0.55
            path.move(to: CGPoint(x: center.x - unit * 0.2, y: crossY))
            path.addLine(to: CGPoint(x: center.x + unit * 0.2, y: crossY))
        } else {
            let center = CGPoint(x: rect.minX + radius + unit * 0.02, y: rect.maxY - radius - unit * 0.02)
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let edge = CGPoint(x: center.x + radius * 0.7071, y: center.y - radius * 0.7071)
            let tip = CGPoint(x: rect.maxX - unit * 0.02, y: rect.minY + unit * 0.02)
            path.move(to: edge)
            path.addLine(to: tip)
            path.move(to: CGPoint(x: tip.x - unit * 0.28, y: tip.y))
            path.addLine(to: tip)
            path.addLine(to: CGPoint(x: tip.x, y: tip.y + unit * 0.28))
        }
        return path
    }
}
