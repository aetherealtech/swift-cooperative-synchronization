import XCTest

@testable import CooperativeSynchronization

import AsyncExtensions

final class SerialQueueTests: XCTestCase {
    func testQueue() async throws {
        let queue = SerialQueue()
        
        let testTask: (Int) async -> Void = { index in
            print("STARTING: \(index)")
            do {
                try await Task.sleep(timeInterval: 1.0)
                print("FINISHING: \(index)")
            } catch {
                print("CANCELLING: \(index)")
            }
        }

        let tasks = (0..<10).map { index in
            queue.schedule { await testTask(index) }
        }
        
        try await Task.sleep(timeInterval: 10)
    }
}
