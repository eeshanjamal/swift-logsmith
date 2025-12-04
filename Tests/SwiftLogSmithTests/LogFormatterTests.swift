//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest
import Foundation
@testable import SwiftLogSmith

final class MockLogger: ILogger, @unchecked Sendable {
    var logTagger: SwiftLogSmith.LogTagger? = nil
    var formatter: LogFormatter = LogFormatter.default
    
    var lastLoggedMessage: String?
    var expectation: XCTestExpectation?
    
    func log(message: SwiftLogSmith.LogMessage) {
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

    func testNestedLogFormatterBuilder() throws {
        let expectation = XCTestExpectation(description: "Log message should be formatted using the new nested builder")
        mockLogger.expectation = expectation

        // 1. Use the nested builder to create a custom format.
        // Format: "MESSAGE - <ID:TAG_VALUE>"
        let builderFormatter = LogFormatter.Builder()
            .addMessagePart()
            .addTagsPart(
                prefix: " - <", // Prefix now includes the separator and the bracket
                format: { "\($0.identifier):\($0.value)" },
                suffix: ">",
                filter: { $0.identifier == "TestTag" }
            )
            .build()
        
        // 2. Set the new formatter on our mock logger.
        mockLogger.formatter = builderFormatter

        // 3. Add a tag.
        LogSmith.addTag(InternalTag(identifier: "TestTag", value: "BuilderTest"))

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
}
