import Foundation

/// Describes which infographic card to render in the panel header.
/// The LLM produces this JSON; SwiftUI renders it natively.
struct InfographicSpec: Codable, Equatable {

    enum CardType: String, Codable {
        /// Single large value + optional subtitle
        case stat
        /// 2–3 stats side by side
        case multiStat
        /// Horizontal segmented bar (e.g. focus vs drift)
        case barSplit
        /// Row of colored circles (recent activity checks)
        case dotRow
        /// 2 label:value pairs stacked
        case labelValue
    }

    let cardType: CardType

    /// When set, the entire card is tappable and opens this URL in the browser.
    let linkURL: String?

    // MARK: stat
    let value: String?
    let label: String?       // small label above value
    let subtitle: String?    // small text below value
    let accent: String?      // "green" | "orange" | nil → default

    // MARK: multiStat
    let items: [StatItem]?

    // MARK: barSplit
    let barTitle: String?
    let segments: [BarSegment]?

    // MARK: dotRow
    let dotTitle: String?
    let dots: [String]?      // "green" | "orange" | "gray"

    // MARK: labelValue
    let rows: [LabelRow]?

    struct StatItem: Codable, Equatable {
        let label: String
        let value: String
    }

    struct BarSegment: Codable, Equatable {
        let label: String
        let ratio: Double   // 0.0–1.0
        let color: String   // "green" | "orange" | "blue" | "gray"
    }

    struct LabelRow: Codable, Equatable {
        let label: String
        let value: String
    }
}

// MARK: - Convenience factories (for local card generation without the LLM)

extension InfographicSpec {
    static func stat(label: String?, value: String, subtitle: String? = nil, accent: String? = nil, linkURL: String? = nil) -> InfographicSpec {
        InfographicSpec(cardType: .stat, linkURL: linkURL, value: value, label: label, subtitle: subtitle, accent: accent,
                        items: nil, barTitle: nil, segments: nil, dotTitle: nil, dots: nil, rows: nil)
    }

    static func barSplit(title: String, segments: [BarSegment]) -> InfographicSpec {
        InfographicSpec(cardType: .barSplit, linkURL: nil, value: nil, label: nil, subtitle: nil, accent: nil,
                        items: nil, barTitle: title, segments: segments, dotTitle: nil, dots: nil, rows: nil)
    }

    static func dotRow(title: String, dots: [String]) -> InfographicSpec {
        InfographicSpec(cardType: .dotRow, linkURL: nil, value: nil, label: nil, subtitle: nil, accent: nil,
                        items: nil, barTitle: nil, segments: nil, dotTitle: title, dots: dots, rows: nil)
    }

    static func labelValue(rows: [LabelRow]) -> InfographicSpec {
        InfographicSpec(cardType: .labelValue, linkURL: nil, value: nil, label: nil, subtitle: nil, accent: nil,
                        items: nil, barTitle: nil, segments: nil, dotTitle: nil, dots: nil, rows: rows)
    }
}

/// Raw stats computed from local data, sent to the LLM as context for card selection.
struct FocusStats {
    let totalEvents: Int
    let onTaskEvents: Int
    let driftEvents: Int
    let goofingOffEvents: Int
    let onTaskPercent: Int        // 0–100
    let focusMinutes: Int         // on-task events × ~10s poll ÷ 60
    let sessionCount: Int
    let longestBlockMinutes: Int
    let topProject: String?
    let topCategory: String?
    let currentSessionMinutes: Int?
    let timeOfDay: String         // "morning" | "afternoon" | "evening"
    let minutesSinceLastDistraction: Int?
    let recentChecks: [TaskStatus]  // last 10 activity events
}
