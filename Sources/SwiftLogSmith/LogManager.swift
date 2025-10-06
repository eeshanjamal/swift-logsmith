//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objcMembers
final class LogManager: NSObject, ILogger, @unchecked Sendable {
    
    private var loggers: Array<any ILogger>
    private var logPrefixes: LogTagCollection
    private var logPostfixes: LogTagCollection
    private let queue = DispatchQueue(label: "com.swift.logman")
    
    private override init() {
        loggers = []
        logPrefixes = LogTagCollection()
        logPostfixes = LogTagCollection()
        super.init()
    }
    
    public init(defaultLogger: any ILogger) {
        loggers = [defaultLogger]
        logPrefixes = LogTagCollection()
        logPostfixes = LogTagCollection()
        super.init()
    }
    
    //MARK: Logger API's
    
    public func addLogger(newLogger: any ILogger, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let newLoggerType = type(of: newLogger)
            guard !self.loggers.contains(where: { type(of: $0) == newLoggerType}) else {
                completion?(false)
                return
            }
            self.loggers.append(newLogger)
            completion?(true)
        }
    }
    
    public func removeLogger(logger: any ILogger, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let loggerType = type(of: logger)
            if let index = self.loggers.firstIndex(where: {type(of: $0) == loggerType}) {
                self.loggers.remove(at: index)
                completion?(true)
            }
            else {
                completion?(false)
            }
        }
    }
    
    //MARK: Log Prefix API's
    
    public func addLogPrefix(logPrefix: LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            self.logPrefixes.addTag(logPrefix, completion)
        }
    }
    
    public func  removeLogPrefix(identifier: String, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            self.logPrefixes.removeTag(identifier, completion)
        }
    }
    
    //MARK: Log Postfix API's
    
    public func addLogPostfix(logPostfix: LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            self.logPostfixes.addTag(logPostfix, completion)
        }
    }
    
    public func  removeLogPostfix(identifier: String, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            self.logPostfixes.removeTag(identifier, completion)
        }
    }
    
    //MARK: ILogger protocol implmentation
    
    func log(type: LogType, message: String) {
        queue.async {
            self.addOnLogMessage(logType: type, message: message) { finalMessage in
                self.loggers.forEach { logger in
                    logger.log(type: type, message: finalMessage)
                }
            }
        }
    }
    
    //MARK: Private API's
    
    private func addOnLogMessage(logType: LogType? = nil, message: String, completion: @escaping (@Sendable(String) -> Void)) {
        logPrefixes.toNoTypeString { noTypePrefix in
            self.logPostfixes.toNoTypeString { noTypePostfix in
                if let logType = logType {
                    self.logPrefixes.toTypeString(logType: logType) { typePrefix in
                        self.logPostfixes.toTypeString(logType: logType) { typePostfix in
                            completion("\(noTypePrefix) \(typePrefix) \(message) \(typePostfix) \(noTypePostfix)")
                        }
                    }
                }
                else {
                    completion("\(noTypePrefix) \(message) \(noTypePostfix)")
                }
            }
        }
    }
    
}
