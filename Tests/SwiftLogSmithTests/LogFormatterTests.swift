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
    var expectation: XCTestExpectation?
    
    func log(message: LogMessage) {
        lastLoggedMessage = formatter.format(message: message)
        expectation?.fulfill()
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
        let expectation = XCTestExpectation(description: "Default formatter output should match expected format")
        mockLogger.expectation = expectation
        mockLogger.formatter = LogFormatter.default // Use the default formatter
        
        // 1. Setup deterministic mock data
        let mockDateString = "20251205103000123"
        let message = "This is a default message"
        let metadata: [String: String] = ["status": "ok"]
        
        // 2. Add tags in the order the default formatter expects to process them
        LogSmith.addTag(ExternalTag(identifier: LogTagIdentifiers.date, value: mockDateString))
        LogSmith.addTag(InternalTag(internalTagType: .file))
        LogSmith.addTag(InternalTag(internalTagType: .function))
        LogSmith.addTag(InternalTag(internalTagType: .line))
        
        // 3. Log the message and capture the line number for the assertion
        let fileName = #fileID
        let functionName = #function
        let line = #line + 1 // This must point to the next line
        LogSmith.logI(message, metadata: metadata)
        
        wait(for: [expectation], timeout: 2.0)

        // 4. Construct the exact expected output string
        // The default format is: Date | [file, function, line] | [LogType] | Message | Metadata
        let expectedSystemTags = "[file: \(fileName), function: \(functionName), line: \(line)]"
        let expectedOutput = "\(mockDateString) \(expectedSystemTags) [I] \(message) [\"status\": \"ok\"]"
        
        let loggedOutput = try XCTUnwrap(mockLogger.lastLoggedMessage)

        // 5. Assert exact string equality
        XCTAssertEqual(loggedOutput, expectedOutput)
        
        // Cleanup
        LogSmith.removeTag(identifier: "Date")
        LogSmith.removeTag(identifier: "file")
        LogSmith.removeTag(identifier: "function")
        LogSmith.removeTag(identifier: "line")
    }
    
    func testMessagePartFormat() throws {
        let expectation = XCTestExpectation(description: "MessagePart should produce empty string for empty message")
        mockLogger.expectation = expectation
        
        let emptyMessageFormatter = LogFormatter.Builder()
            .addMessagePart(prefix: "START[", suffix: "]END")
            .build()
        
        mockLogger.formatter = emptyMessageFormatter
        LogSmith.log("") // Log an empty message
        
        wait(for: [expectation], timeout: 2.0)
        
        let loggedOutput = try XCTUnwrap(mockLogger.lastLoggedMessage)
        XCTAssertEqual(loggedOutput, "") // Expect empty output for empty message
        
        // Test with a non-empty message to ensure formatter works correctly
        let nonEmptyMessageExpectation = XCTestExpectation(description: "MessagePart should work with non-empty message")
        mockLogger.expectation = nonEmptyMessageExpectation
        LogSmith.log("Hello")
        wait(for: [nonEmptyMessageExpectation], timeout: 2.0)
        let loggedOutputNonEmpty = try XCTUnwrap(mockLogger.lastLoggedMessage)
        XCTAssertEqual(loggedOutputNonEmpty, "START[Hello]END")
    }
    
    func testMetadataPartFormat() throws {
        let expectation = XCTestExpectation(description: "MetadataPart should correctly format and include metadata")
        mockLogger.expectation = expectation
        
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
        
        mockLogger.formatter = metadataFormatter
        
        let message = "Test message with metadata"
        LogSmith.log(message, metadata: testMetadata)
        
        wait(for: [expectation], timeout: 2.0)
        
        let loggedOutput = try XCTUnwrap(mockLogger.lastLoggedMessage)
        XCTAssertEqual(loggedOutput, "\(message)\(expectedMetadataString)")
        
        // Test with empty metadata - should produce no metadata part
        let emptyMetadataExpectation = XCTestExpectation(description: "MetadataPart should produce empty string for empty metadata")
        mockLogger.expectation = emptyMetadataExpectation
        
        // Re-use the same formatter configured for a space prefix.
        // If metadata is empty, the MetadataPart should return "" (including its prefix).
        mockLogger.formatter = metadataFormatter
        LogSmith.log("Message without metadata")
        wait(for: [emptyMetadataExpectation], timeout: 2.0)
        let loggedOutputEmpty = try XCTUnwrap(mockLogger.lastLoggedMessage)
        XCTAssertEqual(loggedOutputEmpty, "Message without metadata")
    }
    
    func testSingleTagPartFormat() throws {
        let expectation = XCTestExpectation(description: "Log message should be formatted using the new nested builder")
        mockLogger.expectation = expectation
        
        // 1. Use the nested builder to create a custom format.
        // Format: "MESSAGE - <ID:TAG_VALUE>"
        let builderFormatter = LogFormatter.Builder()
            .addMessagePart()
            .addTagsPart(
                prefix: " - <",
                format: { "\($0.identifier):\($0.value)" },
                suffix: ">",
                filter: { $0.identifier == "TestTag" }
            )
            .build()
        
        // 2. Set the new formatter on our mock logger.
        mockLogger.formatter = builderFormatter
        
        // 3. Add a tag.
        LogSmith.addTag(ExternalTag(identifier: "TestTag", value: "BuilderTest"))
        
        // 4. Log the message.
        let message = "Builder message"
        LogSmith.log(message)
        
        // 5. Wait for the async log to complete and assert the result.
        wait(for: [expectation], timeout: 2.0)
        
        let loggedOutput = try XCTUnwrap(mockLogger.lastLoggedMessage)
        let expectedOutput = "Builder message - <TestTag:BuilderTest>"
        XCTAssertEqual(loggedOutput, expectedOutput)
        
        // Cleanup
        LogSmith.removeTag(identifier: "TestTag")
    }
    
    func testMultipleTagsPartFormat() throws {
        let expectation = XCTestExpectation(description: "Tags should be consumed by earlier parts and not duplicated")
        mockLogger.expectation = expectation
        
        // Formatter with two tag parts:
        // 1. A specific part for "InternalTag"
        // 2. A specific part for "OtherTag"
        let consumingFormatter = LogFormatter.Builder()
            .addTagsPart(
                prefix: "[",
                format: { "\($0.identifier.prefix(1)):\($0.value)" }, // e.g., I:Value1
                suffix: "]",
                filter: { $0.identifier == "InternalTag" }
            )
            .addTagsPart(
                prefix: " ", // Space prefix to separate from first tag part
                format: { "\($0.identifier):\($0.value)" },
                separator: ", ",
                filter: { $0.identifier == "OtherTag" } // Make filter specific
            )
            .addMessagePart(prefix: " ")
            .build()
        
        mockLogger.formatter = consumingFormatter
        
        // Add custom key-value tags using the correct ExternalTag class
        LogSmith.addTag(ExternalTag(identifier: "InternalTag", value: "Value1")) // Should be consumed by the first part
        LogSmith.addTag(ExternalTag(identifier: "OtherTag", value: "Value2"))    // Should be consumed by the second part

        LogSmith.log("Message")
        
        wait(for: [expectation], timeout: 2.0)
        
        let loggedOutput = try XCTUnwrap(mockLogger.lastLoggedMessage)

        // Construct the exact expected output string
        let expectedOutput = "[I:Value1] OtherTag:Value2 Message"

        XCTAssertEqual(loggedOutput, expectedOutput)

        // Cleanup
        LogSmith.removeTag(identifier: "InternalTag")
        LogSmith.removeTag(identifier: "OtherTag")
    }
    
}
