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
    let formatter: LogFormatter
    let tagger: LogTagger?
    
    init(logFormatter: LogFormatter = LogFormatter.default, logTagger: LogTagger? = nil) {
        logger = Logger()
        formatter = logFormatter
        tagger = logTagger
    }
    
    init(subsystem: String, category: String, logFormatter: LogFormatter = LogFormatter.default, logTagger: LogTagger? = nil) {
        logger = Logger(subsystem: subsystem, category: category)
        formatter = logFormatter
        tagger = logTagger
    }
    
    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)? = nil) {
        let formattedMessage = formatter.format(message: message)
        var didLog = true
        switch message.logType {
        case .undefined: 
            didLog = false
        case .none:
            logger.log("\(formattedMessage)")
        case .notice:
            logger.notice("\(formattedMessage)")
        case .info:
            logger.info("\(formattedMessage)")
        case .debug:
            logger.debug("\(formattedMessage)")
        case .trace:
            logger.trace("\(formattedMessage)")
        case .warning:
            logger.warning("\(formattedMessage)")
        case .error:
            logger.error("\(formattedMessage)")
        case .fault:
            logger.fault("\(formattedMessage)")
        case .critical:
            logger.critical("\(formattedMessage)")
        }
        completion?(didLog)
    }
    
}


