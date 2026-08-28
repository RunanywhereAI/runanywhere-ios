//
//  ReminderTools.swift
//  RunAnywhereAI
//
//  create_reminder / get_reminders — EventKit Reminders. Same shape as
//  CalendarManager but with its own store: Reminders is a separate EventKit
//  authorisation from Calendars and the two prompts are independent.
//

import EventKit
import Foundation
import RunAnywhere

actor RemindersManager {
    static let shared = RemindersManager()

    private let store = EKEventStore()
    private var granted = false

    /// Asked for at first use. `NSRemindersFullAccessUsageDescription` is in
    /// the app's Info.plist because EventKit traps rather than throwing when
    /// the string is absent.
    private func access() async -> ToolAccess {
        if granted { return .granted }
        if EKEventStore.authorizationStatus(for: .reminder) == .denied {
            return .refused(Self.deniedMessage)
        }
        do {
            granted = try await store.requestFullAccessToReminders()
        } catch {
            return .refused("Could not ask for Reminders access: \(error.localizedDescription)")
        }
        return granted ? .granted : .refused(Self.deniedMessage)
    }

    private static var deniedMessage: String {
        #if os(macOS)
        "Reminders access was refused. Allow it in System Settings > Privacy & Security > Reminders."
        #else
        "Reminders access was refused. Allow it in Settings > Privacy & Security > Reminders."
        #endif
    }

    private func reminderList(named name: String?) -> (calendar: EKCalendar?, error: String?) {
        guard let name, !name.isEmpty else {
            return (store.defaultCalendarForNewReminders(), nil)
        }
        let lists = store.calendars(for: .reminder)
        guard let match = lists.first(where: {
            $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            let available = lists.map(\.title).joined(separator: ", ")
            return (nil, "No reminder list named \"\(name)\". Available lists: \(available)")
        }
        return (match, nil)
    }

    func createReminder(
        title: String,
        dueDateSpec: String?,
        notes: String?,
        listName: String?
    ) async -> [String: RAToolValue] {
        if let refusal = await access().refusal {
            return ["error": RAToolValue(refusal), "created": RAToolValue(false)]
        }

        let (list, listError) = reminderList(named: listName)
        if let listError {
            return ["error": RAToolValue(listError), "created": RAToolValue(false)]
        }
        guard let list else {
            return [
                "error": RAToolValue("No default reminder list is configured on this device"),
                "created": RAToolValue(false)
            ]
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let notes, !notes.isEmpty {
            reminder.notes = notes
        }

        var dueText = "none"
        if let dueDateSpec, !dueDateSpec.isEmpty {
            guard let parsed = ToolDateParser.parse(dueDateSpec) else {
                return [
                    "error": RAToolValue(
                        "Could not parse due_date \"\(dueDateSpec)\" — use \"YYYY-MM-DD\" or \"YYYY-MM-DD HH:mm\""
                    ),
                    "created": RAToolValue(false)
                ]
            }
            var components: Set<Calendar.Component> = [.year, .month, .day]
            if parsed.hasTime {
                components.formUnion([.hour, .minute])
                // A timed reminder with no alarm never fires a notification;
                // a date-only one follows the Reminders app's all-day behaviour.
                reminder.addAlarm(EKAlarm(absoluteDate: parsed.date))
            }
            reminder.dueDateComponents = Calendar.current.dateComponents(components, from: parsed.date)
            dueText = ToolDateParser.display(parsed.date, hasTime: parsed.hasTime)
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            return ["error": RAToolValue(error.localizedDescription), "created": RAToolValue(false)]
        }

        return [
            "created": RAToolValue(true),
            "reminder_id": RAToolValue(reminder.calendarItemIdentifier),
            "title": RAToolValue(title),
            "due_date": RAToolValue(dueText),
            "list": RAToolValue(list.title)
        ]
    }

    private func predicate(status: String, dueWithinDays: Int?, lists: [EKCalendar]?) -> NSPredicate {
        let windowEnd = dueWithinDays.map {
            Calendar.current.date(byAdding: .day, value: max($0, 0), to: Date()) ?? Date()
        }
        switch status {
        case "completed":
            let windowStart = dueWithinDays.map {
                Calendar.current.date(byAdding: .day, value: -max($0, 0), to: Date()) ?? Date()
            }
            return store.predicateForCompletedReminders(
                withCompletionDateStarting: windowStart,
                ending: nil,
                calendars: lists
            )
        case "all":
            return store.predicateForReminders(in: lists)
        default:
            return store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: windowEnd,
                calendars: lists
            )
        }
    }

    func fetchReminders(
        status: String,
        dueWithinDays: Int?,
        listName: String?
    ) async -> [String: RAToolValue] {
        if let refusal = await access().refusal {
            return ["error": RAToolValue(refusal)]
        }

        var lists: [EKCalendar]?
        if let listName, !listName.isEmpty {
            let (list, listError) = reminderList(named: listName)
            if let listError {
                return ["error": RAToolValue(listError)]
            }
            lists = list.map { [$0] }
        }

        let matching = predicate(status: status, dueWithinDays: dueWithinDays, lists: lists)
        let reminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: matching) { continuation.resume(returning: $0 ?? []) }
        }

        func dueDate(of reminder: EKReminder) -> Date? {
            reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        }
        let sorted = reminders.sorted {
            (dueDate(of: $0) ?? .distantFuture) < (dueDate(of: $1) ?? .distantFuture)
        }
        let summaries = sorted.prefix(50).map { reminder -> String in
            var parts = [reminder.title ?? "Untitled"]
            if let due = dueDate(of: reminder) {
                parts.append("due \(ToolDateParser.display(due, hasTime: reminder.dueDateComponents?.hour != nil))")
            }
            if reminder.isCompleted {
                parts.append("completed")
            }
            if let list = reminder.calendar?.title {
                parts.append("list: \(list)")
            }
            return parts.joined(separator: ", ")
        }

        return [
            "reminder_count": RAToolValue(reminders.count),
            "reminders": RAToolValue(summaries.joined(separator: "; "))
        ]
    }
}

enum ReminderCreateTool {
    static var definition: ToolDefinition {
        ToolDefinition(
            name: "create_reminder",
            description: """
                Creates a reminder (a to-do) in the user's Reminders app. Use only when the \
                user explicitly asks to be reminded of something or to add a task ("remind \
                me to...", "add ... to my to-do list"). Today's date is \
                \(ToolDateParser.today()); compute any relative due date from that. On \
                success the result carries reminder_id and the list it was saved to; if the \
                result has "error", the reminder was NOT created — report the error instead \
                of claiming success.
                """,
            parameters: [
                ToolParameter(
                    name: "title",
                    type: .string,
                    description: "Short description of the task, e.g. \"Call the dentist\"."
                ),
                ToolParameter(
                    name: "due_date",
                    type: .string,
                    description: """
                        When the reminder is due, as "YYYY-MM-DD HH:mm" in local time, or \
                        "YYYY-MM-DD" for a day with no particular time. Omit for a reminder \
                        with no due date.
                        """,
                    required: false
                ),
                ToolParameter(
                    name: "notes",
                    type: .string,
                    description: "Optional extra detail to attach to the reminder.",
                    required: false
                ),
                ToolParameter(
                    name: "list_name",
                    type: .string,
                    description: """
                        Name of the reminder list to add to. Omit to use the default list; \
                        set it only when the user names one.
                        """,
                    required: false
                )
            ],
            category: "Reminders"
        )
    }

    static var executor: ToolExecutor {
        { args in
            guard let title = args["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return ["error": RAToolValue("Missing required \"title\" argument")]
            }
            return await RemindersManager.shared.createReminder(
                title: title,
                dueDateSpec: args["due_date"]?.string,
                notes: args["notes"]?.string,
                listName: args["list_name"]?.string
            )
        }
    }
}

enum ReminderListTool {
    static var definition: ToolDefinition {
        ToolDefinition(
            name: "get_reminders",
            description: """
                Gets the user's own reminders (to-dos) from the Reminders app. Use when the \
                user asks what is on their to-do list or what is due soon. Today's date is \
                \(ToolDateParser.today()). It returns incomplete reminders by default; pass \
                status "completed" or "all" only when the user asks about finished tasks. \
                State only reminders that literally appear in the result — if \
                reminder_count is 0, say the list is empty rather than inventing tasks.
                """,
            parameters: [
                ToolParameter(
                    name: "status",
                    type: .string,
                    description: """
                        Which reminders to return: "incomplete" (default), "completed", or \
                        "all".
                        """,
                    required: false,
                    enumValues: ["incomplete", "completed", "all"]
                ),
                ToolParameter(
                    name: "due_within_days",
                    type: .number,
                    description: """
                        Only return reminders due within this many days from now, e.g. 7 for \
                        "due this week". Omit to include reminders regardless of due date, \
                        including ones with none.
                        """,
                    required: false
                ),
                ToolParameter(
                    name: "list_name",
                    type: .string,
                    description: "Only return reminders from this named list. Omit to search all lists.",
                    required: false
                )
            ],
            category: "Reminders"
        )
    }

    static var executor: ToolExecutor {
        { args in
            await RemindersManager.shared.fetchReminders(
                status: args["status"]?.string?.lowercased() ?? "incomplete",
                dueWithinDays: args["due_within_days"]?.int,
                listName: args["list_name"]?.string
            )
        }
    }
}
