import SwiftUI

/// Native SwiftUI presence face (docs/assets/metra-presence-face.svg is reference only - not bundled).
/// Phase 1.5: native SwiftUI pose only - full nine-face controller later.
struct MetraPresenceFaceView: View {
    var mood: PresenceMood = .attend

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let design: CGFloat = 256

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let s = min(size.width, size.height) / design
                context.scaleBy(x: s, y: s)

                let teal = MetraBrand.accent(for: colorScheme)
                let pill = MetraBrand.pill(for: colorScheme)
                let openFill = MetraBrand.openFill(for: colorScheme)

                let lean: CGFloat = {
                    guard !reduceMotion else { return 0 }
                    switch mood {
                    case .attend: return CGFloat(sin(t * 1.15) * 1.2)
                    case .listening: return CGFloat(sin(t * 1.6) * 0.8)
                    case .speaking: return CGFloat(sin(t * 1.4) * 0.9)
                    }
                }()

                var presence = context
                presence.translateBy(x: design / 2, y: design / 2)
                presence.rotate(by: .degrees(Double(lean) * 0.15))
                presence.translateBy(x: -design / 2, y: -design / 2)

                var plate = Path(roundedRect: CGRect(x: 8, y: 8, width: 240, height: 240), cornerRadius: 48)
                presence.fill(plate, with: .color(pill.opacity(colorScheme == .dark ? 0.55 : 0.72)))

                drawNameplate(presence, teal: teal, pill: pill)

                let blink = Self.blinkAmount(at: t, reduceMotion: reduceMotion)
                drawEyes(presence, teal: teal, blink: blink)
                drawMouth(presence, teal: teal, openFill: openFill)
            }
        }
        .accessibilityLabel("Metra")
        .accessibilityAddTraits(.isImage)
    }

    /// Irregular blink gaps (~4.5-11s) so the face does not feel metronomic.
    /// Phase is computed inside a short sliding window so we never walk from ReferenceDate.
    private static func blinkAmount(at t: TimeInterval, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 1 }
        let window = 120.0
        let epoch = Int(floor(t / window))
        let localT = t - Double(epoch) * window
        // Per-window index offset keeps gaps irregular across window boundaries.
        var i = epoch &* 17
        var cursor = 0.0
        for _ in 0..<64 {
            let gap = blinkGap(for: i)
            let next = cursor + gap
            if localT < next {
                let into = localT - cursor
                if into > gap - 0.18 && into < gap - 0.04 { return 0.16 }
                return 1
            }
            cursor = next
            i += 1
        }
        return 1
    }

    private static func blinkGap(for index: Int) -> Double {
        let h = Double((index &* 2654435761) & 0xFFFF) / Double(0xFFFF)
        return 4.5 + h * 6.5
    }

    private func drawNameplate(_ context: GraphicsContext, teal: Color, pill: Color) {
        var plate = Path(roundedRect: CGRect(x: 62, y: 28, width: 132, height: 40), cornerRadius: 20)
        context.fill(plate, with: .color(pill))

        // Pill vertical center is y=48 so the t stem does not rest on the rim.
        let letters: [(String, CGFloat)] = [
            ("M", 88), ("e", 108), ("t", 128), ("r", 146), ("a", 164),
        ]
        for (ch, x) in letters {
            let glyph = Text(ch)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundColor(teal)
            context.draw(glyph, at: CGPoint(x: x, y: 48), anchor: .center)
        }

        var stem = Path()
        stem.move(to: CGPoint(x: 128, y: 66))
        stem.addLine(to: CGPoint(x: 128, y: 90))
        context.stroke(stem, with: .color(teal), style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }

    private func drawEyes(_ context: GraphicsContext, teal: Color, blink: CGFloat) {
        let rx: CGFloat = 17
        let ry: CGFloat = 13 * blink
        for cx in [CGFloat(88), 168] {
            let rect = CGRect(x: cx - rx, y: 118 - ry, width: rx * 2, height: ry * 2)
            context.fill(Path(ellipseIn: rect), with: .color(teal))
        }
    }

    /// Text-mode mouth: soft smile; open node only for attend/listening (static).
    /// No pulsing open node for speaking - that reads oddly after a text reply.
    private func drawMouth(
        _ context: GraphicsContext,
        teal: Color,
        openFill: Color
    ) {
        let mouthY: CGFloat = 173.5

        var smile = Path()
        let smileDepth: CGFloat = {
            switch mood {
            case .attend: 176
            case .listening: 174
            case .speaking: 178
            }
        }()
        smile.move(to: CGPoint(x: 78, y: 166))
        smile.addCurve(
            to: CGPoint(x: 178, y: 166),
            control1: CGPoint(x: 94, y: smileDepth),
            control2: CGPoint(x: 162, y: smileDepth)
        )
        let smileOpacity: Double = {
            switch mood {
            case .attend: 0.85
            case .listening: 0.55
            case .speaking: 0.95
            }
        }()
        context.stroke(
            smile,
            with: .color(teal.opacity(smileOpacity)),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        )

        let baseR: CGFloat? = {
            switch mood {
            case .attend: 7.5
            case .listening: 9.5
            case .speaking: nil
            }
        }()
        guard let r = baseR else { return }
        let mouthRect = CGRect(x: 128 - r, y: mouthY - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: mouthRect), with: .color(openFill))
        context.stroke(
            Path(ellipseIn: mouthRect),
            with: .color(teal),
            style: StrokeStyle(lineWidth: 5, lineCap: .round)
        )
    }
}

#Preview("Face") {
    MetraPresenceFaceView(mood: .attend)
        .frame(width: 200, height: 200)
        .padding()
        .background(MetraBrand.mist)
}
