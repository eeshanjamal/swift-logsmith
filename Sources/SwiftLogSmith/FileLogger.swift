//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objcMembers
final class FileLogger: NSObject, ILogger {
    
    let tagger: LogTagger?
    let formatter: LogFormatter
    let manager: FileLoggerManager
    
    init(logFormatter: LogFormatter = LogFormatter.default, logTagger: LogTagger? = nil, fileLoggerManager: FileLoggerManager = FileLoggerManager.default) {
        formatter = logFormatter
        tagger = logTagger
        manager = fileLoggerManager
    }
    
    func log(message: LogMessage) {
        
    }
}

@objcMembers
final class FileLoggerManager: NSObject, @unchecked Sendable {
    
    static let defaultDirectory = "LogSmith"
    static let defaultArchiveFiles: Int = 100
    static let defaultDirectorySize: UInt64 = 100 * 1024 * 1024 //100 mb
    static var `default`: FileLoggerManager {
        FileLoggerManager()
    }
    
    let logDirectory: String
    let maximumArchiveFiles: Int
    let maximumDirectorySize: UInt64
    let rollingFrequency: any RollingFrequency
    
    init(logDirectory: String = defaultDirectory, maximumArchiveFiles: Int = defaultArchiveFiles,
         maximumDirectorySize: UInt64 = defaultDirectorySize, rollingFrequency: any RollingFrequency = SessionRollingFrequency()) {
        self.logDirectory = logDirectory
        self.maximumArchiveFiles = maximumArchiveFiles
        self.maximumDirectorySize = maximumDirectorySize
        self.rollingFrequency = rollingFrequency
    }
}

@objcMembers
final class LogFile: NSObject {
    
    let url: URL
    
    init(url: URL) {
        self.url = url
    }
    
    var isExist: Bool {
        FileManager.default.fileExists(atPath: path)
    }
    
    var path: String {
        url.path
    }
    
    var name: String {
        url.lastPathComponent
    }
    
    func attributes() throws -> [FileAttributeKey: Any] {
        return try FileManager.default.attributesOfItem(atPath: path)
    }
    
    var createdAt: Date? {
        return (try? attributes())?[.creationDate] as? Date
    }
    
    var modifiedAt: Date? {
        return (try? attributes())?[.modificationDate] as? Date
    }
    
    var size: UInt64 {
        return (try? attributes())?[.size] as? UInt64 ?? 0
    }
}

@objc protocol RollingFrequency {
    
    @objc func shouldRoll(logFile: LogFile) -> Bool
}

@objcMembers
final class TimeRollingFrequency: NSObject, RollingFrequency {
    
    private let rollingInterval: TimeInterval
    
    init(rollingInterval: TimeInterval) {
        self.rollingInterval = rollingInterval
    }
    
    func shouldRoll(logFile: LogFile) -> Bool {
        if let creationTime = logFile.createdAt {
            // Check if the time elapsed since creation is greater than the interval.
            return Date().timeIntervalSince(creationTime) > rollingInterval
        }
        else {
            // If the file doesn't exist, we can't do rolling validation
            return false
        }
    }
}

@objcMembers
final class SizeRollingFrequency: NSObject, RollingFrequency {
    
    private let maxFileSize: UInt64
    
    init(maxFileSize: UInt64) {
        self.maxFileSize = maxFileSize
    }
    
    func shouldRoll(logFile: LogFile) -> Bool {
        return logFile.size > maxFileSize
    }
}

@objcMembers
final class SessionRollingFrequency: NSObject, RollingFrequency {
    
    func shouldRoll(logFile: LogFile) -> Bool {
        if let creationTime = logFile.createdAt {
            // If the file was created before this app session started, roll it.
            return creationTime < LogSmith.sessionLaunchTime
        }
        else {
            // If the file doesn't exist, we can't do rolling validation
            return false
        }
    }
}

