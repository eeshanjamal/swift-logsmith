//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import SwiftLogSmith

final class FileLoggerManagerTests: XCTestCase {

    var testDirectoryURL: URL!
    let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        // Create a unique directory for each test run
        testDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        // Clean up the unique directory after each test
        try? fileManager.removeItem(at: testDirectoryURL)
        testDirectoryURL = nil
        super.tearDown()
    }

    func testPublicInit_ShouldSucceed() throws {
        // Arrange
        let uniqueName = "TestLogSmith_\(UUID().uuidString)"
        
        // Act
        let sut = try FileLoggerManager(
            logDirectoryName: uniqueName,
            rollingFrequency: SessionRollingFrequency(),
            maximumArchiveFiles: 5,
            maximumDirectorySize: 1024 * 1024
        )
        
        // Assert
        XCTAssertNotNil(sut)
        XCTAssertTrue(sut.logDirectoryURL.path.contains(uniqueName))
        
        // Cleanup: The public init creates a directory in Application Support. We should clean it up.
        try? FileManager.default.removeItem(at: sut.logDirectoryURL)
    }

    func testInit_WhenDirectoryDoesNotExist_ShouldCreateDirectory() throws {
        // Arrange
        let logDirectory = testDirectoryURL.appendingPathComponent("TestLogs")
        var isDirectory: ObjCBool = false
        // Assert directory does not exist before test
        XCTAssertFalse(fileManager.fileExists(atPath: logDirectory.path, isDirectory: &isDirectory))

        // Act
        let sut = try FileLoggerManager(
            logDirectoryURL: logDirectory,
            rollingFrequency: SessionRollingFrequency(),
            maximumArchiveFiles: 10,
            maximumDirectorySize: 1024 * 1024
        )

        // Assert
        XCTAssertNotNil(sut, "Manager should be initialized")
        XCTAssertTrue(fileManager.fileExists(atPath: logDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "The path should be a directory")
    }

    func testWrite_CreatesAndWritesToNewFile() throws {
        // Arrange
        let logDirectory = testDirectoryURL.appendingPathComponent("TestLogs")
        let sut = try FileLoggerManager(logDirectoryURL: logDirectory, rollingFrequency: SessionRollingFrequency(), maximumArchiveFiles: 10, maximumDirectorySize: 1024)
        let logMessage = "Hello, world!"
        
        let writeExpectation = XCTestExpectation(description: "Write operation should complete")
        
        // Act
        sut.write(log: logMessage) { error in
            XCTAssertNil(error)
            writeExpectation.fulfill()
        }
        
        // Assert
        wait(for: [writeExpectation], timeout: 2.0)
        
        let logFiles = sut.listLogFiles()
        XCTAssertEqual(logFiles.count, 1, "There should be one log file created")
        
        let firstLogFile = try XCTUnwrap(logFiles.first)
        let fileContent = try String(contentsOf: firstLogFile.url, encoding: .utf8)
        
        XCTAssertEqual(fileContent, "\(logMessage)\n", "The file content should match the logged message plus a newline")
    }

    func testRolling_BySize() throws {
        // Arrange
        let logDirectory = testDirectoryURL.appendingPathComponent("TestLogs")
        let maxSize: UInt64 = 20 // Set a small size limit
        let rollingFrequency = SizeRollingFrequency(maxFileSize: maxSize)
        let sut = try FileLoggerManager(logDirectoryURL: logDirectory, rollingFrequency: rollingFrequency, maximumArchiveFiles: 10, maximumDirectorySize: 1024)
        
        let log1 = "First log, under limit." // ~23 bytes with newline
        let log2 = "Second log, triggers roll." // ~27 bytes with newline

        let expectation1 = XCTestExpectation(description: "First write should complete")
        sut.write(log: log1) { error in
            XCTAssertNil(error); expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 2.0)

        // Act
        let expectation2 = XCTestExpectation(description: "Second write should complete and trigger roll")
        sut.write(log: log2) { error in
            XCTAssertNil(error); expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 2.0)
        
        // Assert
        let logFiles = sut.listLogFiles()
        let archives = logFiles.filter { $0.url.pathExtension == "zip" }
        let activeLogs = logFiles.filter { $0.url.pathExtension == "log" }
        
        XCTAssertEqual(archives.count, 1, "There should be one archived file")
        XCTAssertEqual(activeLogs.count, 1, "There should be one new active log file")
        
        // Verify content of the archived file
        let archiveURL = try XCTUnwrap(archives.first?.url)
        let unarchivedDir = testDirectoryURL.appendingPathComponent("unarchived")
        try fileManager.createDirectory(at: unarchivedDir, withIntermediateDirectories: false, attributes: nil)
        try fileManager.unzipItem(at: archiveURL, to: unarchivedDir)
        
        let unzippedFiles = try fileManager.contentsOfDirectory(at: unarchivedDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(unzippedFiles.count, 1)
        let unzippedContent = try String(contentsOf: try XCTUnwrap(unzippedFiles.first), encoding: .utf8)
        XCTAssertEqual(unzippedContent, "\(log1)\n")
        
        // Verify content of the new active log file
        let newLogURL = try XCTUnwrap(activeLogs.first?.url)
        let newLogContent = try String(contentsOf: newLogURL, encoding: .utf8)
        XCTAssertEqual(newLogContent, "\(log2)\n")
    }

    func testRolling_ByTime() throws {
        // Arrange
        let logDirectory = testDirectoryURL.appendingPathComponent("TestLogs")
        let interval: TimeInterval = 1.5
        let rollingFrequency = TimeRollingFrequency(rollingInterval: interval)
        let sut = try FileLoggerManager(logDirectoryURL: logDirectory, rollingFrequency: rollingFrequency, maximumArchiveFiles: 10, maximumDirectorySize: 1024)
        
        let log1 = "First log."
        let log2 = "Second log, after interval."

        let expectation1 = XCTestExpectation(description: "First write should complete")
        sut.write(log: log1) { error in
            XCTAssertNil(error); expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 2.0)
        
        // Act
        // Wait for a time longer than the rolling interval to trigger the roll on next write
        Thread.sleep(forTimeInterval: 2.0)

        let expectation2 = XCTestExpectation(description: "Second write should complete and trigger roll")
        sut.write(log: log2) { error in
            XCTAssertNil(error); expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 2.0)
        
        // Assert
        let logFiles = sut.listLogFiles()
        let archives = logFiles.filter { $0.url.pathExtension == "zip" }
        let activeLogs = logFiles.filter { $0.url.pathExtension == "log" }
        
        XCTAssertEqual(archives.count, 1, "There should be one archived file after time-based roll")
        XCTAssertEqual(activeLogs.count, 1, "There should be one new active log file")
        
        // Verify content of the new active log file
        let newLogURL = try XCTUnwrap(activeLogs.first?.url)
        let newLogContent = try String(contentsOf: newLogURL, encoding: .utf8)
        XCTAssertEqual(newLogContent, "\(log2)\n")
    }

    func testPurging_ByCount() throws {
        // Arrange
        let logDirectory = testDirectoryURL.appendingPathComponent("TestLogs")
        try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)

        // 1. Create two existing archives with distinct creation dates
        let oldestArchiveURL = logDirectory.appendingPathComponent("archive_oldest.zip")
        let newerArchiveURL = logDirectory.appendingPathComponent("archive_newer.zip")
        
        fileManager.createFile(atPath: oldestArchiveURL.path, contents: Data("oldest".utf8))
        Thread.sleep(forTimeInterval: 0.1) // ensure different modification/creation dates
        fileManager.createFile(atPath: newerArchiveURL.path, contents: Data("newer".utf8))
        Thread.sleep(forTimeInterval: 0.1)

        // 2. Setup SUT to keep a max of 2 archives and roll on any write to a non-empty file
        let sut = try FileLoggerManager(
            logDirectoryURL: logDirectory,
            rollingFrequency: SizeRollingFrequency(maxFileSize: 1),
            maximumArchiveFiles: 2,
            maximumDirectorySize: 1024 
        )

        // 3. Write to an initial log file. This file will be the one that gets rolled.
        let firstWriteExpectation = XCTestExpectation(description: "Initial write")
        sut.write(log: "This is the initial log file content.") { error in
            XCTAssertNil(error)
            firstWriteExpectation.fulfill()
        }
        wait(for: [firstWriteExpectation], timeout: 2.0)
        
        // Sanity check: we should have 2 archives and 1 log file before the purge-triggering roll
        XCTAssertEqual(sut.listLogFiles(filterByExtensions: ["zip"]).count, 2)
        XCTAssertEqual(sut.listLogFiles(filterByExtensions: ["log"]).count, 1)

        // Act
        // This second write will trigger a roll because the file is no longer empty (size > 1),
        // creating a 3rd archive. The purge logic should then execute.
        let finalWriteExpectation = XCTestExpectation(description: "Final write that triggers purge")
        sut.write(log: "This log triggers the purge.") { error in
            XCTAssertNil(error)
            finalWriteExpectation.fulfill()
        }
        wait(for: [finalWriteExpectation], timeout: 2.0)

        // Assert
        let finalArchives = sut.listLogFiles(filterByExtensions: ["zip"])
        XCTAssertEqual(finalArchives.count, 2, "Should be exactly 2 archives remaining after purge")
        
        let remainingArchiveNames = finalArchives.map { $0.name }
        XCTAssertFalse(remainingArchiveNames.contains("archive_oldest.zip"), "The oldest archive should have been deleted")
        XCTAssertTrue(remainingArchiveNames.contains("archive_newer.zip"), "The newer original archive should remain")
        // The third archive is the one created from rolling the "initial content" log file.
        XCTAssertEqual(finalArchives.filter { $0.name != "archive_newer.zip" }.count, 1, "The newly created archive should be present")
    }

    func testPurging_BySize() throws {
        // Arrange
        let logDirectory = testDirectoryURL.appendingPathComponent("TestLogs")
        // Log message size is ~23 bytes (22 + newline), but zip archive has overhead (~173 bytes)
        let singleArchiveSize: UInt64 = 175 
        let logMessage = "This is a 22-byte log."
        
        // Setup SUT: Max archives is high (no count purge), max size is set to trigger after 2 archives.
        let sut = try FileLoggerManager(
            logDirectoryURL: logDirectory,
            rollingFrequency: SizeRollingFrequency(maxFileSize: 1), // Roll always as logMessage > 1 byte
            maximumArchiveFiles: 10,
            maximumDirectorySize: singleArchiveSize * 2 + 50 // Limit to ~2 archives (approx 400 bytes)
        )

        // Act: Write four times. Each write triggers a roll.
        // 1st roll -> archive 1
        // 2nd roll -> archive 2
        // 3rd roll -> archive 3 (now total > maxDirectorySize, should trigger purge)
        // 4th roll -> archive 4 (now total > maxDirectorySize, should trigger purge)
        let expectation = XCTestExpectation(description: "All writes should complete")
        expectation.expectedFulfillmentCount = 4
        
        for i in 1...4 {
            sut.write(log: "\(logMessage) \(i)") { error in
                XCTAssertNil(error)
                expectation.fulfill()
            }
            Thread.sleep(forTimeInterval: 0.1) // Ensure distinct file timestamps
        }
        
        wait(for: [expectation], timeout: 5.0)

        // Assert
        let finalArchives = sut.listLogFiles(filterByExtensions: ["zip"])
        let totalSize = finalArchives.reduce(0) { $0 + $1.size }

        // After 4 writes, 3 archives were initially created.
        // The purge should delete oldest archives to bring total under limit.
        XCTAssertEqual(finalArchives.count, 2, "Should be 2 archives remaining after purging by size")
        XCTAssertTrue(totalSize <= sut.maximumDirectorySize, "Total size of archives (\(totalSize)) should be under the limit of \(sut.maximumDirectorySize)")
        XCTAssertFalse(finalArchives.contains(where: { $0.name.contains("SLS_") && $0.name.contains("1.log.zip") }), "The oldest archive (from first roll) should be purged")
    }

    func testClearLogs() throws {
        // Arrange
        let logDirectory = testDirectoryURL.appendingPathComponent("TestLogs")
        let sut = try FileLoggerManager(logDirectoryURL: logDirectory, rollingFrequency: SessionRollingFrequency(), maximumArchiveFiles: 10, maximumDirectorySize: 1024)
        
        let writeExpectation = XCTestExpectation(description: "All writes should complete")
        writeExpectation.expectedFulfillmentCount = 3
        
        // Act: Create a few log files and archives
        sut.write(log: "Log 1") { error in XCTAssertNil(error); writeExpectation.fulfill() }
        Thread.sleep(forTimeInterval: 0.1)
        sut.write(log: "Log 2") { error in XCTAssertNil(error); writeExpectation.fulfill() }
        Thread.sleep(forTimeInterval: 0.1) 
        sut.write(log: "Log 3") { error in XCTAssertNil(error); writeExpectation.fulfill() }
        
        wait(for: [writeExpectation], timeout: 5.0)
        
        // Sanity check: ensure files exist before clearing
        XCTAssertTrue(sut.listLogFiles().count > 0, "Should have files before clearing")
        
        let clearExpectation = XCTestExpectation(description: "Clear logs operation should complete")
        
        // Act: Clear all logs
        sut.clearLogs {
            error in
            XCTAssertNil(error, "Clear logs should complete without errors")
            clearExpectation.fulfill()
        }
        
        // Assert
        wait(for: [clearExpectation], timeout: 2.0)
        
        let remainingFiles = sut.listLogFiles()
        XCTAssertEqual(remainingFiles.count, 0, "All log files and archives should be deleted")
    }
}
