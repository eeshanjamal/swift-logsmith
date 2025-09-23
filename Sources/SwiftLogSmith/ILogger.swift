//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objc protocol ILogger: Sendable {
    
    @objc func log(_ message: String)
    @objc func trace(_ message: String)
    @objc func debug(_ message: String)
    @objc func notice(_ message: String)
    @objc func info(_ message: String)
    @objc func warning(_ message: String)
    @objc func error(_ message: String)
    @objc func critical(_ message: String)
    @objc func fault(_ message: String)
    
}
