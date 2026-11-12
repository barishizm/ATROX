import DataKit
import DesignSystem
import SwiftUI
import UIKit

/// Start / end frame of an exercise cross-fading in a loop (P031). Tap pauses or resumes; a horizontal swipe flips
/// to the other frame by hand. With Reduce Motion the loop does not run by itself.
struct ExerciseImageCarousel: View {
    let frames: [String]
    var interval: Duration = .milliseconds(1400)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var paused = false
    @State private var images: [String: UIImage] = [:]

    var body: some View {
        ZStack {
            DSColor.surfaceRaised
            ForEach(Array(frames.enumerated()), id: \.offset) { offset, name in
                if let image = images[name] {
                    Image(uiImage: image).resizable().scaledToFit()
                        .opacity(offset == index ? 1 : 0)
                }
            }
            if images.isEmpty {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 48)).foregroundStyle(DSColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(alignment: .bottom) { indicator }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: index)
        .contentShape(Rectangle())
        .onTapGesture { paused.toggle() }
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard frames.count > 1, abs(value.translation.width) > abs(value.translation.height) else { return }
                paused = true
                step(by: value.translation.width < 0 ? 1 : -1)
            }
        )
        .task(id: frames) { await loadImages() }
        .task(id: paused) { await loop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("exercise.image.label")
        .accessibilityValue(Text("exercise.image.frame \(index + 1) \(max(frames.count, 1))"))
        .accessibilityHint(paused ? "exercise.image.hint.resume" : "exercise.image.hint.pause")
        .accessibilityAddTraits(.isImage)
        .accessibilityAction { paused.toggle() }
        .accessibilityIdentifier("exercise-image")
    }

    private var indicator: some View {
        HStack(spacing: Spacing.sm) {
            if paused, frames.count > 1 { Image(systemName: "pause.fill").font(.caption2) }
            ForEach(frames.indices, id: \.self) { offset in
                Circle().fill(offset == index ? DSColor.accent : DSColor.textTertiary).frame(width: 6, height: 6)
            }
        }
        .padding(Spacing.sm)
        .opacity(frames.count > 1 ? 1 : 0)
    }

    private func step(by delta: Int) {
        guard !frames.isEmpty else { return }
        index = (index + delta + frames.count) % frames.count
    }

    private func loop() async {
        guard !paused, !reduceMotion, frames.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { break }
            step(by: 1)
        }
    }

    /// Thumbnail first (usually bundled, instant), then the full-size image.
    private func loadImages() async {
        index = 0
        images = [:]
        for name in frames {
            if let thumb = await ThumbnailLoader.shared.image(named: ImageNaming.thumb(forFull: name)) {
                images[name] = thumb
            }
        }
        for name in frames {
            if let full = await ThumbnailLoader.shared.image(named: name) { images[name] = full }
        }
    }
}
