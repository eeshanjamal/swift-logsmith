//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation
import OSLog

@objcMembers
final class OSLogger: NSObject, ILogger {
    
    private let logger: Logger
    
    override init() {
        logger = Logger()
        super.init()
    }
    
    public init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
        super.init()
    }
    
    func log(_ message: String) {
        logger.log("\(message)")
    }
    
    func trace(_ message: String) {
        logger.trace("\(message)")
    }
    
    func debug(_ message: String) {
        logger.debug("\(message)")
    }
    
    func notice(_ message: String) {
        logger.notice("\(message)")
    }
    
    func info(_ message: String) {
        logger.info("\(message)")
    }
    
    func warning(_ message: String) {
        logger.warning("\(message)")
    }
    
    func error(_ message: String) {
        logger.error("\(message)")
    }
    
    func critical(_ message: String) {
        logger.critical("\(message)")
    }
    
    func fault(_ message: String) {
        logger.fault("\(message)")
    }
    
}

