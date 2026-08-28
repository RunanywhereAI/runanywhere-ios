//
//  CalendarTools.swift
//  RunAnywhereAI
//
//  get_calendar_events / create_calendar_event / list_calendars — EventKit
//  calendars. One actor and one store behind all three, because EventKit
//  grants read and write together and a second store would mean a second
//  prompt for the same permission.
//

import EventKit
import Foundation
import RunAnywhere

actor CalendarManager {
    static let shared = CalendarManager()

    private let store = EKEventStore()
    private var granted = false

    /// Asked for at first use rather than at launch. EventKit traps rather
    /// than throwing when the Info.plist string is missing, so the usage
    /// description is not optional: `NSCalendarsFullAccessUsageDescription`
    /// is set on the app target.
    private func access() async -> ToolAccess {
        if granted { return .granted }
        if EKEventStore.authorizationStatus(for: .event) == .denied {
            return .refused(Self.deniedMessage)
        }
        do {
            granted = try await store.requestFullAccessToEvents()
        } catch {
            return .refused("Could not ask for Calendar access: \(error.localizedDescription)")
        }
        return granted ? .granted : .refused(Self.deniedMessage)
    }

    private static var deniedMessage: String {
        #if os(macOS)
        "Calendar access was refused. Allow it in System Settings > Privacy & Security > Calendars."
        #else
        "Calendar access was refused. Allow it in Settings > Privacy & Security > Calendars."
        #endif
    }

    private struct DateRange {
        let start: Date
        let end: Date
        let label: String
    }

    /// Explicit range wins, then a keyword, then a single explicit day, then
    /// today. A schedule question skews forward — "this week", "tomorrow" —
    /// which is why the keywords are the ones they are.
    private func resolveRange(dateSpec: String?, startDate: String?, endDate: String?) -> DateRange {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        func day(after date: Date) -> Date {
            calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        let effectiveStart = startDate ?? (endDate != nil ? dateSpec : nil)
        if let effectiveStart, let parsedStart = ToolDateParser.parse(effectiveStart) {
            let startDay = calendar.startOfDay(for: parsedStart.date)
            if let endDate, let parsedEnd = ToolDateParser.parse(endDate),
               calendar.startOfDay(for: parsedEnd.date) != startDay {
                let endDay = day(after: calendar.startOfDay(for: parsedEnd.date))
                return DateRange(
                    start: startDay,
                    end: max(endDay, startDay),
                    label: "\(effectiveStart) to \(endDate)"
                )
            }
            return DateRange(start: startDay, end: day(after: startDay), label: effectiveStart)
        }

        switch dateSpec?.lowercased() {
        case "tomorrow":
            let start = day(after: startOfToday)
            return DateRange(start: start, end: day(after: start), label: "tomorrow")
        case "this_week":
            let end = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? startOfToday
            return DateRange(start: startOfToday, end: max(end, startOfToday), label: "this_week")
        case "next_7_days":
            let end = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday
            return DateRange(start: startOfToday, end: end, label: "next_7_days")
        case .some(let explicitDay) where !explicitDay.isEmpty && explicitDay != "today":
            guard let parsed = ToolDateParser.parse(explicitDay) else {
                return DateRange(start: startOfToday, end: day(after: startOfToday), label: "today")
            }
            let start = calendar.startOfDay(for: parsed.date)
            return DateRange(start: start, end: day(after: start), label: explicitDay)
        default:
            return DateRange(start: startOfToday, end: day(after: startOfToday), label: "today")
        }
    }

    func fetchEvents(
        dateSpec: String?,
        startDate: String?,
        endDate: String?
    ) async -> [String: RAToolValue] {
        if let refusal = await access().refusal {
            return ["error": RAToolValue(refusal)]
        }

        let range = resolveRange(dateSpec: dateSpec, startDate: startDate, endDate: endDate)
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let summaries = events.map { event -> String in
            let timeText = event.isAllDay
                ? "all day"
                : "\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))"
            let locationText = event.location.map { " at \($0)" } ?? ""
            return "\(event.title ?? "Untitled") (\(timeText)\(locationText))"
        }

        return [
            "event_count": RAToolValue(events.count),
            "events": RAToolValue(summaries.joined(separator: "; ")),
            "date": RAToolValue(range.label)
        ]
    }

    struct EventRequest: Sendable {
        let title: String
        let startSpec: String
        let endSpec: String?
        let durationMinutes: Int?
        let notes: String?
        let location: String?
        let calendarName: String?
    }

    private func writableCalendar(named name: String?) -> (calendar: EKCalendar?, error: String?) {
        guard let name, !name.isEmpty else {
            return (store.defaultCalendarForNewEvents, nil)
        }
        let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
        guard let match = writable.first(where: {
            $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            let available = writable.map(\.title).joined(separator: ", ")
            return (nil, "No writable calendar named \"\(name)\". Writable calendars: \(available)")
        }
        return (match, nil)
    }

    private func resolveEnd(
        start: ToolDateParser.ParsedDate,
        endSpec: String?,
        durationMinutes: Int?
    ) -> (end: Date, error: String?) {
        if let endSpec, !endSpec.isEmpty {
            guard let parsedEnd = ToolDateParser.parse(endSpec), parsedEnd.date > start.date else {
                return (start.date, "end \"\(endSpec)\" must be a valid date-time after start")
            }
            return (parsedEnd.date, nil)
        }
        let minutes = max(durationMinutes ?? 60, 1)
        return (start.date.addingTimeInterval(TimeInterval(minutes) * 60), nil)
    }

    /// Returns the reason the request cannot be turned into an event, or nil
    /// once `event` carries all of it.
    private func fill(
        _ event: EKEvent,
        from request: EventRequest,
        start: ToolDateParser.ParsedDate
    ) -> String? {
        event.title = request.title
        if start.hasTime {
            let (end, endError) = resolveEnd(
                start: start,
                endSpec: request.endSpec,
                durationMinutes: request.durationMinutes
            )
            if let endError { return endError }
            event.startDate = start.date
            event.endDate = end
        } else {
            event.isAllDay = true
            event.startDate = start.date
            event.endDate = start.date
        }
        if let notes = request.notes, !notes.isEmpty {
            event.notes = notes
        }
        if let location = request.location, !location.isEmpty {
            event.location = location
        }
        return nil
    }

    func createEvent(_ request: EventRequest) async -> [String: RAToolValue] {
        if let refusal = await access().refusal {
            return ["error": RAToolValue(refusal), "created": RAToolValue(false)]
        }
        guard let start = ToolDateParser.parse(request.startSpec) else {
            return [
                "error": RAToolValue(
                    "Could not parse start \"\(request.startSpec)\" — use \"YYYY-MM-DD HH:mm\" or \"YYYY-MM-DD\""
                ),
                "created": RAToolValue(false)
            ]
        }
        let (calendar, calendarError) = writableCalendar(named: request.calendarName)
        if let calendarError {
            return ["error": RAToolValue(calendarError), "created": RAToolValue(false)]
        }
        guard let calendar else {
            return [
                "error": RAToolValue("No default calendar is configured on this device"),
                "created": RAToolValue(false)
            ]
        }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        if let error = fill(event, from: request, start: start) {
            return ["error": RAToolValue(error), "created": RAToolValue(false)]
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            return ["error": RAToolValue(error.localizedDescription), "created": RAToolValue(false)]
        }

        return [
            "created": RAToolValue(true),
            "event_id": RAToolValue(event.eventIdentifier ?? ""),
            "title": RAToolValue(request.title),
            "start": RAToolValue(ToolDateParser.display(event.startDate, hasTime: start.hasTime)),
            "end": RAToolValue(ToolDateParser.display(event.endDate, hasTime: start.hasTime)),
            "calendar": RAToolValue(calendar.title)
        ]
    }

    func fetchCalendars() async -> [String: RAToolValue] {
        if let refusal = await access().refusal {
            return ["error": RAToolValue(refusal)]
        }
        let calendars = store.calendars(for: .event)
        let summaries = calendars.map { calendar in
            calendar.allowsContentModifications ? calendar.title : "\(calendar.title) (read-only)"
        }
        return [
            "calendar_count": RAToolValue(calendars.count),
            "calendars": RAToolValue(summaries.joined(separator: "; ")),
            "default_calendar": RAToolValue(store.defaultCalendarForNewEvents?.title ?? "none")
        ]
    }
}

enum CalendarEventsTool {
    static var definition: ToolDefinition {
        ToolDefinition(
            name: "get_calendar_events",
            description: """
                Gets the user's own Calendar events — meetings, appointments, plans — for a \
                day or a date range. Use whenever the user asks about their schedule, what \
                is on their calendar, upcoming meetings, or free time. Today's date is \
                \(ToolDateParser.today()); treat that as the only source of truth for \
                "today". This tool sees no other person's calendar. State only events that \
                literally appear in the result — if event_count is 0, say the schedule is \
                free rather than inventing an event. If the result has "error", Calendar \
                could not be read at all.
                """,
            parameters: [
                ToolParameter(
                    name: "date",
                    type: .string,
                    description: """
                        Which period to check: a keyword — "today" (default), "tomorrow", \
                        "this_week", "next_7_days" — or a specific day as "YYYY-MM-DD". For \
                        a custom multi-day range use start_date and end_date instead.
                        """,
                    required: false
                ),
                ToolParameter(
                    name: "start_date",
                    type: .string,
                    description: """
                        Start of a custom date range, as "YYYY-MM-DD". Overrides `date` when \
                        set. Pair with end_date for a multi-day range, or omit end_date to \
                        query that one day.
                        """,
                    required: false
                ),
                ToolParameter(
                    name: "end_date",
                    type: .string,
                    description: """
                        End of the custom date range, inclusive, as "YYYY-MM-DD". Only used \
                        together with start_date.
                        """,
                    required: false
                )
            ],
            category: "Calendar"
        )
    }

    static var executor: ToolExecutor {
        { args in
            await CalendarManager.shared.fetchEvents(
                dateSpec: args["date"]?.string,
                startDate: args["start_date"]?.string,
                endDate: args["end_date"]?.string
            )
        }
    }
}

enum CalendarCreateTool {
    static var definition: ToolDefinition {
        ToolDefinition(
            name: "create_calendar_event",
            description: """
                Creates a new event in the user's own Calendar. Use only when the user \
                explicitly asks to schedule, book, or add something ("schedule a meeting \
                tomorrow at 3pm", "put lunch with Sam on my calendar") — never as a side \
                effect of answering. Today's date is \(ToolDateParser.today()); compute \
                "tomorrow" or "next Tuesday" from that. This tool does not check for \
                clashes, so read the day with get_calendar_events first when picking a slot \
                around existing events. If the result has "error", the event was NOT \
                created — report the error instead of claiming success.
                """,
            parameters: [
                ToolParameter(
                    name: "title",
                    type: .string,
                    description: "Event title as it should appear in the calendar, e.g. \"Lunch with Sam\"."
                ),
                ToolParameter(
                    name: "start",
                    type: .string,
                    description: """
                        Event start as "YYYY-MM-DD HH:mm" in local time. Pass a bare \
                        "YYYY-MM-DD" to create an all-day event instead.
                        """
                ),
                ToolParameter(
                    name: "end",
                    type: .string,
                    description: """
                        Event end as "YYYY-MM-DD HH:mm", after start. Omit to use \
                        duration_minutes. Ignored for all-day events.
                        """,
                    required: false
                ),
                ToolParameter(
                    name: "duration_minutes",
                    type: .number,
                    description: """
                        Event length in minutes when "end" is not given. Defaults to 60. \
                        Ignored for all-day events.
                        """,
                    required: false
                ),
                ToolParameter(
                    name: "notes",
                    type: .string,
                    description: "Optional notes to attach to the event.",
                    required: false
                ),
                ToolParameter(
                    name: "location",
                    type: .string,
                    description: "Optional location, e.g. \"Cafe Roma\" or a street address.",
                    required: false
                ),
                ToolParameter(
                    name: "calendar_name",
                    type: .string,
                    description: """
                        Name of the calendar to add the event to, matching a name from \
                        list_calendars. Omit to use the default calendar.
                        """,
                    required: false
                )
            ],
            category: "Calendar"
        )
    }

    static var executor: ToolExecutor {
        { args in
            guard let title = args["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return ["error": RAToolValue("Missing required \"title\" argument")]
            }
            guard let startSpec = args["start"]?.string, !startSpec.isEmpty else {
                return ["error": RAToolValue("Missing required \"start\" argument")]
            }
            return await CalendarManager.shared.createEvent(
                CalendarManager.EventRequest(
                    title: title,
                    startSpec: startSpec,
                    endSpec: args["end"]?.string,
                    durationMinutes: args["duration_minutes"]?.int,
                    notes: args["notes"]?.string,
                    location: args["location"]?.string,
                    calendarName: args["calendar_name"]?.string
                )
            )
        }
    }
}

enum CalendarListTool {
    static var definition: ToolDefinition {
        ToolDefinition(
            name: "list_calendars",
            description: """
                Lists the calendars on this device — "Home", "Work", subscribed calendars — \
                marking the read-only ones, plus the calendar new events go to by default. \
                Use before create_calendar_event when the user names a specific calendar, \
                or when they ask what calendars they have. Name only calendars that appear \
                in the result. Events cannot be created on one marked read-only.
                """,
            parameters: [],
            category: "Calendar"
        )
    }

    static var executor: ToolExecutor {
        { _ in
            await CalendarManager.shared.fetchCalendars()
        }
    }
}
