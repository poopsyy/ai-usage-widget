import Foundation

enum CheckFailure: Error { case missingValue }
enum CheckLog {
    static var failures = 0
    static func record(_ message: String, file: StaticString, line: UInt) {
        failures += 1
        fputs("FAIL \(file):\(line): \(message)\n", stderr)
    }
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { CheckLog.record("\(actual) != \(expected)", file: file, line: line) }
}
func expectTrue(_ condition: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !condition { CheckLog.record("Expected true", file: file, line: line) }
}
func expectFalse(_ condition: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if condition { CheckLog.record("Expected false", file: file, line: line) }
}
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { CheckLog.record("Expected nil", file: file, line: line) }
}
func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); CheckLog.record("Expected an error", file: file, line: line) } catch {}
}
func require<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure.missingValue }
    return value
}
func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    CheckLog.record(message, file: file, line: line)
}
