//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation
import ZIPFoundation

/// An enum to sort the list of log files.
///
/// It provides various sort keys based on ``LogFile`` properties to sort the list of files.
@objc public enum LogFileSortKey: Int {
    /// Sort property is not specified.
    case undefined
    /// Sort by ``LogFile.name`` property.
    case name
    /// Sort by ``LogFile.createdAt`` property.
    case createdAt
    /// Sort by ``LogFile.modifiedAt`` property.
    case modifiedAt
    /// Sort by ``LogFile.size`` property.
    case size
}

/// An enum to specify the direction of sort for the list of log files.
@objc public enum SortOrder: Int {
    /// Sort in ascending order (e.g., A-Z, 0-9, oldest to newest).
    case ascending
    /// Sort in descending order (e.g., Z-A, 9-0, newest to oldest).
    case descending
}

/// An ``ILogger`` complaint class that logs to a file.
///
/// `FileLogger` formats the raw `LogMessage` into a formatted one and forward it to the ``FileLoggerManager`` instance which actually manages the file I/O operations.
///
/// **FileLoggerManager Behavior**
///
/// It's a comprehensive class to manage all the file logging related operations (such as writing, rolling, archiving and purging).
/// You can either use the default instance of it or provide a one with custom configurations.
///
/// **Usage with Custom Configs**
///
/// While you can instantiate `FileLogger` with default configs, There maybe cases where you're required to have custom configuration.
///
/// ```swift
/// do {
///     // Create a manager with custom rolling and purging rules
///     let manager = try FileLoggerManager(
///         rollingFrequency: TimeRollingFrequency(rollingInterval: 3600), // Roll every hour
///         maximumArchiveFiles: 10
///     )
///
///     // Create the logger with the custom manager
///     let fileLogger = FileLogger(fileLoggerManager: manager)
///
///     // Add it to LogSmith
///     LogSmith.addLogger(newLogger: fileLogger)
/// } catch {
///     print("Failed to set up file logger: \(error)")
/// }
/// ```
@objcMembers
final class FileLogger: NSObject, ILogger {
    
    let tagger: LogTagger?
    let formatter: LogFormatter
    
    /// The ``FileLoggerManager`` instance responsible for all file I/O, rolling, archiving and purging operations.
    let manager: FileLoggerManager
    
    /// Creates a new `FileLogger` instance.
    ///
    /// - Parameters:
    ///   - logFormatter: The ``LogFormatter`` to use for structuring the log message. Defaults to ``LogFormatter.default``.
    ///   - logTagger: An optional ``LogTagger`` to automatically add tags to the logs of this specific logger.
    ///   - fileLoggerManager: The ``FileLoggerManager`` that will handle the underlying file I/O operations. Defaults to a new manager with standard settings.
    init(logFormatter: LogFormatter = LogFormatter.default, logTagger: LogTagger? = nil, fileLoggerManager: FileLoggerManager = try! FileLoggerManager()) {
        formatter = logFormatter
        tagger = logTagger
        manager = fileLoggerManager
    }
    
    /// Formats the ``LogMessage`` and forward it to the ``FileLoggerManager`` for writing into the current log file.
    /// - Parameters:
    ///   - message: The ``LogMessage`` object to be logged.
    ///   - completion: An optional closure called after the write operation completes. It returns `true` if the write was successful.
    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)? = nil) {
        manager.write(log: formatter.format(message: message)) { error in
            completion?(error == nil)
        }
    }
}

/// A manager to manage the entire lifecycle of log files, including writing, rolling, archiving, and purging.
///
/// This class handles all the low-level details of writing logs to disk. Its key responsibilities include:
/// - **Writing:** Appending log strings to the current active log file.
/// - **Rolling:** Automatically rolling the current log file with a new one when the rolling frequency condition satisfied (e.g., exceeds a size limit or a time interval).
/// - **Archiving:** Compressing rolled log files into `.zip` archives to save disk space.
/// - **Purging:** Deleting the oldest archives to stay within configured storage limits (of maximum directory size & file count).
///
/// All file operations are performed asynchronously on a dispatch queue to ensure thread safety.
@objcMembers
final class FileLoggerManager: NSObject, @unchecked Sendable {
    
    /// A domain used by this class when throwing `NSError`.
    public static let ErrorDomain = "com.swift.logsmith.FileLoggerManager.ErrorDomain"
    /// A key used by this class to store an array of errors inside `NSError`'s `userInfo` dictionary (which may occurred during a composite operation like purging or clearing).
    public static let FailedDeletionsKey = "FileLoggerManagerFailedDeletionsKey"
    
    /// An enum with different error codes for `FileLoggerManager` operations failure.
    @objc public enum ErrorCode: Int {
        /// An error occurred during the purging of old log archives. Check the `FailedDeletionsKey` in `userInfo` for details.
        case purgeFailed
        /// The manager could not find or create a log file to write logs.
        case fileNotFound
        /// The log string could not be converted to UTF-8 data for writing.
        case dataPrepareFailed
        /// One or more files could not be deleted during a `clearLogs` operation.
        case clearLogsFailed
        /// The provided `logDirectoryName` contained invalid characters (e.g., '/').
        case invalidDirectoryName
        /// The system's Application Support directory could not be located.
        case directoryNotFound
    }
    
    /// The default name of the directory where logs are stored ("LogSmith").
    public static let defaultDirectoryName = "LogSmith"
    
    #if os(watchOS)
    /// The default maximum number of archived log files to keep on watchOS (10).
    public static let defaultMaxArchiveFiles: UInt = 10
    /// The default maximum size of the log directory on watchOS (10 MB).
    public static let defaultMaxDirectorySize: UInt64 = 10 * 1024 * 1024 // 10 MB
    #elseif os(tvOS)
    /// The default maximum number of archived log files to keep on tvOS (5).
    public static let defaultMaxArchiveFiles: UInt = 5
    /// The default maximum size of the log directory on tvOS (5 MB).
    public static let defaultMaxDirectorySize: UInt64 = 5 * 1024 * 1024 // 5 MB
    #else // macOS, iOS, iPadOS, visionOS etc.
    /// The default maximum number of archived log files to keep on macOS, iOS, iPadOS & visionOS (100).
    public static let defaultMaxArchiveFiles: UInt = 100
    /// The default maximum size of the log directory on macOS, iOS, iPadOS & visionOS (100 MB).
    public static let defaultMaxDirectorySize: UInt64 = 100 * 1024 * 1024 // 100 MB
    #endif
    
    /// The URL of the directory where log files and archives are stored.
    public let logDirectoryURL: URL
    /// The maximum number of archived log files to retain. When this limit is exceeded, the oldest archives are purged.
    public let maximumArchiveFiles: UInt
    /// The target maximum size (in bytes) for the log directory. When this limit is exceeded, the oldest archives are purged.
    public let maximumDirectorySize: UInt64
    /// The strategy used to determine when the active log file should be rolled into an archive.
    public let rollingFrequency: any RollingFrequency

    private var currentLogFile: LogFile?
    
    private let queue = DispatchQueue(label: "com.swift.logsmith.filelogger.\(NSUUID().uuidString)")
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmssSSS"
        return formatter
    }()

    /// Creates a new `FileLoggerManager` instance with customizable settings.
    ///
    /// - Parameters:
    ///   - logDirectoryName: The name of the subdirectory within the application's support directory where logs will be stored. Defaults to `LogSmith`. It should be alphanumeric otherwise may result in an error.
    ///   - rollingFrequency: The strategy for when to roll the active log file. Defaults to `SessionRollingFrequency()`.
    ///   - maximumArchiveFiles: The maximum number of archived log files to keep. Older archives are purged if this limit is exceeded. Defaults to `defaultMaxArchiveFiles`.
    ///   - maximumDirectorySize: The target maximum total size (in bytes) of the log directory. Older archives are purged to stay near this limit. Defaults to `defaultMaxDirectorySize`.
    ///
    /// - Throws: An `NSError` if the `logDirectoryName` is invalid or the log directory cannot be found.
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

    /// Asynchronously writes a log string to the current log file.
    ///
    /// It will automatically handle file rolling and purging as needed before performing the write operation.
    /// - Parameters:
    ///   - log: The formatted log string to write.
    ///   - completion: An optional closure that is called after the write operation finishes. It receives an `NSError` object if an error occurred.
    public func write(log: String, completion: (@Sendable(NSError?) -> Void)? = nil) {
        queue.async { self._write(log, completion: completion) }
    }
    
    /// Lists all log files (including active and archived) within the log directory of this manager.
    /// - Parameters:
    ///   - filterByExtensions: An optional array of file extensions to filter by (e.g., `["log"]`, `["zip"]`).
    ///   - sortBy: The ``LogFileSortKey`` to use for sorting. Defaults to `.undefined`.
    ///   - order: The ``SortOrder`` to use for sorting (ascending or descending).
    /// - Returns: An array of ``LogFile`` objects matching the criteria.
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
    
    /// Asynchronously deletes all log files within the log directory of this manager.
    /// - Parameter completion: An optional closure called after the operation finishes. It receives an `NSError` object if one or more files could not be deleted.
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

/// A data object that represents a single log file on disk.
///
/// This class provides a convenient, object-oriented way to access the properties of a log file, such as its URL, name, and file attributes (creation date, size, etc.).
@objcMembers
final class LogFile: NSObject {
    
    /// The full URL of the log file.
    public let url: URL
    
    /// Creates a new `LogFile` instance with provided ``URL``.
    ///
    /// - Parameters:
    ///   - url: The ``URL`` of the file where it's actually stored on disk.
    public init(url: URL) {
        self.url = url
        super.init()
    }

    /// The name of the file, including its extension.
    public var name: String {
        url.lastPathComponent
    }
    
    /// The full path of the file as a string.
    public var path: String {
        url.path
    }
    
    /// A boolean indicating whether the file currently exists on disk.
    public var isExist: Bool {
        FileManager.default.fileExists(atPath: path)
    }
    
    /// The creation date of the file. Returns `nil` if the file attributes cannot be read.
    public var createdAt: Date? {
        return attributes()?[.creationDate] as? Date
    }
    
    /// The last modification date of the file. Returns `nil` if the file attributes cannot be read.
    public var modifiedAt: Date? {
        return attributes()?[.modificationDate] as? Date
    }
    
    /// The size of the file in bytes. Returns `0` if the file attributes cannot be read.
    public var size: UInt64 {
        return attributes()?[.size] as? UInt64 ?? 0
    }
    
    private func attributes() -> [FileAttributeKey: Any]? {
        return try? FileManager.default.attributesOfItem(atPath: path)
    }
}

/// A protocol that defines a strategy for determining when to roll the active log file.
@objc protocol RollingFrequency {
    
    /// Determines if the current log file should be rolled based on the implementing strategy's criteria.
    /// - Parameter logFile: The ``LogFile`` object representing the current active log file.
    /// - Returns: `true` if the file should be rolled, `false` otherwise.
    @objc func shouldRoll(logFile: LogFile) -> Bool
}

/// A ``RollingFrequency`` complaint class that rolls the log file if it's older than a specified time interval.
@objcMembers
final class TimeRollingFrequency: NSObject, RollingFrequency {
    
    private let rollingInterval: TimeInterval
    
    /// Creates a ``TimeRollingFrequency`` instance based on time rolling strategy.
    /// - Parameter rollingInterval: The maximum age of the log file in seconds. If the file is older than this, it will be rolled.
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

/// A ``RollingFrequency`` complaint class that rolls the log file if it exceeds a specific size.
@objcMembers
final class SizeRollingFrequency: NSObject, RollingFrequency {
    
    private let maxFileSize: UInt64
    
    /// Creates a ``SizeRollingFrequency`` instance based on size rolling strategy.
    /// - Parameter maxFileSize: The maximum size of the log file (in bytes). If the file's size exceeds this, it will be rolled.
    init(maxFileSize: UInt64) {
        self.maxFileSize = maxFileSize
    }
    
    func shouldRoll(logFile: LogFile) -> Bool {
        return logFile.size > maxFileSize
    }
}

/// A ``RollingFrequency`` complaint class that rolls the log file at the start of a new application session.
@objcMembers
final class SessionRollingFrequency: NSObject, RollingFrequency {
    
    /// Creates a ``SessionRollingFrequency`` instance based on app session rolling strategy.
    override init() {
        super.init()
    }
    
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

