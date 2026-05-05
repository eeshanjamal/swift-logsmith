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
        // We isolate the unsafe calls here
        let label = unsafe __dispatch_queue_get_label(nil)
        return unsafe String(cString: label, encoding: .utf8)
    }
}
