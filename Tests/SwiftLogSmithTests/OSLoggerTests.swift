//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import SwiftLogSmith

final class OSLoggerTests: XCTestCase {

    func testInit_WithDefaultValues_ShouldSucceed() {
        let logger = OSLogger()
        XCTAssertNotNil(logger)
    }

    func testInit_WithCustomSubsystemAndCategory_ShouldSucceed() {
        let logger = OSLogger(subsystem: "com.example.test", category: "testing")
        XCTAssertNotNil(logger)
    }

    func testLog_WithAllLogTypes_ShouldExecuteWithoutError() {

        let logger = OSLogger(subsystem: "com.example.test", category: "testing")
        let types = LogType.allCases.filter { $0 != LogType.undefined }
        
        expectCompletion(description: "All logs should complete", fulfillmentCount: types.count) { fulfill in
            types.forEach { type in
                logger.log(message: LogMessage(message: "Test message for \(type)", logType: type, tags: [], metadata: [:])) { success in
                    XCTAssertTrue(success)
                    fulfill()
                }
            }
        }
    }

    func testLog_WithUndefinedLogType_ShouldReturnFalse() {

        let logger = OSLogger()
        let message = LogMessage(message: "Undefined test", logType: .undefined, tags: [], metadata: [:])
        
        expectCompletion(description: "Completion should return false") { fulfill in
            logger.log(message: message) { success in
                XCTAssertFalse(success)
                fulfill()
            }
        }
    }
}
