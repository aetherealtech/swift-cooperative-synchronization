import XCTest

@testable import CooperativeSynchronization

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

        let tasks: [Task<Void, Never>] = await (0..<10).mapAsync { index in
            await queue.schedule { await testTask(index) }
        }
  
        await tasks
            .map { task in { @Sendable in await task.value } }
            .awaitAll()
        
        for index in tasks.indices.dropFirst() {
            let (taskRunTime, previousTaskRunTime) = await _runTimes.read { runTimes in (runTimes[index], runTimes[index - 1]) }
            
            guard let taskRunTime, let previousTaskRunTime else {
                XCTFail("Missing task run time")
                return
            }
            
            XCTAssertTrue(taskRunTime.lowerBound > previousTaskRunTime.upperBound)
        }
    }
    
    func testCancel() async throws {
        let queue = SerialQueue()
        
        let testTask: @Sendable (Int) async -> Void = { index in
            print("STARTING: \(index)")
            do {
                try await Task.sleep(timeInterval: 1.0)
                print("FINISHING: \(index)")
            } catch {
                print("CANCELLING: \(index)")
            }
        }

        let tasks: [Task<Void, Never>] = await (0..<10).mapAsync { index in
            await queue.schedule { await testTask(index) }
        }
        
        try await Task.sleep(timeInterval: 3)
        
        tasks.forEach { $0.cancel() }
        
        try await Task.sleep(timeInterval: 10)
    }
    
    func testWait() async throws {
        let queue = SerialQueue()
        
        let testTask: @Sendable (Int) async -> Void = { index in
            print("STARTING: \(index)")
            do {
                try await Task.sleep(timeInterval: 1.0)
                print("FINISHING: \(index)")
            } catch {
                print("CANCELLING: \(index)")
            }
        }

        let tasks = await (0..<10).mapAsync { index in
            await queue.schedule { await testTask(index) }
        }
        
        let finalTask = await queue.schedule { () async -> Int in
            print("Kaboom")
            return 55
        }
        
        let result = try await finalTask.value
        
        print("TEST")
    }
    
    func testWaitPreCancel() async throws {
        let queue = SerialQueue()
        
        let testTask: @Sendable (Int) async -> Void = { index in
            print("STARTING: \(index)")
            do {
                try await Task.sleep(timeInterval: 1.0)
                print("FINISHING: \(index)")
            } catch {
                print("CANCELLING: \(index)")
            }
        }

        let tasks = await (0..<10).mapAsync { index in
            await queue.schedule { await testTask(index) }
        }
        
        let resultTask = await queue.schedule { () async -> Int in
            print("Kaboom")
            return 55
        }

        resultTask.cancel()
        
        let result = await Result { try await resultTask.value }
        
        print("TEST")
    }
    
    func testWaitAndCancelBeforeSchedule() async throws {
        let queue = SerialQueue()
        
        let testTask: @Sendable (Int) async -> Void = { index in
            print("STARTING: \(index)")
            do {
                try await Task.sleep(timeInterval: 1.0)
                print("FINISHING: \(index)")
            } catch {
                print("CANCELLING: \(index)")
            }
        }

        let tasks = await (0..<10).mapAsync { index in
            await queue.schedule { await testTask(index) }
        }
        
        let resultTask = await queue.schedule { () async -> Int in
            print("Kaboom")
            return 55
        }
        
        try await Task.sleep(timeInterval: 0.1)
        
        resultTask.cancel()
        
        let result = await Result { try await resultTask.value }
        
        print("TEST")
    }
    
    func testWaitAndCancelAfterSchedule() async throws {
        let queue = SerialQueue()
        
        let resultTask = await queue.schedule { () async -> Int in
            print("STARTING")
            defer { print("FINISHING") }
            
            try? await Task.sleep(timeInterval: 5.0)
            return 55
        }
        
        try await Task.sleep(timeInterval: 0.5)
        
        resultTask.cancel()
        
        let result = await Result { try await resultTask.value }
                
        print("TEST")
    }
}
