import Foundation

/// Non-normative presence cue map - presence consumes policy events only.
/// No uncued Playful catalog walks from conversation policy.
enum PresencePolicyEvent: String, Sendable, Hashable {
    case deskAttend
    case companyWarm
    case deliverFocus
    case deskStrictFlat
    case listening
    case speaking
    case sparkEligible
    case sparkDenied
    case seamAuthorized
    case seamSkipped
    case ephemeralActive
    case ephemeralEnded
    case intimacyRefuse
    case retentionBlock
}

struct PresenceCue: Sendable, Hashable {
    let event: PresencePolicyEvent
    let mood: PresenceMood
    let note: String?
}

enum PresenceCueMap {
    /// Map a policy/runtime event to optional presence chrome. Never invent Playful walks.
    static func consume(_ event: PresencePolicyEvent) -> PresenceCue? {
        switch event {
        case .deskAttend, .deliverFocus:
            return PresenceCue(event: event, mood: .attend, note: nil)
        case .companyWarm:
            return PresenceCue(event: event, mood: .attend, note: "company")
        case .deskStrictFlat:
            return PresenceCue(event: event, mood: .attend, note: "desk_strict")
        case .listening:
            return PresenceCue(event: event, mood: .listening, note: nil)
        case .speaking:
            return PresenceCue(event: event, mood: .speaking, note: nil)
        case .sparkEligible, .sparkDenied, .seamAuthorized, .seamSkipped,
             .ephemeralActive, .ephemeralEnded, .intimacyRefuse, .retentionBlock:
            // Telemetry/cue acknowledgement only - no mood change unless speaking/listening.
            return PresenceCue(event: event, mood: .attend, note: event.rawValue)
        }
    }
}
