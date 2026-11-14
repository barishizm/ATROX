import DesignSystem
import StrengthKit
import SwiftUI

/// The card itself (P084): dark, one accent, brand mark, an "estimated score" note that stays readable at story size.
/// Laid out at the export size (1080 wide), so what the user previews scaled down is exactly what is shared.
struct ShareCardView: View {
    let content: ShareCardContent
    let options: ShareCardOptions

    private var size: CGSize { options.format.size }
    private var isStory: Bool { options.format == .story }
    private var ink: Color { .white }
    private var muted: Color { Color.white.opacity(0.68) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.07), Color(red: 0.11, green: 0.09, blue: 0.10)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [DSColor.accent.opacity(0.28), .clear], center: .top, startRadius: 40, endRadius: size.height * 0.7
            )
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                hero
                Spacer(minLength: 0)
                if !content.stats.isEmpty { statsRow.padding(.bottom, isStory ? 56 : 28) }
                footer
            }
            .padding(.horizontal, 88)
            .padding(.vertical, isStory ? 120 : 72)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("share-card")
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Text(verbatim: "ATROX").font(.system(size: 44, weight: .black, design: .rounded)).tracking(6).foregroundStyle(ink)
            Spacer()
            Text(kindKey).font(.system(size: 32, weight: .semibold)).tracking(2).foregroundStyle(DSColor.accent)
        }
    }

    private var kindKey: LocalizedStringKey {
        switch content.kind {
        case .overall: "share.kind.overall"
        case .exercise: "share.kind.exercise"
        case .record: "share.kind.record"
        case .weekly: "share.kind.weekly"
        }
    }

    @ViewBuilder private var hero: some View {
        VStack(spacing: isStory ? 36 : 20) {
            if let score = content.score {
                ring(score)
            } else if let headline = content.headline {
                Image(systemName: "trophy.fill").font(.system(size: isStory ? 120 : 80)).foregroundStyle(DSColor.accent)
                Text(verbatim: headline).font(.system(size: isStory ? 150 : 110, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink).minimumScaleFactor(0.4).lineLimit(1)
            }
            if !content.title.isEmpty {
                Text(verbatim: content.title).font(.system(size: isStory ? 64 : 52, weight: .bold)).foregroundStyle(ink)
                    .multilineTextAlignment(.center).minimumScaleFactor(0.5).lineLimit(2)
            }
            if let level = content.level {
                Text(verbatim: level).font(.system(size: 40, weight: .semibold)).foregroundStyle(muted)
            }
            if options.showsReference, let reference = content.referenceLabel {
                Text(verbatim: reference).font(.system(size: 32)).foregroundStyle(muted).multilineTextAlignment(.center)
            }
            if options.showsBodyweight, let bodyweight = content.bodyweightText {
                Text(verbatim: bodyweight).font(.system(size: 32, weight: .medium)).foregroundStyle(muted)
            }
        }
    }

    private func ring(_ score: Int) -> some View {
        let diameter: CGFloat = isStory ? 600 : 420
        let color = DSColor.level(ScoreLevel(score: Double(score)))
        return ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 36)
            Circle().trim(from: 0, to: Double(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 36, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(verbatim: "\(score)").font(.system(size: diameter * 0.46, weight: .heavy, design: .rounded)).foregroundStyle(ink)
        }
        .frame(width: diameter, height: diameter)
    }

    private var statsRow: some View {
        HStack(spacing: 24) {
            ForEach(content.stats) { stat in
                VStack(spacing: 6) {
                    if stat.isVerbatim {
                        Text(verbatim: stat.label).font(.system(size: 40, weight: .bold)).foregroundStyle(ink)
                    } else {
                        Text(verbatim: stat.value).font(.system(size: 52, weight: .heavy, design: .rounded)).foregroundStyle(ink)
                        Text(LocalizedStringKey(stat.label)).font(.system(size: 28, weight: .medium)).foregroundStyle(muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 28))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if options.showsName, let name = content.displayName, !name.isEmpty {
                Text(verbatim: name).font(.system(size: 40, weight: .semibold)).foregroundStyle(ink)
            }
            if content.score != nil {
                // Small but readable: the number is an estimate, not a measurement.
                Text("share.estimated").font(.system(size: 30, weight: .medium)).foregroundStyle(muted)
            }
        }
    }
}
