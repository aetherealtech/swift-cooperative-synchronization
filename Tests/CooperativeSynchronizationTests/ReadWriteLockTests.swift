import XCTest

@testable import CooperativeSynchronization

import AsyncExtensions

final class ReadWriteLockTests: XCTestCase {
    func testWriter() async throws {
        let lock = ReadWriteLock()
        
        let read = { @Sendable in
            try await lock.read {
                print("READING")
                try await Task.sleep(timeInterval: 1.0)
                print("DONE READING")
            }
        }
        
        let write = {
            try await lock.write {
                print("WRITING")
                try await Task.sleep(timeInterval: 1.0)
                print("DONE WRITING")
            }
        }
        
        async let read1 = read()
        async let read2 = read()
        async let read3 = read()
        
        try await Task.sleep(timeInterval: 0.1)
        
        async let write1 = write()
        
        try await Task.sleep(timeInterval: 0.1)
        
        async let read4 = read()
        async let read5 = read()
        async let read6 = read()
        
        try await read1
        try await read2
        try await read3
        try await write1
        try await read4
        try await read5
        try await read6
    }
}
