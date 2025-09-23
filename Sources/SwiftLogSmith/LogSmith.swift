//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objcMembers
final class LogSmith: NSObject, @unchecked Sendable {
    
    private static let shared = LogSmith()
    
    private let defaultManager = LogManager(defaultLogger: OSLogger())
    private let queue = DispatchQueue(label: "com.swift.logsmith")
    
    private override init() {
        super.init()
    }
    
    public static func addLogger(_ newLogger: any ILogger,_ completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.addLogger(newLogger, completion) }
    }
    
    public static func removeLogger(_ logger: any ILogger,_ completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.removeLogger(logger, completion) }
    }
    
    public static func log(_ message: String) {
        shared.queue.async { shared.defaultManager.log(message) }
    }
    
    public static func logT(_ message: String) {
        shared.queue.async { shared.defaultManager.trace(message) }
    }
    
    public static func logD(_ message: String) {
        shared.queue.async { shared.defaultManager.debug(message) }
    }
    
    public static func logN(_ message: String) {
        shared.queue.async { shared.defaultManager.notice(message) }
    }
    
    public static func logI(_ message: String) {
        shared.queue.async { shared.defaultManager.info(message) }
    }
    
    public static func logW(_ message: String) {
        shared.queue.async { shared.defaultManager.warning(message) }
    }
    
    public static func logE(_ message: String) {
        shared.queue.async { shared.defaultManager.error(message) }
    }
    
    public static func logC(_ message: String) {
        shared.queue.async { shared.defaultManager.critical(message) }
    }
    
    public static func logF(_ message: String) {
        shared.queue.async { shared.defaultManager.fault(message) }
    }
    
}
