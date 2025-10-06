//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objc protocol ILogger: Sendable {
    
    @objc func log(type: LogType, message: String)
    
}
