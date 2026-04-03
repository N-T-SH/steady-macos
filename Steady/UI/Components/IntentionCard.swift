import SwiftUI

struct IntentionCard: View {
    let intention: Intention
    let onStart: () -> Void
    let onEdit: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with task name and status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(intention.task)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 6) {
                        StatusBadge(status: intention.status)
                        StrictnessBadge(level: intention.strictness)
                    }
                }
                
                Spacer()
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(isHovered ? 1 : 0.7)
            }
            
            Divider()
                .background(Color.secondary.opacity(0.2))
            
            // Why it matters section
            VStack(alignment: .leading, spacing: 4) {
                Text("Why it matters")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Text(intention.whyItMatters)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            
            // Temptation bundle (if set)
            if let temptation = intention.temptationBundle, !temptation.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("Watch for: \(temptation)")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                    Spacer()
                }
            }
            
            // Start button
            Button(action: onStart) {
                HStack {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                    Text("Start Session")
                        .font(.system(size: 14, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(intention.status == .planned ? Color.accentColor : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(intention.status != .planned)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct StatusBadge: View {
    let status: IntentionStatus
    
    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15))
            .foregroundColor(statusColor)
            .cornerRadius(4)
    }
    
    var statusColor: Color {
        switch status {
        case .planned:
            return .blue
        case .active:
            return .green
        case .completed:
            return .purple
        case .skipped:
            return .gray
        }
    }
}

struct StrictnessBadge: View {
    let level: StrictnessLevel
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.system(size: 8))
            Text(level.rawValue.capitalized)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(strictnessColor.opacity(0.15))
        .foregroundColor(strictnessColor)
        .cornerRadius(4)
    }
    
    var iconName: String {
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
    
    var strictnessColor: Color {
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
}
