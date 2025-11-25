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
    
    func log(message: LogMessage) {
        switch message.logType {
        case .undefined: break //Nothing need to be done here
        case .none:
            logger.log("\(message.completeMessage)")
        case .notice:
            logger.notice("\(message.completeMessage)")
        case .info:
            logger.info("\(message.completeMessage)")
        case .debug:
            logger.debug("\(message.completeMessage)")
        case .trace:
            logger.trace("\(message.completeMessage)")
        case .warning:
            logger.warning("\(message.completeMessage)")
        case .error:
            logger.error("\(message.completeMessage)")
        case .fault:
            logger.fault("\(message.completeMessage)")
        case .critical:
            logger.critical("\(message.completeMessage)")
        }
    }
    
}

