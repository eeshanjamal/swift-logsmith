//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import SwiftLogSmith

final class FirstMockLogger: ILogger, @unchecked Sendable {
    var tagger: LogTagger?
    var formatter: LogFormatter
    var lastLoggedMessage: LogMessage?
    var logCallCount = 0

    init(tagger: LogTagger? = nil, formatter: LogFormatter = LogFormatter.default) {
        self.tagger = tagger
        self.formatter = formatter
    }

    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
        lastLoggedMessage = message
        logCallCount += 1
        completion?(true)
    }
    
    func reset() {
        lastLoggedMessage = nil
        logCallCount = 0
    }
}

final class SecondMockLogger: ILogger, @unchecked Sendable {
    var tagger: LogTagger?
    var formatter: LogFormatter
    var lastLoggedMessage: LogMessage?
    var logCallCount = 0

    init(tagger: LogTagger? = nil, formatter: LogFormatter = LogFormatter.default) {
        self.tagger = tagger
        self.formatter = formatter
    }

    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
        lastLoggedMessage = message
        logCallCount += 1
        completion?(true)
    }
    
    func reset() {
        lastLoggedMessage = nil
        logCallCount = 0
    }
}

final class LogManagerTests: XCTestCase {

    var sut: LogManager!
    var mockDefaultLogger: FirstMockLogger!

    override func setUp() {
        super.setUp()
        mockDefaultLogger = FirstMockLogger()
        sut = LogManager(identifier: "TestManager", defaultLogger: mockDefaultLogger)
    }

    override func tearDown() {
        sut = nil
        mockDefaultLogger = nil
        super.tearDown()
    }

    func testInitialization_ShouldContainDefaultLogger() {
        let logger = mockDefaultLogger
        expectCompletion(description: "Default logger should receive log") { fulfill in
            sut.log(message: "test", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 1)
                fulfill()
            }
        }
    }

    func testAddLogger_WithNewLogger_ShouldSucceed() {
        let newLogger = SecondMockLogger()
        expectCompletion(description: "Add new logger") { fulfill in
            sut.addLogger(newLogger: newLogger) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
    
        // Verify both loggers receive the message
        let logger = mockDefaultLogger
        expectCompletion(description: "Both loggers should receive the log") { fulfill in
            sut.log(message: "test", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 1)
                XCTAssertEqual(newLogger.logCallCount, 1)
                fulfill()
            }
        }
    }

    func testLogLevelFiltering_ManagerLevel() {
        sut.setMinimumLogLevel(.error)
        
        let logger = mockDefaultLogger
        // This log is below the manager's minimum level and should be dropped
        expectCompletion(description: "Info log should be filtered") { fulfill in
            sut.log(message: "info log", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 0, "Info log should have been filtered")
                fulfill()
            }
        }
        
        mockDefaultLogger.reset()

        expectCompletion(description: "Error log should pass") { fulfill in
            sut.log(message: "error log", logType: .error) { _ in
                XCTAssertEqual(logger?.logCallCount, 1, "Error log should have been processed")
                fulfill()
            }
        }
    }

    func testLogLevelFiltering_LoggerItemLevel() {
        let strictLogger = SecondMockLogger()
        expectCompletion(description: "Add strict logger") { fulfill in
            sut.addLogger(newLogger: strictLogger, minLogLevel: .error) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
        
        let logger = mockDefaultLogger
        expectCompletion(description: "Default logger receives, strict logger filters") { fulfill in
            sut.log(message: "info log", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 1)
                XCTAssertEqual(strictLogger.logCallCount, 0)
                fulfill()
            }
        }
    }

    func testLogTypeFiltering_ManagerLevel() {
        sut.setMinimumLogType(.warning)
        
        let logger = mockDefaultLogger
        expectCompletion(description: "Info log should be filtered by type") { fulfill in
            sut.log(message: "info log", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 0, "Info log should have been filtered")
                fulfill()
            }
        }
        
        mockDefaultLogger.reset()

        expectCompletion(description: "Warning log should pass") { fulfill in
            sut.log(message: "warning log", logType: .warning) { _ in
                XCTAssertEqual(logger?.logCallCount, 1, "Warning log should have been processed")
                fulfill()
            }
        }
    }

    func testLogTypeFiltering_LoggerItemLevel() {
        let strictLogger = SecondMockLogger()
        expectCompletion(description: "Add strict logger") { fulfill in
            sut.addLogger(newLogger: strictLogger, minLogType: .warning) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
        
        let logger = mockDefaultLogger
        expectCompletion(description: "Default logger receives, strict logger filters by type") { fulfill in
            sut.log(message: "info log", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 1, "Default logger should have received the info log")
                XCTAssertEqual(strictLogger.logCallCount, 0, "Strict logger should have filtered the info log by type")
                fulfill()
            }
        }
    }

    func testCombinedFiltering_ManagerLevel() {
        sut.setMinimumLogLevel(.error)   // min level rawValue = 3
        sut.setMinimumLogType(.critical) // min type rawValue = 8
        
        let logger = mockDefaultLogger
        // Scenario 1: Fails Level filter
        expectCompletion(description: "Log should be filtered by level") { fulfill in
            sut.log(message: "info log", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 0, "Info log should have been filtered by level")
                fulfill()
            }
        }
        
        mockDefaultLogger.reset()
        
        // Scenario 2: Fails Type filter
        expectCompletion(description: "Log should be filtered by type") { fulfill in
            sut.log(message: "error log", logType: .error) { _ in
                XCTAssertEqual(logger?.logCallCount, 0, "Error log should be filtered by type")
                fulfill()
            }
        }
        
        mockDefaultLogger.reset()
        
        // Scenario 3: Passes both filters
        expectCompletion(description: "Log should pass both filters") { fulfill in
            sut.log(message: "critical log", logType: .critical) { _ in
                XCTAssertEqual(logger?.logCallCount, 1, "Critical log should pass both filters")
                fulfill()
            }
        }
    }
    
    func testCombinedFiltering_LoggerItemLevel() {
        let strictLogger = SecondMockLogger()
        sut.setMinimumLogLevel(.default)
        sut.setMinimumLogType(.none)

        expectCompletion(description: "Add strict logger with combined filters") { fulfill in
            sut.addLogger(newLogger: strictLogger, minLogLevel: .error, minLogType: .error) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
        
        let logger = mockDefaultLogger
        expectCompletion(description: "Combined filter test") { fulfill in
            sut.log(message: "warning log", logType: .warning) { _ in
                XCTAssertEqual(logger?.logCallCount, 1)
                XCTAssertEqual(strictLogger.logCallCount, 0)
                fulfill()
            }
        }
    }

    func testTagIntegration_ManagerAndLoggerLevels() {
        let loggerTagger = LogTagger()
        let loggerSpecificLogger = SecondMockLogger(tagger: loggerTagger)
        sut.addLogger(newLogger: loggerSpecificLogger, completion: nil)

        let managerTag = ExternalTag(identifier: "ManagerTag", value: "ManagerValue")
        let loggerTag = ExternalTag(identifier: "LoggerTag", value: "LoggerValue")
        
        expectCompletion(description: "Add manager tag") { fulfill in
            sut.addTag(managerTag) { _ in fulfill() }
        }
        expectCompletion(description: "Add logger-specific tag") { fulfill in
            loggerTagger.addTag(loggerTag) { _ in fulfill() }
        }

        let logger = mockDefaultLogger
        expectCompletion(description: "All loggers should receive log with correct tags") { fulfill in
            sut.log(message: "tag test", logType: .info) { _ in
                let defaultMsg = logger?.lastLoggedMessage
                XCTAssertNotNil(defaultMsg)
                XCTAssertTrue(defaultMsg?.tags.contains(where: { $0.identifier == "ManagerTag" }) ?? false)
                XCTAssertFalse(defaultMsg?.tags.contains(where: { $0.identifier == "LoggerTag" }) ?? false)
                
                let specificMsg = loggerSpecificLogger.lastLoggedMessage
                XCTAssertNotNil(specificMsg)
                XCTAssertTrue(specificMsg?.tags.contains(where: { $0.identifier == "ManagerTag" }) ?? false)
                XCTAssertTrue(specificMsg?.tags.contains(where: { $0.identifier == "LoggerTag" }) ?? false)
                fulfill()
            }
        }
    }
}
