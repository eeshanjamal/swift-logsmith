//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objc protocol ILogger: Sendable {
    
    @objc optional var logTagger: LogTagger { get }
    @objc func log(type: LogType, message: String)
    
}
