import UserNotifications
import Foundation

/// Actor-based notification manager for scheduling and handling user notifications
/// Delivers notifications quietly by default with time-sensitive option for deadlines
actor NotificationManager: NSObject {
    static let shared = NotificationManager()
    
    private let notificationCenter: UNUserNotificationCenter
    private var scheduledIdentifiers: Set<String> = []
    
    // MARK: - Constants
    
    private enum NotificationIdentifiers {
        static let morningIntention = "steady.morning.intention"
        static let sessionStart = "steady.session.start"
        static let sessionNudge = "steady.session.nudge"
        static let sessionComplete = "steady.session.complete"
        static let driftAlert = "steady.drift.alert"
        static let streakMilestone = "steady.streak.milestone"
    }
    
    private enum NotificationCategories {
        static let intentionCategory = "INTENTION_CATEGORY"
        static let sessionCategory = "SESSION_CATEGORY"
        static let nudgeCategory = "NUDGE_CATEGORY"
        static let driftCategory = "DRIFT_CATEGORY"
    }
    
    private enum ActionIdentifiers {
        static let startSession = "START_SESSION"
        static let skipSession = "SKIP_SESSION"
        static let logDistraction = "LOG_DISTRACTION"
        static let takeBreak = "TAKE_BREAK"
        static let backToWork = "BACK_TO_WORK"
        static let dismiss = "DISMISS"
    }
    
    // MARK: - Initialization
    
    private override init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        super.init()
    }
    
    // MARK: - Authorization
    
    /// Request authorization for notifications with quiet delivery by default
    func requestAuthorization() async throws {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound, .provisional]
        let granted = try await notificationCenter.requestAuthorization(options: options)
        
        if granted {
            await setupNotificationCategories()
            notificationCenter.delegate = self
        }
    }
    
    // MARK: - Notification Categories Setup
    
    private func setupNotificationCategories() async {
        // Intention category - Set intentions for today
        let startSessionAction = UNNotificationAction(
            identifier: ActionIdentifiers.startSession,
            title: "Set Intentions",
            options: .foreground
        )
        let skipIntentionAction = UNNotificationAction(
            identifier: ActionIdentifiers.skipSession,
            title: "Not Now",
            options: []
        )
        let intentionCategory = UNNotificationCategory(
            identifier: NotificationCategories.intentionCategory,
            actions: [startSessionAction, skipIntentionAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Session start category - Session ready to start
        let beginSessionAction = UNNotificationAction(
            identifier: ActionIdentifiers.startSession,
            title: "Start Session",
            options: .foreground
        )
        let postponeAction = UNNotificationAction(
            identifier: ActionIdentifiers.dismiss,
            title: "Later",
            options: []
        )
        let sessionCategory = UNNotificationCategory(
            identifier: NotificationCategories.sessionCategory,
            actions: [beginSessionAction, postponeAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Nudge category - Gentle reminder during session
        let takeBreakAction = UNNotificationAction(
            identifier: ActionIdentifiers.takeBreak,
            title: "Take Break",
            options: []
        )
        let backToWorkAction = UNNotificationAction(
            identifier: ActionIdentifiers.backToWork,
            title: "Back to Work",
            options: .foreground
        )
        let nudgeCategory = UNNotificationCategory(
            identifier: NotificationCategories.nudgeCategory,
            actions: [takeBreakAction, backToWorkAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Drift category - Alert when drifting off task
        let logDistractionAction = UNNotificationAction(
            identifier: ActionIdentifiers.logDistraction,
            title: "Log Distraction",
            options: .foreground
        )
        let dismissDriftAction = UNNotificationAction(
            identifier: ActionIdentifiers.dismiss,
            title: "Dismiss",
            options: []
        )
        let driftCategory = UNNotificationCategory(
            identifier: NotificationCategories.driftCategory,
            actions: [logDistractionAction, dismissDriftAction],
            intentIdentifiers: [],
            options: []
        )
        
        await notificationCenter.setNotificationCategories([
            intentionCategory,
            sessionCategory,
            nudgeCategory,
            driftCategory
        ])
    }
    
    // MARK: - Notification Scheduling
    
    /// Schedule morning intention reminder
    func scheduleIntentionReminder(intention: Intention) async {
        let content = UNMutableNotificationContent()
        content.title = "Set intentions for today?"
        content.body = "What matters most today? Take a moment to set your focus."
        content.categoryIdentifier = NotificationCategories.intentionCategory
        content.sound = .default
        content.interruptionLevel = .passive // Quiet by default
        content.userInfo = ["intentionId": intention.id.uuidString]
        
        // Schedule for 9:00 AM or user's preferred time
        var dateComponents = DateComponents()
        dateComponents.hour = 9
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let identifier = NotificationIdentifiers.morningIntention
        
        await sendNotification(
            content: content,
            identifier: identifier,
            trigger: trigger
        )
    }
    
    /// Schedule session start notification
    func scheduleSessionStart(intention: Intention) async {
        let content = UNMutableNotificationContent()
        content.title = "\(intention.task) session ready"
        content.body = "Start your \(intention.plannedDuration)-minute focused session?"
        content.categoryIdentifier = NotificationCategories.sessionCategory
        content.sound = .default
        content.interruptionLevel = .passive
        content.userInfo = [
            "intentionId": intention.id.uuidString,
            "task": intention.task,
            "duration": intention.plannedDuration
        ]
        
        // Immediate notification
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "\(NotificationIdentifiers.sessionStart).\(intention.id.uuidString)"
        
        await sendNotification(
            content: content,
            identifier: identifier,
            trigger: trigger
        )
    }
    
    /// Schedule gentle nudge during active session
    func scheduleSessionNudge(session: Session) async {
        // Only send nudges for gentle, focused, or accountable strictness levels
        guard let intention = await getIntention(for: session) else { return }
        guard intention.strictness != .quiet else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Still focused?"
        content.body = "You've been on this page for a while. Break or back to \(intention.task)?"
        content.categoryIdentifier = NotificationCategories.nudgeCategory
        content.sound = .default
        content.interruptionLevel = .passive
        content.userInfo = [
            "sessionId": session.id.uuidString,
            "intentionId": session.intentionId.uuidString
        ]
        
        // Send after 10 minutes of continuous activity
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
        let identifier = "\(NotificationIdentifiers.sessionNudge).\(session.id.uuidString)"
        
        await sendNotification(
            content: content,
            identifier: identifier,
            trigger: trigger
        )
    }
    
    /// Send drift alert when user is off-task
    func sendDriftAlert(classification: URLClassification) async {
        let content = UNMutableNotificationContent()
        content.title = "Off track?"
        content.body = "\(classification.pageTitle) doesn't seem related to your current intention."
        content.categoryIdentifier = NotificationCategories.driftCategory
        content.sound = .default
        content.interruptionLevel = .passive
        content.userInfo = [
            "url": classification.url,
            "category": classification.category.rawValue,
            "confidence": classification.confidence
        ]
        
        // Immediate notification
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "\(NotificationIdentifiers.driftAlert).\(classification.timestamp.timeIntervalSince1970)"
        
        await sendNotification(
            content: content,
            identifier: identifier,
            trigger: trigger
        )
    }
    
    /// Send streak milestone celebration
    func sendStreakMilestone(streak: Int) async {
        guard streak > 0 && streak % 5 == 0 else { return } // Every 5 days
        
        let content = UNMutableNotificationContent()
        content.title = "\(streak) day streak!"
        content.body = "You're building great habits. Keep it up!"
        content.sound = .default
        content.interruptionLevel = .passive
        content.userInfo = ["streak": streak]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "\(NotificationIdentifiers.streakMilestone).\(streak)"
        
        await sendNotification(
            content: content,
            identifier: identifier,
            trigger: trigger
        )
    }
    
    /// Send session complete notification
    func sendSessionComplete(session: Session) async {
        guard let intention = await getIntention(for: session) else { return }
        
        let duration = session.endTime?.timeIntervalSince(session.startTime) ?? 0
        let minutes = Int(duration / 60)
        
        let content = UNMutableNotificationContent()
        content.title = "Session complete!"
        content.body = "Great work on \(intention.task) for \(minutes) minutes. How did it go?"
        content.sound = .default
        content.interruptionLevel = .passive
        content.userInfo = [
            "sessionId": session.id.uuidString,
            "intentionId": session.intentionId.uuidString,
            "duration": minutes
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "\(NotificationIdentifiers.sessionComplete).\(session.id.uuidString)"
        
        await sendNotification(
            content: content,
            identifier: identifier,
            trigger: trigger
        )
    }
    
    // MARK: - Notification Management
    
    /// Clear all pending notifications
    func clearPendingNotifications() async {
        await notificationCenter.removeAllPendingNotificationRequests()
        scheduledIdentifiers.removeAll()
    }
    
    /// Clear notifications for a specific session
    func clearNotifications(for sessionId: UUID) async {
        let identifiers = [
            "\(NotificationIdentifiers.sessionStart).\(sessionId.uuidString)",
            "\(NotificationIdentifiers.sessionNudge).\(sessionId.uuidString)",
            "\(NotificationIdentifiers.sessionComplete).\(sessionId.uuidString)"
        ]
        await notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        identifiers.forEach { scheduledIdentifiers.remove($0) }
    }
    
    /// Get count of pending notifications (for rate limiting)
    func getPendingNotificationCount() async -> Int {
        let requests = await notificationCenter.pendingNotificationRequests()
        return requests.count
    }
    
    // MARK: - Private Methods
    
    private func sendNotification(
        content: UNMutableNotificationContent,
        identifier: String,
        trigger: UNNotificationTrigger
    ) async {
        // Rate limiting: max 3-4 notifications per day
        let pendingCount = await getPendingNotificationCount()
        guard pendingCount < 4 else { return }
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await notificationCenter.add(request)
            scheduledIdentifiers.insert(identifier)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }
    
    /// Helper to fetch intention for a session (would connect to data store in real implementation)
    private func getIntention(for session: Session) async -> Intention? {
        // This would typically fetch from Core Data or other persistence
        // For now, return a placeholder - actual implementation would use IntentionStore
        return nil
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Always deliver quietly by default
        completionHandler([.banner, .sound])
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let notificationId = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        
        Task {
            await handleNotificationAction(
                actionIdentifier: actionIdentifier,
                notificationId: notificationId,
                userInfo: userInfo
            )
        }
        
        completionHandler()
    }
    
    private func handleNotificationAction(
        actionIdentifier: String,
        notificationId: String,
        userInfo: [AnyHashable: Any]
    ) async {
        switch actionIdentifier {
        case ActionIdentifiers.startSession:
            // Post notification to app to show intention setup or start session
            NotificationCenter.default.post(
                name: .init("SteadyStartSession"),
                object: nil,
                userInfo: userInfo
            )
            
        case ActionIdentifiers.skipSession, ActionIdentifiers.dismiss:
            // Just dismiss - no action needed
            break
            
        case ActionIdentifiers.logDistraction:
            NotificationCenter.default.post(
                name: .init("SteadyLogDistraction"),
                object: nil,
                userInfo: userInfo
            )
            
        case ActionIdentifiers.takeBreak:
            NotificationCenter.default.post(
                name: .init("SteadyTakeBreak"),
                object: nil,
                userInfo: userInfo
            )
            
        case ActionIdentifiers.backToWork:
            NotificationCenter.default.post(
                name: .init("SteadyBackToWork"),
                object: nil,
                userInfo: userInfo
            )
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification - open relevant view
            NotificationCenter.default.post(
                name: .init("SteadyOpenNotification"),
                object: nil,
                userInfo: userInfo
            )
            
        default:
            break
        }
        
        // Remove the delivered notification
        await notificationCenter.removeDeliveredNotifications(withIdentifiers: [notificationId])
    }
}

// MARK: - Time-Sensitive Notifications

extension NotificationManager {
    
    /// Schedule a time-sensitive notification for user-set deadlines
    func scheduleDeadlineReminder(deadline: Date, intention: Intention) async {
        let content = UNMutableNotificationContent()
        content.title = "Deadline approaching"
        content.body = "Your intention \"\(intention.task)\" deadline is in 15 minutes"
        content.sound = .default
        content.interruptionLevel = .timeSensitive // Override quiet delivery for deadlines
        content.userInfo = ["intentionId": intention.id.uuidString]
        
        let triggerDate = deadline.addingTimeInterval(-15 * 60) // 15 minutes before
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "steady.deadline.\(intention.id.uuidString)"
        
        await sendNotification(
            content: content,
            identifier: identifier,
            trigger: trigger
        )
    }
}
