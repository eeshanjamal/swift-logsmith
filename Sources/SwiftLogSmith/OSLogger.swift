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
    let formatter: any LogFormatter
    let logTagger: LogTagger?
    
    init(formatter: any LogFormatter = DefaultLogFormatter(), logTagger: LogTagger? = nil) {
        self.logger = Logger()
        self.formatter = formatter
        self.logTagger = logTagger
    }
    
    init(subsystem: String, category: String, formatter: any LogFormatter = DefaultLogFormatter(), logTagger: LogTagger? = nil) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.formatter = formatter
        self.logTagger = logTagger
    }
    
    func log(message: LogMessage) {
        let formattedMessage = formatter.format(message: message)
        switch message.logType {
        case .undefined: break //Nothing need to be done here
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
    }
    
}


