import XCTest

@testable import CooperativeSynchronization

import Assertions
import AsyncExtensions
import AsyncCollectionExtensions
import Combine

actor MockScheduler: CooperativeSynchronization.Scheduler {
    struct JobConfig: JobConfigProtocol {}
    
    actor CancelHandle: Cancellable {
        var cancelled = false
        
        nonisolated func cancel() {
            Task { await setCancelled() }
        }
        
        private func setCancelled() {
            cancelled = true
        }
    }
    
    private(set) var scheduledWork: [@Sendable () async throws -> Void] = []
    
    private(set) var scheduleImp: (JobConfig, @escaping @Sendable () async throws -> Void) async -> CancelHandle = { _, _ in fatalError("No setup") }
    func schedule(config: JobConfig, _ work: @escaping @Sendable () async throws -> Void) async -> CancelHandle {
        await scheduleImp(config, work)
    }
    
    func setup(schedule: @escaping @Sendable (JobConfig, @escaping @Sendable () async throws -> Void) async -> CancelHandle) {
        scheduleImp = schedule
    }
    
    func cancelAll() {}
}

final class QueueExtensionsTests: XCTestCase {
    func testWaitScheduleImmediately() async throws {
        let scheduler = MockScheduler()

        await scheduler.setup(schedule: { _, work in
            try! await work()
            return .init()
        })
        
        let expectedResult = Int.random(in: 0..<10000)
        
        let task = await scheduler.schedule { () async -> Int in
            return expectedResult
        }
        
        let result = try await task.value
        
        try assertEqual(result, expectedResult)
    }
    
    func testWaitScheduleLater() async throws {
        let scheduler = MockScheduler()

        let _recordedWork = Isolated<(@Sendable () async throws -> Void)?>(nil)
        
        await scheduler.setup(schedule: { _, work in
            await _recordedWork.write { recoredWork in recoredWork = work }
            return .init()
        })
        
        let expectedResult = Int.random(in: 0..<10000)
        
        let task = await scheduler.schedule { () async -> Int in
            return expectedResult
        }
        
        let result = try await task.value
        
        try assertEqual(result, expectedResult)
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
