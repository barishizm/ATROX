import SwiftUI

/// Parses the normalized path strings emitted by `tools/musclemap/convert.py` (absolute `M L C Q Z` only).
enum MuscleMapPathParser {
    static func path(from string: String) -> Path {
        var path = Path()
        let tokens = string.split(separator: " ", omittingEmptySubsequences: true)
        var index = 0

        func take(_ count: Int) -> [CGFloat]? {
            guard index + count <= tokens.count else { return nil }
            var values: [CGFloat] = []
            for token in tokens[index..<index + count] {
                guard let value = Double(token) else { return nil }
                values.append(CGFloat(value))
            }
            index += count
            return values
        }

        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M": if let v = take(2) { path.move(to: CGPoint(x: v[0], y: v[1])) } else { return Path() }
            case "L": if let v = take(2) { path.addLine(to: CGPoint(x: v[0], y: v[1])) } else { return Path() }
            case "Q":
                guard let v = take(4) else { return Path() }
                path.addQuadCurve(to: CGPoint(x: v[2], y: v[3]), control: CGPoint(x: v[0], y: v[1]))
            case "C":
                guard let v = take(6) else { return Path() }
                path.addCurve(
                    to: CGPoint(x: v[4], y: v[5]),
                    control1: CGPoint(x: v[0], y: v[1]), control2: CGPoint(x: v[2], y: v[3]))
            case "Z": path.closeSubpath()
            default: return Path()
            }
        }
        return path
    }
}

/// Pre-parsed geometry for one body view, shared by every `MuscleMapView`.
struct MuscleMapRegion: Sendable, Identifiable {
    let id: String
    let muscles: [Muscle]
    let path: Path
}

enum MuscleMapGeometry {
    static let aspectRatio: CGFloat = MuscleMapData.canvas.width / MuscleMapData.canvas.height

    static let front: [MuscleMapRegion] = resolve(MuscleMapData.front)
    static let back: [MuscleMapRegion] = resolve(MuscleMapData.back)
    static let frontOutline = MuscleMapPathParser.path(from: MuscleMapData.frontOutline)
    static let backOutline = MuscleMapPathParser.path(from: MuscleMapData.backOutline)

    private static func resolve(_ regions: [MuscleMapData.Region]) -> [MuscleMapRegion] {
        regions.map { region in
            var combined = Path()
            for string in region.paths { combined.addPath(MuscleMapPathParser.path(from: string)) }
            return MuscleMapRegion(id: region.id, muscles: region.muscles, path: combined)
        }
    }
}

/// Draws canvas-space geometry scaled uniformly into the proposed rect, centered.
struct MuscleMapShape: Shape {
    let source: Path

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / MuscleMapData.canvas.width, rect.height / MuscleMapData.canvas.height)
        guard scale.isFinite, scale > 0 else { return Path() }
        let x = rect.minX + (rect.width - MuscleMapData.canvas.width * scale) / 2
        let y = rect.minY + (rect.height - MuscleMapData.canvas.height * scale) / 2
        return source.applying(CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: y)))
    }
}
