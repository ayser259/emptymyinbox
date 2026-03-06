import Foundation
import Testing
@testable import emptyMyInbox

struct TelemetryTests {
    @Test("Telemetry sanitizes sensitive metadata keys")
    func testTelemetrySanitizeMetadata() {
        let input = [
            "email": "user@example.com",
            "subject": "Secret subject",
            "model": "gpt-4o-mini"
        ]
        let sanitized = Telemetry.sanitizeMetadata(input)
        #expect(sanitized["email"] == "<redacted>")
        #expect(sanitized["subject"] == "<redacted>")
        #expect(sanitized["model"] == "gpt-4o-mini")
    }

    @Test("Telemetry redacts email addresses and API keys in text")
    func testTelemetryRedactPII() {
        let raw = "contact user@example.com with key sk-test-1234"
        let redacted = Telemetry.redactPII(in: raw)
        #expect(!redacted.contains("user@example.com"))
        #expect(!redacted.contains("sk-test-1234"))
        #expect(redacted.contains("<redacted>"))
    }
}
