//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

extension DispatchQueue {
    static var currentLabel: String? {
        #if swift(>=6.2)
            let label = unsafe __dispatch_queue_get_label(nil)
            return unsafe String(cString: label, encoding: .utf8)
        #else
            let label = __dispatch_queue_get_label(nil)
            return String(cString: label, encoding: .utf8)
        #endif
    }
}
