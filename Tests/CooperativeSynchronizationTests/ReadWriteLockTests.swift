import XCTest

@testable import CooperativeSynchronization

import Assertions
import AsyncExtensions

final class ReadWriteLockTests: XCTestCase {
    func testWriter() async throws {
        let lock = ReadWriteLock()
        
        let _readers = Isolated(0)
        let _writing = Isolated(false)
        
        let waitUntil: @Sendable (Fence) async throws -> Void = { fence in
            try await withTimeout(after: Duration.seconds(2)) { try await fence.wait() }
        }
        
        let read = { @Sendable in
            let startedFence = Fence()
            let finishFence = Fence()

            let task = await lock.scheduleRead {
                await _readers.write { readers in readers += 1 }
                await startedFence.signal(reset: false)
                try await finishFence.wait()
                await _readers.write { readers in readers -= 1 }
            }
            
            return (task: task, started: startedFence, finish: finishFence)
        }
        
        let write = { @Sendable in
            let startedFence = Fence()
            let finishFence = Fence()

            let task = await lock.scheduleWrite {
                await _writing.write { writing in writing = true }
                await startedFence.signal(reset: false)
                try await finishFence.wait()
                await _writing.write { writing in writing = false }
            }
            
            return (task: task, started: startedFence, finish: finishFence)
        }

        let read1 = await read()
        let read2 = await read()
        let read3 = await read()
    
        let write1 = await write()

        let read4 = await read()
        let read5 = await read()
        let read6 = await read()
        
        try await waitUntil(read1.started)
        try await waitUntil(read2.started)
        try await waitUntil(read3.started)
        
        try await assertFalse(write1.started.signaled)
        
        await read1.finish.signal(reset: false)
        await read2.finish.signal(reset: false)
        await read3.finish.signal(reset: false)
        
        try await waitUntil(write1.started)
        
        try await assertFalse(read4.started.signaled)
        try await assertFalse(read5.started.signaled)
        try await assertFalse(read6.started.signaled)
        
        await write1.finish.signal(reset: false)
        
        try await waitUntil(read4.started)
        try await waitUntil(read5.started)
        try await waitUntil(read6.started)
        
        await read4.finish.signal(reset: false)
        await read5.finish.signal(reset: false)
        await read6.finish.signal(reset: false)
    }
}
