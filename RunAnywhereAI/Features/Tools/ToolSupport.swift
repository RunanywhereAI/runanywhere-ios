//
//  ToolSupport.swift
//  RunAnywhereAI
//
//  Shared helpers for the app's own tools: the date-string contract every
//  scheduling tool holds the model to, and the permission gate the EventKit
//  tools share.
//

import Foundation

/// One date-string contract for every tool that accepts a date from the
/// model: "YYYY-MM-DD HH:mm" in local time, or a bare "YYYY-MM-DD" day.
/// ISO 8601 with an explicit offset is accepted too, because models emit it
/// whatever the parameter description says.
enum ToolDateParser {
    struct ParsedDate {
        let date: Date
        let hasTime: Bool
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        return formatter
    }

    private static let dateTimeFormats = [
        makeFormatter("yyyy-MM-dd HH:mm"),
        makeFormatter("yyyy-MM-dd HH:mm:ss"),
        makeFormatter("yyyy-MM-dd'T'HH:mm"),
        makeFormatter("yyyy-MM-dd'T'HH:mm:ss")
    ]
    private static let dayFormat = makeFormatter("yyyy-MM-dd")
    private static let displayFormat = makeFormatter("yyyy-MM-dd HH:mm")
    private static let isoFormat = ISO8601DateFormatter()

    static func parse(_ spec: String) -> ParsedDate? {
        let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in dateTimeFormats {
            if let date = formatter.date(from: trimmed) {
                return ParsedDate(date: date, hasTime: true)
            }
        }
        if let date = isoFormat.date(from: trimmed) {
            return ParsedDate(date: date, hasTime: true)
        }
        if let date = dayFormat.date(from: trimmed) {
            return ParsedDate(date: date, hasTime: false)
        }
        return nil
    }

    static func display(_ date: Date, hasTime: Bool = true) -> String {
        hasTime ? displayFormat.string(from: date) : dayFormat.string(from: date)
    }

    static func today() -> String {
        dayFormat.string(from: Date())
    }

    static func utcOffsetString(for date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let hours = abs(seconds) / 3600
        let minutes = (abs(seconds) % 3600) / 60
        return String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", hours, minutes)
    }
}

/// Where a permission-gated tool stands with the system.
///
/// A refusal is a result the caller reports, never a thrown error and never a
/// trap: a tool that runs inside a workflow node or a generation loop has to
/// come back with something the model or the run log can read.
enum ToolAccess {
    case granted
    case refused(String)

    var refusal: String? {
        if case .refused(let message) = self { return message }
        return nil
    }
}
