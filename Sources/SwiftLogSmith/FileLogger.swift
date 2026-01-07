//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation
import ZIPFoundation

/// Keys to specify the property to sort log files by.
@objc public enum LogFileSortKey: Int {
    case undefined
    case name
    case createdAt
    case modifiedAt
    case size
}

/// Specifies the direction for sorting.
@objc public enum SortOrder: Int {
    case ascending
    case descending
}

@objcMembers
final class FileLogger: NSObject, ILogger {
    
    let tagger: LogTagger?
    let formatter: LogFormatter
    let manager: FileLoggerManager
    
    init(logFormatter: LogFormatter = LogFormatter.default, logTagger: LogTagger? = nil, fileLoggerManager: FileLoggerManager = try! FileLoggerManager()) {
        formatter = logFormatter
        tagger = logTagger
        manager = fileLoggerManager
    }
    
    func log(message: LogMessage) {
        manager.write(log: formatter.format(message: message))
    }
}

@objcMembers
final class FileLoggerManager: NSObject, @unchecked Sendable {
    
    public static let ErrorDomain = "com.swift.logsmith.FileLoggerManager.ErrorDomain"
    public static let FailedDeletionsKey = "FileLoggerManagerFailedDeletionsKey"
    
    @objc public enum ErrorCode: Int {
        case purgeFailed
        case fileNotFound
        case dataPrepareFailed
        case clearLogsFailed
    }
    
    public static let defaultDirectoryName = "LogSmith"
    public static let defaultMaxArchiveFiles: Int = 10
    public static let defaultMaxDirectorySize: UInt64 = 100 * 1024 * 1024 // 100 MB
    
    public static var `default`: FileLoggerManager {
        try! FileLoggerManager()
    }
    
    public let logDirectoryURL: URL
    public let maximumArchiveFiles: Int
    public let maximumDirectorySize: UInt64
    public let rollingFrequency: any RollingFrequency

    private var currentLogFile: LogFile?
    
    private let queue = DispatchQueue(label: "com.swift.logsmith.filelogger.\(NSUUID().uuidString)")
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    public init(logDirectoryName: String = defaultDirectoryName, rollingFrequency: any RollingFrequency = SessionRollingFrequency(),
        maximumArchiveFiles: Int = defaultMaxArchiveFiles, maximumDirectorySize: UInt64 = defaultMaxDirectorySize) throws {
        
        self.rollingFrequency = rollingFrequency
        self.maximumArchiveFiles = maximumArchiveFiles
        self.maximumDirectorySize = maximumDirectorySize

        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "FileLoggerManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot find Application Support directory."])
        }
        
        let appIdentifier = Bundle.main.bundleIdentifier ?? "com.unknown.app"
        self.logDirectoryURL = appSupportURL.appendingPathComponent(appIdentifier).appendingPathComponent(logDirectoryName)

        super.init()
        
        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        self.currentLogFile = listLogFiles(filterByExtensions: ["log"], sortBy: .modifiedAt, order: .descending).first
    }

    public func write(log: String, completion: (@Sendable(NSError?) -> Void)? = nil) {
        queue.async { self._write(log, completion: completion) }
    }
    
    public func listLogFiles(filterByExtensions: [String]? = nil, sortBy: LogFileSortKey = .undefined, order: SortOrder = .ascending) -> [LogFile] {
        
        // Only fetch properties if we need them for sorting.
        let keysToFetch: [URLResourceKey]? = (sortBy == .undefined) ? nil : [.creationDateKey, .contentModificationDateKey, .fileSizeKey]
        
        guard var urls = try? fileManager.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: keysToFetch, options: []) else {
            return []
        }
        
        // 1. Filtering on the [URL] array
        if let extensions = filterByExtensions, !extensions.isEmpty {
            let lowercasedExtensions = extensions.map { $0.lowercased() }
            urls = urls.filter { lowercasedExtensions.contains($0.pathExtension.lowercased()) }
        }
        
        // 2. Sorting on the [URL] array for performance
        if sortBy != .undefined {
            urls.sort { (lhsURL, rhsURL) in
                // Use pre-fetched resource values from the URL for sorting performance
                let lhsValues = try? lhsURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
                let rhsValues = try? rhsURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])

                let result: Bool
                switch sortBy {
                case .undefined:
                    result = false
                case .name:
                    result = lhsURL.lastPathComponent.compare(rhsURL.lastPathComponent) == .orderedAscending
                case .size:
                    result = UInt64(lhsValues?.fileSize ?? 0) < UInt64(rhsValues?.fileSize ?? 0)
                case .createdAt:
                    result = (lhsValues?.creationDate ?? .distantPast) < (rhsValues?.creationDate ?? .distantPast)
                case .modifiedAt:
                    result = (lhsValues?.contentModificationDate ?? .distantPast) < (rhsValues?.contentModificationDate ?? .distantPast)
                }
                return order == .ascending ? result : !result
            }
            
            // 3. Clear the cache from the original URL array to save memory
            for i in 0..<urls.count {
                urls[i].removeAllCachedResourceValues()
            }
        }
        
        // 4. Map to LogFile objects
        return urls.map { LogFile(url: $0) }
    }
    
    public func clearLogs(completion: (@Sendable(NSError?) -> Void)? = nil) {
        queue.async {
            let logFiles = self.listLogFiles()
            var deletionErrors: [NSError] = []
            for file in logFiles {
                do {
                    try self.fileManager.removeItem(at: file.url)
                } catch let error as NSError {
                    deletionErrors.append(error)
                }
            }
            self.currentLogFile = nil
            if let completion = completion {
                if deletionErrors.isEmpty {
                    completion(nil)
                }
                else {
                    let userInfo: [String: Any] = [
                        NSLocalizedDescriptionKey: "Failed to clear one or more logs.",
                        FileLoggerManager.FailedDeletionsKey: deletionErrors
                    ]
                    completion(NSError(
                        domain: FileLoggerManager.ErrorDomain,
                        code: ErrorCode.clearLogsFailed.rawValue,
                        userInfo: userInfo
                    ))
                }
            }
        }
    }

    private func _write(_ log: String, completion: ((NSError?) -> Void)? = nil) {
        do {
            if currentLogFile == nil {
                createNewLogFile()
            }

            guard let currentLogFile = self.currentLogFile else {
                throw NSError(domain: FileLoggerManager.ErrorDomain, code: ErrorCode.fileNotFound.rawValue, userInfo: [NSLocalizedDescriptionKey: "Failed to establish a current log file."])
            }

            if rollingFrequency.shouldRoll(logFile: currentLogFile) {
                try rollFile()
                try purgeArchives()
            }
            
            guard let fileToWrite = self.currentLogFile, let data = (log + "\n").data(using: .utf8) else {
                throw NSError(domain: FileLoggerManager.ErrorDomain, code: ErrorCode.dataPrepareFailed.rawValue, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare data for writing."])
            }

            if fileManager.fileExists(atPath: fileToWrite.path) {
                let fileHandle = try FileHandle(forWritingTo: fileToWrite.url)
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: data)
                try fileHandle.close()
            } else {
                try data.write(to: fileToWrite.url, options: .atomic)
            }
            completion?(nil) // Success
        } catch let error as NSError {
            completion?(error) // Failure
        } catch {
            completion?(error as NSError)
        }
    }

    private func createNewLogFile() {
        let timestamp = dateFormatter.string(from: Date())
        let newURL = logDirectoryURL.appendingPathComponent("\(timestamp).log")
        self.currentLogFile = LogFile(url: newURL)
    }

    private func rollFile() throws {
        guard let fileToRoll = currentLogFile, fileToRoll.isExist else {
            createNewLogFile()
            return
        }

        let archiveURL = fileToRoll.url.appendingPathExtension("zip")

        do {
            try fileManager.zipItem(at: fileToRoll.url, to: archiveURL, shouldKeepParent: false, compressionMethod: .deflate)
        } catch {
            // Zipping failed, rethrow the error as NSError.
            throw error as NSError
        }

        do {
            try fileManager.removeItem(at: fileToRoll.url)
        } catch {
            let primaryError = error as NSError
            // Deleting original failed, attempt to roll back by removing the archive.
            do {
                try fileManager.removeItem(at: archiveURL)
            } catch let rollbackError {
                // This is a "double fault" scenario. Log it for debugging.
                print("FileLogger rollback failed: could not remove duplicate archive \(archiveURL). Error: \(rollbackError)")
            }
            // Throw the original, more important error.
            throw primaryError
        }

        createNewLogFile()
    }

    private func purgeArchives() throws {
        var archives = listLogFiles(filterByExtensions: ["zip"], sortBy: .createdAt, order: .ascending)
        var deletionErrors: [NSError] = []

        // 1. Purge by count
        while archives.count > maximumArchiveFiles {
            let fileToDelete = archives.removeFirst()
            do {
                try fileManager.removeItem(at: fileToDelete.url)
            } catch let error as NSError {
                deletionErrors.append(error)
            }
        }
        
        // 2. Purge by size
        var totalSize = archives.reduce(0) { $0 + $1.size }
        while totalSize > maximumDirectorySize && !archives.isEmpty {
            let fileToDelete = archives.removeFirst()
            do {
                totalSize -= fileToDelete.size
                try fileManager.removeItem(at: fileToDelete.url)
            } catch let error as NSError {
                deletionErrors.append(error)
            }
        }
        
        if !deletionErrors.isEmpty {
            let userInfo: [String: Any] = [
                NSLocalizedDescriptionKey: "Failed to purge one or more log archives.",
                FileLoggerManager.FailedDeletionsKey: deletionErrors
            ]
            throw NSError(
                domain: FileLoggerManager.ErrorDomain,
                code: ErrorCode.purgeFailed.rawValue,
                userInfo: userInfo
            )
        }
    }
}

@objcMembers
final class LogFile: NSObject {
    
    public let url: URL

    public var name: String {
        url.lastPathComponent
    }
    
    public var path: String {
        url.path
    }
    
    /// A real-time check to see if the file exists on disk.
    public var isExist: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public init(url: URL) {
        self.url = url
        super.init()
    }
    
    /// The creation date of the file.
    public var createdAt: Date? {
        return attributes()?[.creationDate] as? Date
    }
    
    /// The modification date of the file.
    public var modifiedAt: Date? {
        return attributes()?[.modificationDate] as? Date
    }
    
    /// The size of the file in bytes.
    public var size: UInt64 {
        return attributes()?[.size] as? UInt64 ?? 0
    }
    
    private func attributes() -> [FileAttributeKey: Any]? {
        return try? FileManager.default.attributesOfItem(atPath: path)
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

