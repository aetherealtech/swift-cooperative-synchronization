import XCTest

@testable import CooperativeSynchronization

import AsyncExtensions
import Synchronization

final class SerialQueueTests: XCTestCase {
    func testQueue() async throws {
        let queue = SerialQueue()
        
        @Synchronization.Synchronized
        var runTimes: [Int: Range<Date>] = [:]
        
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
            
            _runTimes.write { runTimes in runTimes[index] = start..<end }
        }

        let tasks: [Task<Void, Never>] = (0..<10).map { index in
            queue.schedule { await testTask(index) }
        }
        
        await tasks
            .map { task in { @Sendable in await task.value } }
            .awaitAll()
        
        for index in tasks.indices.dropFirst() {
            guard let taskRunTime = runTimes[index], let previousTaskRunTime = runTimes[index - 1] else {
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

        let tasks = (0..<10).map { index in
            queue.schedule { await testTask(index) }
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

        let tasks = (0..<10).map { index in
            queue.schedule { await testTask(index) }
        }
        
        let result = try await queue.schedule { () async -> Int in
            print("Kaboom")
            return 55
        }.value
        
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

        let tasks = (0..<10).map { index in
            queue.schedule { await testTask(index) }
        }
        
        let resultTask = queue.schedule { () async -> Int in
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

        let tasks = (0..<10).map { index in
            queue.schedule { await testTask(index) }
        }
        
        let resultTask = queue.schedule { () async -> Int in
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
        
        let resultTask = queue.schedule { () async -> Int in
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
