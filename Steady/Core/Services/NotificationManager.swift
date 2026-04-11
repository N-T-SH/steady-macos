import Foundation

/// Stub — system notification center reminders have been removed.
/// Check-ins are now signalled by a periodic menu bar icon flash.
actor NotificationManager: NSObject {
    static let shared = NotificationManager()
    private override init() { super.init() }
}
