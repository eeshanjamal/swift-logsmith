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
    private let queue = DispatchQueue(label: "com.swift.logman")
    
    private override init() {
        loggers = []
        super.init()
    }
    
    public init(defaultLogger: any ILogger) {
        loggers = [defaultLogger]
        super.init()
    }
    
    public func addLogger(_ newLogger: any ILogger,_ completion: (@Sendable(Bool) -> Void)? = nil) {
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
    
    public func removeLogger(_ logger: any ILogger,_ completion: (@Sendable(Bool) -> Void)? = nil) {
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
    
    //MARK: ILogger protocol implmentation
    
    func log(_ message: String) {
        queue.async { self.loggers.forEach { $0.log(message) } }
    }
    
    func trace(_ message: String) {
        queue.async { self.loggers.forEach { $0.trace(message) } }
    }
    
    func debug(_ message: String) {
        queue.async { self.loggers.forEach { $0.debug(message) } }
    }
    
    func notice(_ message: String) {
        queue.async { self.loggers.forEach { $0.notice(message) } }
    }
    
    func info(_ message: String) {
        queue.async { self.loggers.forEach { $0.info(message) } }
    }
    
    func warning(_ message: String) {
        queue.async { self.loggers.forEach { $0.warning(message) } }
    }
    
    func error(_ message: String) {
        queue.async { self.loggers.forEach { $0.error(message) } }
    }
    
    func critical(_ message: String) {
        queue.async { self.loggers.forEach { $0.critical(message) } }
    }
    
    func fault(_ message: String) {
        queue.async { self.loggers.forEach { $0.fault(message) } }
    }
    
}
