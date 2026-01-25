//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest

extension XCTestCase {
    /// A helper function to wrap the boilerplate of creating an expectation and waiting for it.
    /// - Parameters:
    ///   - description: The description of the expectation.
    ///   - fulfillmentCount:The number of times fulfill() must be called before the expectation is completely fulfilled. Default value is 1.
    ///   - timeout: The timeout for the expectation. Defaults to 1.0 second.
    ///   - operation: The asynchronous operation to perform. The closure provides a `fulfill`
    ///     function that must be called to complete the expectation.
    func expectCompletion(description: String, fulfillmentCount: Int = 1, timeout: TimeInterval = 1.0, operation: (_ fulfill: @escaping @Sendable () -> Void) -> Void) {
        let expectation = XCTestExpectation(description: description)
        expectation.expectedFulfillmentCount = fulfillmentCount
        operation {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }
}
