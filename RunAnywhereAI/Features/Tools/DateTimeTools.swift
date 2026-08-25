//
//  DateTimeTools.swift
//  RunAnywhereAI
//
//  get_current_datetime / get_time_in_timezone — the device's own clock as
//  structured fields, and the same reading in another named timezone.
//

import Foundation
import RunAnywhere

enum DateTimeTool {
    static var definition: ToolDefinition {
        ToolDefinition(
            name: "get_current_datetime",
            description: """
                Gets the device's current date and time as structured fields: ISO 8601 \
                timestamp (with local UTC offset), calendar date, wall-clock time, weekday \
                name, ISO week number, timezone, and Unix timestamp. Use it whenever an \
                answer depends on today's date — computing "tomorrow" or "next Friday", \
                naming the weekday, or building a date for another tool. All values are \
                already in the device's local timezone, so do not apply the UTC offset to \
                them again. For another timezone use get_time_in_timezone.
                """,
            parameters: [],
            category: "Utility"
        )
    }

    static var executor: ToolExecutor {
        { _ in
            let now = Date()
            let timeZone = TimeZone.current

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.timeZone = timeZone

            var isoCalendar = Calendar(identifier: .iso8601)
            isoCalendar.timeZone = timeZone

            return [
                "iso_timestamp": RAToolValue(isoFormatter.string(from: now)),
                "date": RAToolValue(DateTimeFormat.string(now, "yyyy-MM-dd", timeZone)),
                "time": RAToolValue(DateTimeFormat.string(now, "HH:mm:ss", timeZone)),
                "weekday": RAToolValue(DateTimeFormat.string(now, "EEEE", timeZone)),
                "week_number": RAToolValue(isoCalendar.component(.weekOfYear, from: now)),
                "year": RAToolValue(isoCalendar.component(.yearForWeekOfYear, from: now)),
                "timezone": RAToolValue(timeZone.identifier),
                "utc_offset": RAToolValue(ToolDateParser.utcOffsetString(for: now, timeZone: timeZone)),
                "unix_timestamp": RAToolValue(Int(now.timeIntervalSince1970))
            ]
        }
    }
}

enum WorldClockTool {
    static var definition: ToolDefinition {
        ToolDefinition(
            name: "get_time_in_timezone",
            description: """
                Gets the current date and time in a specific timezone anywhere in the world. \
                Use when the user asks what time it is in another city, country, or timezone \
                (e.g. "what time is it in Tokyo"). Pass the IANA timezone identifier for the \
                place — map the city to its zone yourself, e.g. Tokyo -> "Asia/Tokyo", \
                New York -> "America/New_York", London -> "Europe/London". The result's \
                "time" and "date" are already local to that timezone; report them as-is \
                without converting. If the result contains "error", the identifier was not \
                recognised — try the canonical IANA name for the nearest major city.
                """,
            parameters: [
                ToolParameter(
                    name: "timezone",
                    type: .string,
                    description: """
                        IANA timezone identifier, e.g. "Asia/Tokyo", "America/New_York", \
                        "Europe/Paris", "Australia/Sydney". Common abbreviations like "UTC" \
                        or "GMT" also work.
                        """
                )
            ],
            category: "Utility"
        )
    }

    static var executor: ToolExecutor {
        { args in
            guard let identifier = args["timezone"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !identifier.isEmpty else {
                return ["error": RAToolValue("Missing required \"timezone\" argument")]
            }
            guard let timeZone = TimeZone(identifier: identifier) ?? TimeZone(abbreviation: identifier) else {
                return [
                    "error": RAToolValue(
                        "Unknown timezone \"\(identifier)\" — pass an IANA identifier like \"Asia/Tokyo\""
                    )
                ]
            }

            let now = Date()
            return [
                "timezone": RAToolValue(timeZone.identifier),
                "date": RAToolValue(DateTimeFormat.string(now, "yyyy-MM-dd", timeZone)),
                "time": RAToolValue(DateTimeFormat.string(now, "HH:mm", timeZone)),
                "weekday": RAToolValue(DateTimeFormat.string(now, "EEEE", timeZone)),
                "utc_offset": RAToolValue(ToolDateParser.utcOffsetString(for: now, timeZone: timeZone))
            ]
        }
    }
}

private enum DateTimeFormat {
    /// POSIX locale throughout: these fields are read by a model and by other
    /// tools, so "Monday" has to stay "Monday" whatever the device language is.
    static func string(_ date: Date, _ format: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
