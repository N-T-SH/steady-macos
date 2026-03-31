import SwiftUI

struct StrictnessSelector: View {
    @Binding var level: StrictnessLevel
    
    @State private var selectedIndex: Int = 1
    
    init(level: Binding<StrictnessLevel>) {
        self._level = level
        self._selectedIndex = State(initialValue: StrictnessLevel.allCases.firstIndex(of: level.wrappedValue) ?? 1)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Focus Mode")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            
            // Segmented selector
            HStack(spacing: 0) {
                ForEach(Array(StrictnessLevel.allCases.enumerated()), id: \.offset) { index, strictnessLevel in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedIndex = index
                            level = strictnessLevel
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: iconForLevel(strictnessLevel))
                                .font(.system(size: 14))
                            Text(strictnessLevel.rawValue.capitalized)
                                .font(.system(size: 12, weight: selectedIndex == index ? .semibold : .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedIndex == index ? colorForLevel(strictnessLevel) : Color.clear)
                        .foregroundColor(selectedIndex == index ? .white : colorForLevel(strictnessLevel))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            // Help text for selected mode
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: iconForLevel(level))
                        .font(.system(size: 12))
                        .foregroundColor(colorForLevel(level))
                    
                    Text(level.rawValue.capitalized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Text(helpTextForLevel(level))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Behavior details
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(behaviorDetailsForLevel(level), id: \.self) { detail in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(colorForLevel(level))
                                .padding(.top, 2)
                            
                            Text(detail)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(colorForLevel(level).opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(colorForLevel(level).opacity(0.2), lineWidth: 1)
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private func iconForLevel(_ level: StrictnessLevel) -> String {
        switch level {
        case .quiet:
            return "speaker.slash.fill"
        case .gentle:
            return "hand.raised.fill"
        case .focused:
            return "eye.fill"
        case .accountable:
            return "checkmark.shield.fill"
        }
    }
    
    private func colorForLevel(_ level: StrictnessLevel) -> Color {
        switch level {
        case .quiet:
            return .gray
        case .gentle:
            return .green
        case .focused:
            return .orange
        case .accountable:
            return .red
        }
    }
    
    private func helpTextForLevel(_ level: StrictnessLevel) -> String {
        switch level {
        case .quiet:
            return "Steady silently tracks your browsing activity without any interruptions. Perfect for self-directed work where you want insights without nudges."
        case .gentle:
            return "Occasional, friendly reminders when you drift off-task. Steady assumes positive intent and keeps interruptions minimal."
        case .focused:
            return "Regular check-ins to keep you aligned with your intention. Steady actively helps you notice and return from distractions."
        case .accountable:
            return "Firm guidance with immediate feedback when you go off-task. For when you need strong external accountability to stay focused."
        }
    }
    
    private func behaviorDetailsForLevel(_ level: StrictnessLevel) -> [String] {
        switch level {
        case .quiet:
            return [
                "Tracks all URL activity silently",
                "No notifications or interruptions",
                "Review your patterns in the log",
                "Self-directed focus mode"
            ]
        case .gentle:
            return [
                "Tracks URL activity",
                "Occasional nudges if you drift (33% chance)",
                "Friendly, non-judgmental reminders",
                "Assumes positive intent"
            ]
        case .focused:
            return [
                "Real-time URL classification",
                "Immediate notification on off-task sites",
                "Tracks interruptions and context",
                "Helps build awareness"
            ]
        case .accountable:
            return [
                "Strict real-time monitoring",
                "Urgent alerts for any off-task activity",
                "Requires acknowledgment of distractions",
                "Maximum accountability support"
            ]
        }
    }
}

struct StrictnessSelector_Previews: PreviewProvider {
    static var previews: some View {
        StrictnessSelector(level: .constant(.focused))
            .padding()
            .frame(width: 400)
    }
}
