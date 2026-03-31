import SwiftUI

struct SessionTimer: View {
    @ObservedObject var sessionManager: SessionManager
    var onEndSession: (() -> Void)? = nil
    var onLogDistraction: (() -> Void)? = nil
    
    @State private var showEndConfirmation = false
    @State private var showDistractionSheet = false
    @State private var distractionReason = ""
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress ring
            ZStack {
                // Background circle
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.15),
                        lineWidth: 8
                    )
                    .frame(width: 200, height: 200)
                
                // Progress arc
                Circle()
                    .trim(from: 0, to: CGFloat(min(sessionManager.progressPercentage(), 1.0)))
                    .stroke(
                        progressGradient,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: sessionManager.progressPercentage())
                
                // Timer display
                VStack(spacing: 4) {
                    Text(sessionManager.formattedElapsedTime())
                        .font(.system(size: 42, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    if sessionManager.remainingTime() != nil {
                        Text("Remaining: \(sessionManager.formattedRemainingTime())")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    if sessionManager.isPaused {
                        Text("PAUSED")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.vertical, 20)
            
            // Intention info
            if let intention = sessionManager.currentIntention {
                VStack(spacing: 8) {
                    Text("Focusing on")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Text(intention.task)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    if !intention.whyItMatters.isEmpty {
                        Text(intention.whyItMatters)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 24)
            }
            
            // Control buttons
            HStack(spacing: 16) {
                // Pause/Resume button
                Button(action: {
                    if sessionManager.isPaused {
                        sessionManager.resumeSession()
                    } else {
                        sessionManager.pauseSession()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: sessionManager.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 14))
                        Text(sessionManager.isPaused ? "Resume" : "Pause")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(width: 100)
                    .padding(.vertical, 10)
                    .background(sessionManager.isPaused ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundColor(sessionManager.isPaused ? .green : .orange)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Log distraction button
                Button(action: {
                    showDistractionSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.bubble")
                            .font(.system(size: 14))
                        Text("Log")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(width: 100)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(sessionManager.isPaused)
                
                // End session button
                Button(action: {
                    showEndConfirmation = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14))
                        Text("End")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(width: 100)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 8)
            
            // Distractions list
            if let session = sessionManager.activeSession, !session.interruptions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Logged Distractions (\(session.interruptions.count))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(session.interruptions.enumerated()), id: \.offset) { index, distraction in
                                HStack {
                                    Image(systemName: distraction.acknowledged ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10))
                                        .foregroundColor(distraction.acknowledged ? .green : .orange)
                                    
                                    Text(distraction.category)
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Text(formatTime(distraction.timestamp))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(4)
                                .onTapGesture {
                                    sessionManager.acknowledgeDistraction(at: index)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
        .alert("End Session?", isPresented: $showEndConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) {
                onEndSession?()
            }
        } message: {
            Text("Are you sure you want to end this session?")
        }
        .sheet(isPresented: $showDistractionSheet) {
            DistractionSheet(reason: $distractionReason) { reason in
                sessionManager.logDistraction(reason: reason)
                showDistractionSheet = false
                distractionReason = ""
                onLogDistraction?()
            }
        }
    }
    
    private var progressGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [.accentColor, .purple]),
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct DistractionSheet: View {
    @Binding var reason: String
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("What distracted you?")
                .font(.system(size: 16, weight: .semibold))
            
            TextEditor(text: $reason)
                .font(.system(size: 14))
                .frame(height: 80)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            
            // Quick options
            HStack(spacing: 8) {
                ForEach(["Social Media", "Email", "Notification", "Other"], id: \.self) { option in
                    Button(action: {
                        reason = option
                    }) {
                        Text(option)
                            .font(.system(size: 12))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(PlainButtonStyle())
                
                Button("Log") {
                    if !reason.isEmpty {
                        onSubmit(reason)
                    }
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(reason.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
