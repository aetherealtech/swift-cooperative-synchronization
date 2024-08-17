import XCTest

@testable import CooperativeSynchronization

import Assertions
import AsyncExtensions
import AsyncCollectionExtensions

final class SerialQueueTests: XCTestCase {
    func testQueue() async throws {
        let queue = SerialQueue()
        
        let _runTimes = Isolated([:] as [Int: Range<Date>])
        
        let testTask: @Sendable (Int) async -> Void = { [_runTimes] index in
            let start = Date()
            print("STARTING: \(index)")
            
            do {
                try await Task.sleep(timeInterval: 0.25)
                print("FINISHING: \(index)")
            } catch {
                print("CANCELLING: \(index)")
            }
            
            let end = Date()
            
            await _runTimes.write { runTimes in runTimes[index] = start..<end }
        }

        let tasks: [SerialQueue.CancelHandle] = await (0..<10).mapAsync { index in
            await queue.schedule { await testTask(index) }
        }
  
        await tasks
            .map { task in { @Sendable in await task.value } }
            .awaitAll()
        
        for index in tasks.indices.dropFirst() {
            let (taskRunTime, previousTaskRunTime) = await _runTimes.read { runTimes in (runTimes[index], runTimes[index - 1]) }
            
            guard let taskRunTime, let previousTaskRunTime else {
                throw Fail("Missing task run time")
            }
            
            try assertTrue(taskRunTime.lowerBound > previousTaskRunTime.upperBound)
        }
    }
}
