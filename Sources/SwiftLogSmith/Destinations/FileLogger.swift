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
        case invalidDirectoryName
        case directoryNotFound
    }
    
    public static let defaultDirectoryName = "LogSmith"
    #if os(watchOS)
    public static let defaultMaxArchiveFiles: UInt = 10
    public static let defaultMaxDirectorySize: UInt64 = 10 * 1024 * 1024 // 10 MB
    #elseif os(tvOS)
    public static let defaultMaxArchiveFiles: UInt = 5
    public static let defaultMaxDirectorySize: UInt64 = 5 * 1024 * 1024 // 5 MB
    #else // macOS, iOS, iPadOS, visionOS etc.
    public static let defaultMaxArchiveFiles: UInt = 100
    public static let defaultMaxDirectorySize: UInt64 = 100 * 1024 * 1024 // 100 MB
    #endif
    
    public static let `default`: FileLoggerManager = try! FileLoggerManager()
    
    public let logDirectoryURL: URL
    public let maximumArchiveFiles: UInt
    public let maximumDirectorySize: UInt64
    public let rollingFrequency: any RollingFrequency

    private var currentLogFile: LogFile?
    
    private let queue = DispatchQueue(label: "com.swift.logsmith.filelogger.\(NSUUID().uuidString)")
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmssSSS"
        return formatter
    }()

    /// Public initializer for library consumers.
    ///
    /// - Parameters:
    ///   - logDirectoryName: The name of the subdirectory within the application's support directory where log files will be stored.
    ///   - rollingFrequency: The strategy used to determine when to roll the active log file into an archive.
    ///   - maximumArchiveFiles: The maximum number of archived log files to retain. Older archives will be purged if this limit is exceeded.
    ///                          Note: Setting this to 0 will result in all archives being purged as they are created.
    ///   - maximumDirectorySize: The maximum total size (in bytes) that the log directory should occupy on disk. This includes active log files and all archives.
    ///                           If the total size exceeds this limit, oldest archives will be purged until the limit is met.
    ///                           **Important Considerations for `maximumDirectorySize`:**
    ///                           - The actual disk usage includes file system overhead and ZIP compression overhead (e.g., ~170-200 bytes per ZIP file).
    ///                           - If individual log messages are very large, a single log file (and its subsequent archive) can exceed this limit.
    ///                           - While the system strives to adhere to `maximumDirectorySize`, it's a soft limit. If the smallest possible set of archives (e.g., just one remaining archive) still exceeds this size, that archive will *not* be arbitrarily deleted to meet the limit. Purging prioritizes retaining more recent logs up to the configured `maximumArchiveFiles`.
    ///
    /// - Throws: An `NSError` of domain `FileLoggerManager.ErrorDomain` if the `logDirectoryName` is invalid or the Application Support directory cannot be found.
    public convenience init(
        logDirectoryName: String = defaultDirectoryName,
        rollingFrequency: any RollingFrequency = SessionRollingFrequency(),
        maximumArchiveFiles: UInt = defaultMaxArchiveFiles,
        maximumDirectorySize: UInt64 = defaultMaxDirectorySize
    ) throws {
        // Validate inputs
        guard !logDirectoryName.contains("/") else {
            throw NSError(domain: FileLoggerManager.ErrorDomain, code: ErrorCode.invalidDirectoryName.rawValue, userInfo: [NSLocalizedDescriptionKey: "logDirectoryName cannot contain path separators."])
        }
        
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: FileLoggerManager.ErrorDomain, code: ErrorCode.directoryNotFound.rawValue, userInfo: [NSLocalizedDescriptionKey: "Cannot find Application Support directory."])
        }
        
        let appIdentifier = Bundle.main.bundleIdentifier ?? "com.unknown.app"
        let finalLogDirectoryURL = appSupportURL.appendingPathComponent(appIdentifier).appendingPathComponent(logDirectoryName)
        
        // Delegate to the internal, designated initializer
        try self.init(
            logDirectoryURL: finalLogDirectoryURL,
            rollingFrequency: rollingFrequency,
            maximumArchiveFiles: maximumArchiveFiles,
            maximumDirectorySize: maximumDirectorySize
        )
    }

    /// Internal initializer for testing and shared logic.
    ///
    /// - Parameters:
    ///   - logDirectoryURL: The URL to the directory where log files will be stored.
    ///   - rollingFrequency: The strategy used to determine when to roll the active log file into an archive.
    ///   - maximumArchiveFiles: The maximum number of archived log files to retain. Older archives will be purged if this limit is exceeded.
    ///                          Note: Setting this to 0 will result in all archives being purged as they are created.
    ///   - maximumDirectorySize: The maximum total size (in bytes) that the log directory should occupy on disk. This includes active log files and all archives.
    ///                           If the total size exceeds this limit, oldest archives will be purged until the limit is met.
    ///                           **Important Considerations for `maximumDirectorySize`:**
    ///                           - The actual disk usage includes file system overhead and ZIP compression overhead (e.g., ~170-200 bytes per ZIP file).
    ///                           - If individual log messages are very large, a single log file (and its subsequent archive) can exceed this limit.
    ///                           - While the system strives to adhere to `maximumDirectorySize`, it's a soft limit. If the smallest possible set of archives (e.g., just one remaining archive) still exceeds this size, that archive will *not* be arbitrarily deleted to meet the limit. Purging prioritizes retaining more recent logs up to the configured `maximumArchiveFiles`.
    ///
    /// - Throws: An `NSError` if directory creation fails.
    internal init(
        logDirectoryURL: URL,
        rollingFrequency: any RollingFrequency,
        maximumArchiveFiles: UInt,
        maximumDirectorySize: UInt64
    ) throws {
        self.logDirectoryURL = logDirectoryURL
        self.rollingFrequency = rollingFrequency
        self.maximumArchiveFiles = maximumArchiveFiles
        self.maximumDirectorySize = maximumDirectorySize
        
        super.init()
        
        try fileManager.createDirectory(at: self.logDirectoryURL, withIntermediateDirectories: true, attributes: nil)
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
                case .undefined: result = false
                case .name: result = lhsURL.lastPathComponent.compare(rhsURL.lastPathComponent) == .orderedAscending
                case .size: result = UInt64(lhsValues?.fileSize ?? 0) < UInt64(rhsValues?.fileSize ?? 0)
                case .createdAt: result = (lhsValues?.creationDate ?? .distantPast) < (rhsValues?.creationDate ?? .distantPast)
                case .modifiedAt: result = (lhsValues?.contentModificationDate ?? .distantPast) < (rhsValues?.contentModificationDate ?? .distantPast)
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
            var deletionErrors: [NSError] = []
            for file in self.listLogFiles() {
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
                } else {
                    let userInfo: [String: Any] = [ NSLocalizedDescriptionKey: "Failed to clear one or more logs.", FileLoggerManager.FailedDeletionsKey: deletionErrors ]
                    completion(NSError(domain: FileLoggerManager.ErrorDomain, code: ErrorCode.clearLogsFailed.rawValue, userInfo: userInfo))
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
            completion?(nil)
        } catch let error as NSError {
            completion?(error)
        } catch {
            completion?(error as NSError)
        }
    }

    private func createNewLogFile() {
        let timestamp = dateFormatter.string(from: Date())
        let newURL = logDirectoryURL.appendingPathComponent("SLS_\(timestamp).log")
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
            let userInfo: [String: Any] = [ NSLocalizedDescriptionKey: "Failed to purge one or more log archives.", FileLoggerManager.FailedDeletionsKey: deletionErrors ]
            throw NSError(domain: FileLoggerManager.ErrorDomain, code: ErrorCode.purgeFailed.rawValue, userInfo: userInfo)
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

