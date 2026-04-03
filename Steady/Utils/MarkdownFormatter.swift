import Foundation

enum MarkdownFormatter {
    
    // MARK: - Date Formatters
    
    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd h:mm a"
        return formatter
    }
    
    private static var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
    
    // MARK: - Check-in Formatting
    
    static func formatCheckinEntry(session: Session, intention: Intention) -> String {
        let timestamp = dateFormatter.string(from: session.startTime)
        var lines: [String] = []
        
        lines.append("### \(timestamp)")
        lines.append("**Session:** \(intention.task)")
        
        lines.append("**Energy before:** \(session.preSessionEnergy)/10")
        
        let completed = session.endTime != nil && intention.status == .completed
        lines.append("**Completed:** \(completed ? "Yes" : "No")")
        
        if let reflection = session.postSessionReflection, !reflection.isEmpty {
            lines.append("**Reflection:** \"\(reflection)\"")
        }
        
        if !session.interruptions.isEmpty {
            let distractionCount = session.interruptions.count
            let notes = session.interruptions.compactMap { $0.category }.joined(separator: ", ")
            let distractionText = notes.isEmpty ? "\(distractionCount)" : "\(distractionCount) (\(notes))"
            lines.append("**Distractions:** \(distractionText)")
        }
        
        lines.append("---")
        lines.append("")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Reflection Formatting
    
    static func formatReflectionEntry(
        question: String,
        answer: String,
        insight: String?,
        source: String
    ) -> String {
        let timestamp = shortDateFormatter.string(from: Date())
        var lines: [String] = []
        
        lines.append("### \(timestamp)")
        lines.append("**Q:** \(question)")
        lines.append("**A:** \(answer)")
        
        if let insight = insight, !insight.isEmpty {
            lines.append("**Insight:** \(insight)")
        }
        
        lines.append("**Source:** \(source)")
        lines.append("---")
        lines.append("")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Current State Formatting
    
    static func formatCurrentState(stats: CurrentStateStats) -> String {
        let dateFormatter = shortDateFormatter
        let lastCheckinStr = dateFormatter.string(from: stats.lastCheckin)
        let updatedDate = dateFormatter.string(from: Date())
        
        var lines: [String] = []
        
        lines.append("# Current State")
        lines.append("*Last updated: \(updatedDate)*")
        lines.append("")
        lines.append("## Stats")
        lines.append("- Last check-in: \(lastCheckinStr)")
        lines.append("- Current streak: \(stats.currentStreak) days")
        lines.append("- Longest streak: \(stats.longestStreak) days")
        lines.append("- Total check-ins: \(stats.totalCheckins)")
        lines.append("- This month: \(stats.thisMonthCheckins)")
        
        if !stats.habitStreaks.isEmpty {
            lines.append("")
            lines.append("## Habit Streaks")
            for (habit, streak) in stats.habitStreaks.sorted(by: { $0.key < $1.key }) {
                lines.append("- \(habit): \(streak) days")
            }
        }
        
        if !stats.currentBlockers.isEmpty {
            lines.append("")
            lines.append("## Current Blockers")
            for blocker in stats.currentBlockers {
                lines.append("- \(blocker)")
            }
        }
        
        if let energy = stats.energyLevel {
            lines.append("")
            lines.append("## Energy")
            lines.append("Current level: \(energy)/10")
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Next Session Formatting
    
    static func formatNextSessionEntry(followUp: String) -> String {
        return "- [ ] \(followUp)"
    }
    
    // MARK: - Conversation Summary Formatting
    
    static func formatConversationSummary(
        summary: String,
        intention: Intention
    ) -> String {
        let timestamp = shortDateFormatter.string(from: Date())
        var lines: [String] = []
        
        lines.append("### \(timestamp)")
        lines.append("**Session:** \(intention.task)")
        lines.append("**Summary:** \(summary)")
        lines.append("---")
        lines.append("")
        
        return lines.joined(separator: "\n")
    }
}
