//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objc protocol ILogger: Sendable {
    
    var tagger: LogTagger? { get }
    var formatter: LogFormatter { get }
    func log(message: LogMessage)   
}
