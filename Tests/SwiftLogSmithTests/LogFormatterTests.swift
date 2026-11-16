//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest
import Foundation
@testable import SwiftLogSmith

final class MockLogger: ILogger, @unchecked Sendable {
    var tagger: LogTagger? = nil
    var formatter: LogFormatter = LogFormatter.default
    
    var lastLoggedMessage: String?
    var lastLogMessage: LogMessage?
    
    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
        lastLogMessage = message
        lastLoggedMessage = formatter.format(message: message)
        completion?(true)
    }
}

extension ISO8601DateFormatter {
    /// Reads the value of a timestamp tag: ISO 8601 with milliseconds.
    static var withFractionalSeconds: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

final class LogFormatterTests: XCTestCase {
    var mockLogger: MockLogger!
    
    override func setUp() {
        super.setUp()
        mockLogger = MockLogger()
        // We add our mock logger for testing.
        LogSmith.addLogger(newLogger: mockLogger)
    }
    
    override func tearDown() {
        LogSmith.removeLogger(logger: mockLogger)
        mockLogger = nil
        super.tearDown()
    }
    
    func testDefaultFormat() throws {
        let logger = mockLogger!
        logger.formatter = LogFormatter.default // Use the default formatter
        
        // 1. Setup deterministic mock data
        let message = "This is a default message"
        let metadata: [String: String] = ["status": "ok"]
        
        // 2. Add tags in the order the default formatter expects to process them
        LogSmith.addTag(InternalTag(internalTagType: .timestamp))
        LogSmith.addTag(InternalTag(internalTagType: .file))
        LogSmith.addTag(InternalTag(internalTagType: .function))
        LogSmith.addTag(InternalTag(internalTagType: .line))
        
        // 3. Log the message and capture the line number for the assertion
        let fileName = #fileID
        let functionName = #function
        
        expectCompletion(description: "Default formatter output should match expected format") { fulfill in
            let line = #line + 1
            LogSmith.logI(message, metadata: metadata) { _ in
                // 4. Construct the exact expected output string
                // The default format is: Timestamp | [file, function, line] | [LogType] | Message | Metadata
                let expectedTimestamp = Self.displayTimestamp(logger.lastLogMessage?.timestamp ?? .distantPast)
                let expectedSystemTags = "[file: \(fileName), function: \(functionName), line: \(line)]"
                let expectedOutput = "\(expectedTimestamp) \(expectedSystemTags) [I] \(message) [\"status\": \"ok\"]"
                
                let loggedOutput = logger.lastLoggedMessage
                
                // 5. Assert exact string equality
                XCTAssertEqual(loggedOutput, expectedOutput)
                fulfill()
            }
        }
        
        // Cleanup
        LogSmith.removeTag(identifier: LogTagIdentifiers.timestamp)
        LogSmith.removeTag(identifier: "file")
        LogSmith.removeTag(identifier: "function")
        LogSmith.removeTag(identifier: "line")
    }

    func testDefaultFormat_WithUserDateTag_ShouldPrintItWithExternalTags() throws {
        // A date tag added by the user before the timestamp tag existed is no longer printed first, but it isn't lost.
        let logger = mockLogger!
        logger.formatter = LogFormatter.default
        LogSmith.addTag(ExternalTag(identifier: "date", value: "legacy-date"))

        expectCompletion(description: "A user date tag should appear with the external tags") { fulfill in
            LogSmith.logI("Hello") { _ in
                XCTAssertEqual(logger.lastLoggedMessage, "[I] [legacy-date] Hello")
                fulfill()
            }
        }

        LogSmith.removeTag(identifier: "date")
    }

    func testDefaultFormat_WithExternalTagNamedTimestamp_ShouldNotPrintItAsTheTimestamp() throws {
        let logger = mockLogger!
        logger.formatter = LogFormatter.default
        LogSmith.addTag(ExternalTag(identifier: LogTagIdentifiers.timestamp, value: "not-a-time"))

        expectCompletion(description: "Only an internal timestamp tag should take the timestamp position") { fulfill in
            LogSmith.logI("Hello") { _ in
                XCTAssertEqual(logger.lastLoggedMessage, "[I] [not-a-time] Hello")
                fulfill()
            }
        }

        LogSmith.removeTag(identifier: LogTagIdentifiers.timestamp)
    }

    func testTagsPart_WithoutFormatForTimestampTag_ShouldPrintISO8601ValueInUTC() throws {
        let logger = mockLogger!
        logger.formatter = LogFormatter.Builder()
            .addTagsPart(filter: { $0.identifier == LogTagIdentifiers.timestamp })
            .build()
        LogSmith.addTag(InternalTag(internalTagType: .timestamp))

        expectCompletion(description: "A tag part with no format should fall back to the stored UTC value") { fulfill in
            LogSmith.logI("Hello") { _ in
                let output = logger.lastLoggedMessage ?? ""
                let timestamp = logger.lastLogMessage?.timestamp ?? .distantPast
                XCTAssertTrue(output.hasSuffix("Z"), "The stored value should be in UTC: \(output)")
                let parsed = ISO8601DateFormatter.withFractionalSeconds.date(from: output)
                XCTAssertNotNil(parsed, "The stored value should be ISO 8601: \(output)")
                XCTAssertLessThan(abs((parsed ?? .distantFuture).timeIntervalSince(timestamp)), 0.001)
                fulfill()
            }
        }

        LogSmith.removeTag(identifier: LogTagIdentifiers.timestamp)
    }

    /// Formats a date the way the default formatter shows the timestamp: local time with milliseconds and the UTC offset.
    private static func displayTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        return formatter.string(from: date)
    }

    func testMessagePartFormat() throws {
        let logger = mockLogger!
        let emptyMessageFormatter = LogFormatter.Builder()
            .addMessagePart(prefix: "START[", suffix: "]END")
            .build()
        
        logger.formatter = emptyMessageFormatter
        
        expectCompletion(description: "MessagePart should produce empty string for empty message") { fulfill in
            LogSmith.log("") { _ in
                let loggedOutput = logger.lastLoggedMessage
                XCTAssertEqual(loggedOutput, "") // Expect empty output for empty message
                fulfill()
            }
        }
        
        // Test with a non-empty message to ensure formatter works correctly
        expectCompletion(description: "MessagePart should work with non-empty message") { fulfill in
            LogSmith.log("Hello") { _ in
                let loggedOutputNonEmpty = logger.lastLoggedMessage
                XCTAssertEqual(loggedOutputNonEmpty, "START[Hello]END")
                fulfill()
            }
        }
    }
    
    func testMetadataPartFormat() throws {
        let logger = mockLogger!
        let testMetadata: [String: String] = ["user": "testUser", "id": "123"]
        
        // The format closure for metadata part sorts keys. Ensure expected string matches this.
        let expectedMetadataString = " metadata: [\"id\": \"123\", \"user\": \"testUser\"]"
        
        // Format: MESSAGE [METADATA]
        let metadataFormatter = LogFormatter.Builder()
            .addMessagePart()
            .addMetadataPart(
                prefix: " ", // Add a space before metadata
                format: { metadata in
                    // Sort the metadata keys to ensure consistent output string for testing
                    let sortedMetadata = metadata.sorted { $0.key < $1.key }
                    let metadataContent = sortedMetadata.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ")
                    return "metadata: [\(metadataContent)]"
                }
            )
            .build()
        
        logger.formatter = metadataFormatter
        
        let message = "Test message with metadata"
        
        expectCompletion(description: "MetadataPart should correctly format and include metadata") { fulfill in
            LogSmith.log(message, metadata: testMetadata) { _ in
                let loggedOutput = logger.lastLoggedMessage
                XCTAssertEqual(loggedOutput, "\(message)\(expectedMetadataString)")
                fulfill()
            }
        }
        
        // Test with empty metadata - should produce no metadata part
        // Re-use the same formatter configured for a space prefix.
        // If metadata is empty, the MetadataPart should return "" (including its prefix).
        logger.formatter = metadataFormatter
        
        expectCompletion(description: "MetadataPart should produce empty string for empty metadata") { fulfill in
            LogSmith.log("Message without metadata") { _ in
                let loggedOutputEmpty = logger.lastLoggedMessage
                XCTAssertEqual(loggedOutputEmpty, "Message without metadata")
                fulfill()
            }
        }
    }
    
    /// Renders `metadata` the way `addMetadataPart()` does when it is given no format of its own.
    private func renderedByDefault(_ metadata: [String: String]) -> String {
        let formatter = LogFormatter.Builder().addMetadataPart().build()
        return formatter.format(message: LogMessage(message: "", logType: .none, tags: [], metadata: metadata))
    }
    
    func testDefaultMetadataFormat_WithSeveralEntries_ShouldSortByKey() {
        XCTAssertEqual(renderedByDefault(["zebra": "1", "apple": "2", "mango": "3"]), #"["apple": "2", "mango": "3", "zebra": "1"]"#)
        XCTAssertEqual(renderedByDefault(["only": "one"]), #"["only": "one"]"#)
    }
    
    func testDefaultMetadataFormat_WithNoEntries_ShouldProduceNothing() {
        XCTAssertEqual(renderedByDefault([:]), "")
    }
    
    func testDefaultMetadataFormat_WithOneEntry_ShouldMatchHowSwiftPrintsTheDictionary() {
        // A single entry has no order to disagree about, so the text must be exactly what printing the dictionary gives,
        // escaping included.
        let values = ["plain", #"say "hi""#, #"C:\temp"#, "two\nlines", "tab\there", "emoji 😀", "", #"[nested=[x=1]]"#]
        
        for value in values {
            let metadata = ["key": value]
            XCTAssertEqual(renderedByDefault(metadata), "\(metadata)", "value: \(value)")
        }
    }
    
    func testDefaultMetadataFormat_WithEntriesInsertedInDifferentOrders_ShouldRenderTheSame() {
        // Arrange — the same entries added in opposite orders, which a plain dictionary may iterate differently.
        let keys = (0..<30).map { "key\($0)" }
        var forward: [String: String] = [:]
        var backward: [String: String] = [:]
        keys.forEach { forward[$0] = $0.uppercased() }
        keys.reversed().forEach { backward[$0] = $0.uppercased() }
        let expected = "[" + keys.sorted().map { #""\#($0)": "\#($0.uppercased())""# }.joined(separator: ", ") + "]"
        
        // Act & Assert
        XCTAssertEqual(renderedByDefault(forward), expected)
        XCTAssertEqual(renderedByDefault(backward), expected)
    }
    
    func testSingleTagPartFormat() throws {
        let logger = mockLogger!
        // 1. Use the nested builder to create a custom format.
        // Format: "MESSAGE - <ID:TAG_VALUE>"
        let builderFormatter = LogFormatter.Builder()
            .addMessagePart()
            .addTagsPart(
                prefix: " - <",
                format: { tag, _ in "\(tag.identifier):\(tag.value)" },
                suffix: ">",
                filter: { $0.identifier == "TestTag" }
            )
            .build()
        
        // 2. Set the new formatter on our mock logger.
        logger.formatter = builderFormatter
        
        // 3. Add a tag.
        LogSmith.addTag(ExternalTag(identifier: "TestTag", value: "BuilderTest"))
        
        // 4. Log the message.
        let message = "Builder message"
        
        expectCompletion(description: "Log message should be formatted using the new nested builder") { fulfill in
            LogSmith.log(message) { _ in
                let loggedOutput = logger.lastLoggedMessage
                let expectedOutput = "Builder message - <TestTag:BuilderTest>"
                XCTAssertEqual(loggedOutput, expectedOutput)
                fulfill()
            }
        }
        
        // Cleanup
        LogSmith.removeTag(identifier: "TestTag")
    }
    
    func testMultipleTagsPartFormat() throws {
        let logger = mockLogger!
        // Formatter with two tag parts:
        // 1. A specific part for "InternalTag"
        // 2. A specific part for "OtherTag"
        let consumingFormatter = LogFormatter.Builder()
            .addTagsPart(
                prefix: "[",
                format: { tag, _ in "\(tag.identifier.prefix(1)):\(tag.value)" }, // e.g., I:Value1
                suffix: "]",
                filter: { $0.identifier == "InternalTag" }
            )
            .addTagsPart(
                prefix: " ", // Space prefix to separate from first tag part
                format: { tag, _ in "\(tag.identifier):\(tag.value)" },
                separator: ", ",
                filter: { $0.identifier == "OtherTag" } // Make filter specific
            )
            .addMessagePart(prefix: " ")
            .build()
        
        logger.formatter = consumingFormatter
        
        // Add custom key-value tags using the correct ExternalTag class
        LogSmith.addTag(ExternalTag(identifier: "InternalTag", value: "Value1")) // Should be consumed by the first part
        LogSmith.addTag(ExternalTag(identifier: "OtherTag", value: "Value2"))    // Should be consumed by the second part

        expectCompletion(description: "Tags should be consumed by earlier parts and not duplicated") { fulfill in
            LogSmith.log("Message") { _ in
                let loggedOutput = logger.lastLoggedMessage
                // Construct the exact expected output string
                let expectedOutput = "[I:Value1] OtherTag:Value2 Message"
                XCTAssertEqual(loggedOutput, expectedOutput)
                fulfill()
            }
        }

        // Cleanup
        LogSmith.removeTag(identifier: "InternalTag")
        LogSmith.removeTag(identifier: "OtherTag")
    }

    func testTagsPartFormat_WithMessageArgument_ShouldReceiveTheMessageBeingFormatted() throws {
        let logger = mockLogger!
        logger.formatter = LogFormatter.Builder()
            .addTagsPart(format: { tag, message in "\(tag.value)@\(message.logType.stringValue):\(message.message)" },
                         filter: { $0.identifier == "MessageAwareTag" })
            .build()
        LogSmith.addTag(ExternalTag(identifier: "MessageAwareTag", value: "tag"))

        expectCompletion(description: "The format closure should see the message it formats") { fulfill in
            LogSmith.logW("hello") { _ in
                XCTAssertEqual(logger.lastLoggedMessage, "tag@warning:hello")
                fulfill()
            }
        }

        LogSmith.removeTag(identifier: "MessageAwareTag")
    }

}
