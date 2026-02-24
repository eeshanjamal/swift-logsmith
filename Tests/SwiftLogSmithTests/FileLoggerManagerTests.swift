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
        
        // Act
        expectCompletion(description: "Write operation should complete", timeout: 2.0) { fulfill in
            sut.write(log: logMessage) { error in
                XCTAssertNil(error)
                fulfill()
            }
        }
        
        // Assert
        expectCompletion(description: "verify write operation should complete", timeout: 2.0) { fulfill in
            sut.listLogFiles { logFiles in
                XCTAssertEqual(logFiles.count, 1, "There should be one log file created")
                
                do {
                    let firstLogFile = try XCTUnwrap(logFiles.first)
                    let fileContent = try String(contentsOf: firstLogFile.url, encoding: .utf8)
                    XCTAssertEqual(fileContent, "\(logMessage)\n", "The file content should match the logged message plus a newline")
                } catch {
                    XCTFail("Failed to verify newly created log file: \(error)")
                }
                fulfill()
            }
        }
    }

    func testRolling_BySize() throws {
        // Arrange
        let logDirectory = testDirectoryURL.appendingPathComponent("TestLogs")
        let maxSize: UInt64 = 20 // Set a small size limit
        let rollingFrequency = SizeRollingFrequency(maxFileSize: maxSize)
        let sut = try FileLoggerManager(logDirectoryURL: logDirectory, rollingFrequency: rollingFrequency, maximumArchiveFiles: 10, maximumDirectorySize: 1024)
        
        let log1 = "First log, under limit." // ~23 bytes with newline
        let log2 = "Second log, triggers roll." // ~27 bytes with newline

        expectCompletion(description: "First write should complete", timeout: 2.0) { fulfill in
            sut.write(log: log1) { error in
                XCTAssertNil(error); fulfill()
            }
        }

        // Act
        expectCompletion(description: "Second write should complete and trigger roll", timeout: 2.0) { fulfill in
            sut.write(log: log2) { error in
                XCTAssertNil(error); fulfill()
            }
        }
        
        // Capture local copies to avoid capturing self
        let testDir = self.testDirectoryURL!
        
        // Assert
        expectCompletion(description: "verify rolling by size should complete", timeout: 2.0) { fulfill in
            sut.listLogFiles { logFiles in
                let archives = logFiles.filter { $0.url.pathExtension == "zip" }
                let activeLogs = logFiles.filter { $0.url.pathExtension == "log" }
                
                XCTAssertEqual(archives.count, 1, "There should be one archived file")
                XCTAssertEqual(activeLogs.count, 1, "There should be one new active log file")
                
                do {
                    // Verify content of the archived file
                    let archiveURL = try XCTUnwrap(archives.first?.url)
                    let unarchivedDir = testDir.appendingPathComponent("unarchived")
                    try FileManager.default.createDirectory(at: unarchivedDir, withIntermediateDirectories: false, attributes: nil)
                    try FileManager.default.unzipItem(at: archiveURL, to: unarchivedDir)
                    
                    let unzippedFiles = try FileManager.default.contentsOfDirectory(at: unarchivedDir, includingPropertiesForKeys: nil)
                    XCTAssertEqual(unzippedFiles.count, 1)
                    
                    let firstUnzippedFile = try XCTUnwrap(unzippedFiles.first)
                    let unzippedContent = try String(contentsOf: firstUnzippedFile, encoding: .utf8)
                    XCTAssertEqual(unzippedContent, "\(log1)\n")
                    
                    // Verify content of the new active log file
                    let newLogURL = try XCTUnwrap(activeLogs.first?.url)
                    let newLogContent = try String(contentsOf: newLogURL, encoding: .utf8)
                    XCTAssertEqual(newLogContent, "\(log2)\n")
                } catch {
                    XCTFail("test rolling by size verification failed: \(error)")
                }
                fulfill()
            }
        }
    }

    func testRolling_ByTime() throws {
        // Arrange
        let logDirectory = testDirectoryURL.appendingPathComponent("TestLogs")
        let interval: TimeInterval = 1.5
        let rollingFrequency = TimeRollingFrequency(rollingInterval: interval)
        let sut = try FileLoggerManager(logDirectoryURL: logDirectory, rollingFrequency: rollingFrequency, maximumArchiveFiles: 10, maximumDirectorySize: 1024)
        
        let log1 = "First log."
        let log2 = "Second log, after interval."

        expectCompletion(description: "First write should complete", timeout: 2.0) { fulfill in
            sut.write(log: log1) { error in
                XCTAssertNil(error); fulfill()
            }
        }
        
        // Act
        // Wait for a time longer than the rolling interval to trigger the roll on next write
        Thread.sleep(forTimeInterval: 2.0)

        expectCompletion(description: "Second write should complete and trigger roll", timeout: 2.0) { fulfill in
            sut.write(log: log2) { error in
                XCTAssertNil(error); fulfill()
            }
        }
        
        // Assert
        expectCompletion(description: "verify rolling by time should complete", timeout: 2.0) { fulfill in
            sut.listLogFiles { logFiles in
                let archives = logFiles.filter { $0.url.pathExtension == "zip" }
                let activeLogs = logFiles.filter { $0.url.pathExtension == "log" }
                
                XCTAssertEqual(archives.count, 1, "There should be one archived file after time-based roll")
                XCTAssertEqual(activeLogs.count, 1, "There should be one new active log file")
                
                do {
                    // Verify content of the new active log file
                    let newLogURL = try XCTUnwrap(activeLogs.first?.url)
                    let newLogContent = try String(contentsOf: newLogURL, encoding: .utf8)
                    XCTAssertEqual(newLogContent, "\(log2)\n")
                } catch {
                    XCTFail("test rolling by time verification failed: \(error)")
                }
                fulfill()
            }
        }
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
        expectCompletion(description: "Initial write for purge (by count) should complete", timeout: 2.0) { fulfill in
            sut.write(log: "This is the initial log file content.") { error in
                XCTAssertNil(error)
                fulfill()
            }
        }
        
        // Sanity check: we should have 2 archives and 1 log file before the purge-triggering roll
        expectCompletion(description: "Befor purge (by count) files sanity check should complete", timeout: 2.0) { fulfill in
            sut.listLogFiles(filterByExtensions: ["zip"]) { archives in
                XCTAssertEqual(archives.count, 2)
                sut.listLogFiles(filterByExtensions: ["log"]) { logs in
                    XCTAssertEqual(logs.count, 1)
                    fulfill()
                }
            }
        }

        // Act
        // This second write will trigger a roll because the file is no longer empty (size > 1),
        // creating a 3rd archive. The purge logic should then execute.
        expectCompletion(description: "Write that triggers purge (by count) should complete", timeout: 2.0) { fulfill in
            sut.write(log: "This log triggers the purge (by count).") { error in
                XCTAssertNil(error)
                fulfill()
            }
        }

        // Assert
        expectCompletion(description: "Verify final archives post purge (by count) should complete", timeout: 2.0) { fulfill in
            sut.listLogFiles(filterByExtensions: ["zip"]) { finalArchives in
                XCTAssertEqual(finalArchives.count, 2, "Should be exactly 2 archives remaining after purge")
                
                let remainingArchiveNames = finalArchives.map { $0.name }
                XCTAssertFalse(remainingArchiveNames.contains("archive_oldest.zip"), "The oldest archive should have been deleted")
                XCTAssertTrue(remainingArchiveNames.contains("archive_newer.zip"), "The newer original archive should remain")
                // The third archive is the one created from rolling the "initial content" log file.
                XCTAssertEqual(finalArchives.filter { $0.name != "archive_newer.zip" }.count, 1, "The newly created archive should be present")
                fulfill()
            }
        }
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

        // 1. Create first archive and capture its name
        expectCompletion(description: "First two writes in purge (by size) should complete", fulfillmentCount: 2, timeout: 2.0) { fulfill in
            sut.write(log: "\(logMessage) 1") { _ in fulfill() }
            Thread.sleep(forTimeInterval: 0.1)
            sut.write(log: "\(logMessage) 2") { _ in fulfill() }
        }
        
        expectCompletion(description: "Purge (by size) logic flow should complete", timeout: 5.0) { fulfill in
            // Step 1: Get initial archive name
            sut.listLogFiles(filterByExtensions: ["zip"], sortBy: .createdAt, order: .ascending) { initialArchives in
                XCTAssertEqual(initialArchives.count, 1, "Should have 1 archive after two writes")
                
                let archiveName: String
                do {
                    archiveName = try XCTUnwrap(initialArchives.first?.name)
                    XCTAssertFalse(archiveName.isEmpty, "First archive name should not be empty")
                } catch {
                    XCTFail("Failed to unwrap archive name: \(error)")
                    fulfill()
                    return
                }
                
                // Step 2: Trigger purge by writing more logs (nested inside to keep archiveName in scope)
                let group = DispatchGroup()
                
                group.enter()
                sut.write(log: "\(logMessage) 3") { _ in group.leave() }
                
                group.enter()
                Thread.sleep(forTimeInterval: 0.1)
                sut.write(log: "\(logMessage) 4") { _ in group.leave() }
                
                group.notify(queue: .global()) {
                    // Step 3: Verify
                    sut.listLogFiles(filterByExtensions: ["zip"]) { finalArchives in
                        let totalSize = finalArchives.reduce(0) { $0 + $1.size }

                        // After 4 writes, 3 archives were created.
                        // The purge should delete oldest archives to bring total under limit.
                        XCTAssertEqual(finalArchives.count, 2, "Should be 2 archives remaining after purging by size")
                        XCTAssertTrue(totalSize <= sut.maximumDirectorySize, "Total size of archives (\(totalSize)) should be under the limit of \(sut.maximumDirectorySize)")
                        
                        let finalArchiveNames = finalArchives.map { $0.name }
                        XCTAssertFalse(finalArchiveNames.contains(archiveName), "The oldest archive (\(archiveName)) should have been purged")
                        fulfill()
                    }
                }
            }
        }
    }

    func testClearLogs() throws {
        // Arrange
        let logDirectory = testDirectoryURL.appendingPathComponent("TestLogs")
        let sut = try FileLoggerManager(logDirectoryURL: logDirectory, rollingFrequency: SessionRollingFrequency(), maximumArchiveFiles: 10, maximumDirectorySize: 1024)
        
        // Act: Create a few log files and archives
        expectCompletion(description: "All writes should complete", fulfillmentCount: 3, timeout: 5.0) { fulfill in
            sut.write(log: "Log 1") { error in XCTAssertNil(error); fulfill() }
            Thread.sleep(forTimeInterval: 0.1)
            sut.write(log: "Log 2") { error in XCTAssertNil(error); fulfill() }
            Thread.sleep(forTimeInterval: 0.1)
            sut.write(log: "Log 3") { error in XCTAssertNil(error); fulfill() }
        }
        
        // Sanity check: ensure files exist before clearing
        expectCompletion(description: "Sanity check before clear logs operation should complete", timeout: 2.0) { fulfill in
            sut.listLogFiles { logFiles in
                XCTAssertTrue(logFiles.count > 0, "Should have files before clearing")
                fulfill()
            }
        }
        
        // Act: Clear all logs
        expectCompletion(description: "Clear logs operation should complete", timeout: 2.0) { fulfill in
            sut.clearLogs { error in
                XCTAssertNil(error, "Clear logs should complete without errors")
                fulfill()
            }
        }
        
        // Assert
        expectCompletion(description: "Verify no files remaining after clear logs operation should complete", timeout: 2.0) { fulfill in
            sut.listLogFiles { remainingFiles in
                XCTAssertEqual(remainingFiles.count, 0, "All log files and archives should be deleted")
                fulfill()
            }
        }
    }
}
