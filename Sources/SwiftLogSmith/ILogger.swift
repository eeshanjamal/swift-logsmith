//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objc protocol ILogger: Sendable {
    
    var logTagger: LogTagger? { get }
    var formatter: any LogFormatter { get }
    func log(message: LogMessage)   
}
