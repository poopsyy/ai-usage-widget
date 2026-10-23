import Foundation

/// Replays a bounded terminal screen instead of matching erased quota text in a transcript.
public enum ClaudeCLIScreen {
    public static func render(_ text: String, rows: Int = 200, columns: Int = 160) -> String {
        var cells = Array(repeating: Array(repeating: Character(" "), count: columns), count: rows)
        var row = 0, column = 0, savedRow = 0, savedColumn = 0
        let chars = Array(text)
        var index = 0
        func clamp(_ value: Int, _ maximum: Int) -> Int { max(0, min(maximum - 1, value)) }
        func newline() {
            row += 1
            if row >= rows { cells.removeFirst(); cells.append(Array(repeating: " ", count: columns)); row = rows - 1 }
        }
        while index < chars.count {
            let char = chars[index]; index += 1
            if char == "\u{1b}" {
                guard index < chars.count else { break }
                let kind = chars[index]; index += 1
                if kind == "[" {
                    var parameter = ""
                    while index < chars.count {
                        let value = chars[index]; index += 1
                        if let scalar = value.asciiValue, (0x40...0x7e).contains(scalar) {
                            let values = parameter.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                            let first = values.first ?? 0; let amount = max(1, first)
                            switch value {
                            case "A": row = clamp(row - amount, rows)
                            case "B": row = clamp(row + amount, rows)
                            case "C": column = clamp(column + amount, columns)
                            case "D": column = clamp(column - amount, columns)
                            case "G": column = clamp(amount - 1, columns)
                            case "d": row = clamp(amount - 1, rows)
                            case "H", "f": row = clamp(amount - 1, rows); column = clamp((values.count > 1 ? max(1, values[1]) : 1) - 1, columns)
                            case "J":
                                if first == 2 || first == 3 { cells = Array(repeating: Array(repeating: " ", count: columns), count: rows) }
                                else if first == 0 {
                                    for r in row..<rows { for c in (r == row ? column : 0)..<columns { cells[r][c] = " " } }
                                } else if first == 1 {
                                    for r in 0...row { for c in 0..<(r == row ? min(columns, column + 1) : columns) { cells[r][c] = " " } }
                                }
                            case "K":
                                let range = first == 2 ? 0..<columns : (first == 1 ? 0..<min(columns, column + 1) : min(column, columns)..<columns)
                                for c in range { cells[row][c] = " " }
                            case "s": savedRow = row; savedColumn = column
                            case "u": row = savedRow; column = savedColumn
                            default: break // SGR, cursor visibility, queries, and private modes do not write text.
                            }
                            break
                        }
                        parameter.append(value)
                    }
                } else if kind == "]" || kind == "P" {
                    while index < chars.count {
                        if chars[index] == "\u{7}" { index += 1; break }
                        if chars[index] == "\u{1b}", index + 1 < chars.count, chars[index + 1] == "\\" { index += 2; break }
                        index += 1
                    }
                } else if kind == "7" { savedRow = row; savedColumn = column }
                else if kind == "8" { row = savedRow; column = savedColumn }
                continue
            }
            if char == "\r\n" { column = 0; newline(); continue }
            switch char {
            case "\r": column = 0
            case "\n": newline()
            case "\u{8}": column = max(0, column - 1)
            case "\t": column = min(columns - 1, ((column / 8) + 1) * 8)
            default:
                guard char.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else { continue }
                if column >= columns { column = 0; newline() }
                cells[row][column] = char; column += 1
            }
        }
        return cells.map { String($0).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
}

public enum ClaudeCLIUsage {
    public static func snapshot(screen: String, at now: Date = Date()) throws -> UsageSnapshot {
        var windows: [UsageWindow] = []
        var pending: (id: String, title: String)?
        var used: Double?
        var reset: Date?
        func finish() {
            if let pending, let used { windows.append(UsageWindow(id: pending.id, title: pending.title, usedPercent: used, resetsAt: reset)) }
            used = nil; reset = nil
        }
        for raw in screen.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if lower.hasPrefix("session stats") || lower.hasPrefix("usage insights") || lower.hasPrefix("extra usage") {
                finish(); pending = nil; continue
            }
            if lower.hasPrefix("current session") || lower.hasPrefix("current week") {
                finish()
                if lower.hasPrefix("current session") { pending = ("five_hour", "Session") }
                else if lower.contains("sonnet") { pending = ("seven_day_sonnet", "Weekly · Sonnet") }
                else if lower.contains("opus") { pending = ("seven_day_opus", "Weekly · Opus") }
                else if !lower.contains("(") || lower.contains("all models") { pending = ("seven_day", "Weekly") }
                else { pending = nil }
            }
            guard pending != nil else { continue }
            if let groups = match(percentPattern, line),
               let percent = Double(groups[0]), (0...100).contains(percent) {
                let value = groups[1].lowercased() == "remaining" ? 100 - percent : percent
                if let used, used != value { throw AgentError.invalidResponse(.claude) }
                used = value
            }
            if lower.contains("reset") { reset = resetDate(line, at: now) }
        }
        finish()
        guard !windows.isEmpty else { throw AgentError.unsupported(.claude) }
        guard Set(windows.map(\.id)).count == windows.count else { throw AgentError.invalidResponse(.claude) }
        return UsageSnapshot(provider: .claude, observedAt: now, windows: windows)
    }
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
    private static let percentPattern = regex(#"(?:^|\s)(\d+(?:\.\d+)?)%\s*(used|remaining|of limit used)\b"#)
    private static let isoPattern = regex(#"(\d{4}-\d\d-\d\d[T ]\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d))"#)
    private static let relativePattern = regex(#"resets?\s+in\s+(?:(\d+)h\s*)?(?:(\d+)m\s*)?(?:(\d+)s)?\s*$"#)
    private static let labelPattern = regex(#"resets\s+(.+?)(?:\s+\(([A-Za-z_]+(?:/[A-Za-z0-9_+\-]+)*)\))?\s*$"#)
    private static let timePattern = regex(#"^(\d{1,2})(?::(\d\d))?(am|pm)$"#)
    private static let datePattern = regex(#"^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec) (\d{1,2})(?:, (\d{4}))?, (\d{1,2})(?::(\d\d))?(am|pm)$"#)
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let fractionalISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter
    }()
    private static let plainISO = ISO8601DateFormatter()

    private static func match(_ regex: NSRegularExpression, _ text: String) -> [String]? {
        guard let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<result.numberOfRanges).map { Range(result.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
    private static func resetDate(_ text: String, at now: Date) -> Date? {
        if let groups = match(isoPattern, text) {
            let value = groups[0].replacingOccurrences(of: " ", with: "T")
            return fractionalISO.date(from: value) ?? plainISO.date(from: value)
        }
        // Relative durations are provider-reported.
        if let groups = match(relativePattern, text) {
            let hours = Double(groups[0]) ?? 0
            let minutes = Double(groups[1]) ?? 0
            let seconds = hours * 3600 + minutes * 60 + (Double(groups[2]) ?? 0)
            if seconds > 0 { return now.addingTimeInterval(seconds) }
        }
        // Claude Code labels: "3pm (Zone)" within a day, "Oct 30, 9am (Zone)" or "Jan 2, 2027, 9am (Zone)" otherwise.
        // Date-only and weekday labels stay unknown.
        guard let groups = match(labelPattern, text) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: groups[1]) ?? .current
        let label = groups[0].replacingOccurrences(of: "\u{202f}", with: "").lowercased()
        func hour(_ value: String, _ meridiem: String) -> Int? {
            guard let value = Int(value), (1...12).contains(value) else { return nil }
            return value % 12 + (meridiem == "pm" ? 12 : 0)
        }
        if let time = match(timePattern, label), let hour = hour(time[0], time[2]) {
            let minute = Int(time[1]) ?? 0
            guard minute < 60 else { return nil }
            return calendar.nextDate(after: now.addingTimeInterval(-60), matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime)
        }
        if let date = match(datePattern, label), let month = months.firstIndex(of: date[0]), let day = Int(date[1]), let hour = hour(date[3], date[5]) {
            let minute = Int(date[4]) ?? 0
            guard minute < 60 else { return nil }
            let explicitYear = Int(date[2])
            var components = DateComponents(year: explicitYear ?? calendar.component(.year, from: now), month: month + 1, day: day, hour: hour, minute: minute)
            guard var result = calendar.date(from: components) else { return nil }
            if explicitYear == nil, result < now.addingTimeInterval(-86400) {
                components.year = (components.year ?? 0) + 1
                guard let next = calendar.date(from: components) else { return nil }
                result = next
            }
            return result
        }
        return nil
    }
}
