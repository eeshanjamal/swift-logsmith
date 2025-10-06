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
    
    func log(type: LogType, message: String) {
        switch type {
        case .none:
            logger.log("\(message)")
        case .notice:
            logger.notice("\(message)")
        case .info:
            logger.info("\(message)")
        case .debug:
            logger.debug("\(message)")
        case .trace:
            logger.trace("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        case .fault:
            logger.fault("\(message)")
        case .critical:
            logger.critical("\(message)")
        }
    }
    
}

