//
//  NotificationTool.swift
//  RunAnywhereAI
//
//  send_notification — posts a local user notification. The manager is also
//  the UNUserNotificationCenter delegate: without a delegate that returns
//  presentation options, a notification posted while the app is frontmost —
//  the common case during a chat or a workflow run — is silently swallowed.
//

import Foundation
import RunAnywhere
import UserNotifications

@MainActor
final class NotificationToolManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationToolManager()

    /// Authorisation is asked for the first time a notification is actually
    /// wanted, not at launch: a permission sheet on first run, for a tool the
    /// user may never reach, is the prompt everyone denies.
    func access() async -> ToolAccess {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .refused(Self.deniedMessage)
        default:
            break
        }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? .granted : .refused(Self.deniedMessage)
        } catch {
            return .refused("Could not ask for notification permission: \(error.localizedDescription)")
        }
    }

    private static var deniedMessage: String {
        #if os(macOS)
        "Notifications are turned off for this app. Turn them on in System Settings > Notifications."
        #else
        "Notifications are turned off for this app. Turn them on in Settings > Notifications."
        #endif
    }

    func send(title: String, body: String, delaySeconds: Double) async -> [String: RAToolValue] {
        if let refusal = await access().refusal {
            return ["error": RAToolValue(refusal), "delivered": RAToolValue(false)]
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Clamped to 24h; anything further out belongs in Reminders or
        // Calendar, which survive the app being quit.
        let clampedDelay = min(max(delaySeconds, 0), 86_400)
        let trigger: UNNotificationTrigger? = clampedDelay >= 1
            ? UNTimeIntervalNotificationTrigger(timeInterval: clampedDelay, repeats: false)
            : nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            return ["error": RAToolValue(error.localizedDescription), "delivered": RAToolValue(false)]
        }

        return [
            "delivered": RAToolValue(true),
            "title": RAToolValue(title),
            "delay_seconds": RAToolValue(clampedDelay)
        ]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum NotificationTool {
    static var definition: ToolDefinition {
        ToolDefinition(
            name: "send_notification",
            description: """
                Shows a system notification banner on this device, immediately or after a \
                delay of up to 24 hours. Use when the user asks to be notified, pinged, or \
                alerted ("notify me in 20 minutes", "send me a notification when done"). \
                The notification only fires while this app is running — for anything \
                further out, or that must survive quitting the app, use create_reminder \
                instead. Keep the title short and put the detail in the body. Only say the \
                notification was sent or scheduled if the result has delivered = true.
                """,
            parameters: [
                ToolParameter(
                    name: "title",
                    type: .string,
                    description: "Short headline shown in the notification banner."
                ),
                ToolParameter(
                    name: "body",
                    type: .string,
                    description: "Message text shown under the title."
                ),
                ToolParameter(
                    name: "delay_seconds",
                    type: .number,
                    description: """
                        Seconds to wait before showing the notification (e.g. 1200 for "in \
                        20 minutes"). Omit or pass 0 to show it immediately. Maximum 86400 \
                        (24 hours).
                        """,
                    required: false
                )
            ],
            category: "Notifications"
        )
    }

    static var executor: ToolExecutor {
        { args in
            guard let title = args["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return ["error": RAToolValue("Missing required \"title\" argument")]
            }
            let body = args["body"]?.string ?? ""
            let delay = args["delay_seconds"]?.number ?? 0
            return await NotificationToolManager.shared.send(
                title: title,
                body: body,
                delaySeconds: delay
            )
        }
    }
}
