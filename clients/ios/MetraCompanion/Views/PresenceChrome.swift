import SwiftUI

/// How large presence is drawn. Chat keeps the desk mark; voice nearly fills the screen.
enum PresenceSurface: String, Equatable {
    case chat
    case voice
}

/// Presence for the Metra home. Always on-screen; size depends on surface (chat vs voice).
struct PresenceChrome: View {
    var mood: PresenceMood = .attend
    var surface: PresenceSurface = .chat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if surface == .voice {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height) * 0.88
                    VStack(spacing: 16) {
                        Spacer(minLength: 0)
                        MetraPresenceFaceView(mood: mood)
                            .frame(width: side, height: side)
                            .animation(.easeInOut(duration: 0.28), value: mood)
                        Text(mood.caption)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(MetraBrand.accent(for: colorScheme).opacity(0.85))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 8) {
                    MetraPresenceFaceView(mood: mood)
                        .frame(width: chatMarkSize, height: chatMarkSize)
                        .animation(.easeInOut(duration: 0.28), value: mood)

                    Text(mood.caption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Metra, \(mood.caption), \(surface == .voice ? "voice" : "chat")")
    }

    /// Desk / text-chat mark size stays stable across moods (no jump on speaking).
    private var chatMarkSize: CGFloat { 128 }
}

enum PresenceMood: Equatable {
    case attend
    case listening
    case speaking

    var caption: String {
        switch self {
        case .attend: "attend"
        case .listening: "listening"
        case .speaking: "speaking"
        }
    }
}
