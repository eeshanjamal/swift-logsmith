//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import SwiftLogSmith

final class FileLoggerTests: XCTestCase {
    
    var testDirectoryURL: URL!
    let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        testDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: testDirectoryURL)
        testDirectoryURL = nil
        super.tearDown()
    }

    func testLog_ShouldWriteToManager() throws {
        // Arrange
        let manager = try FileLoggerManager(
            logDirectoryURL: testDirectoryURL,
            rollingFrequency: SessionRollingFrequency(),
            maximumArchiveFiles: 1,
            maximumDirectorySize: 1024 * 1024
        )
        
        let logger = FileLogger(fileLoggerManager: manager)
        let messageText = "Test file logger integration"
        let logMessage = LogMessage(message: messageText, logType: .info, tags: [], metadata: [:])
        
        expectCompletion(description: "Write should complete", timeout: 2.0) { fulfill in
            logger.log(message: logMessage) { success in
                XCTAssertTrue(success)
                fulfill()
            }
        }
        
        // Assert
        let files = manager.listLogFiles()
        XCTAssertEqual(files.count, 1)
        
        let content = try String(contentsOf: files[0].url, encoding: .utf8)
        XCTAssertTrue(content.contains(messageText))
    }
}
