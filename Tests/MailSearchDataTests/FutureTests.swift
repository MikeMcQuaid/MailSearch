import NIOCore
import NIOTransportServices
import Testing

@Test
func `event loop future handoffs preserve values and errors under contention`() async throws {
    let eventLoops = NIOTSEventLoopGroup(loopCount: 2)
    await withTaskGroup(of: Void.self) { tasks in
        for _ in 0 ..< 16 {
            tasks.addTask {
                let eventLoop = eventLoops.next()
                for value in 0 ..< 1_000 {
                    do {
                        let received = try await eventLoop.submit {
                            if value.isMultiple(of: 2) {
                                throw ChannelError.eof
                            }
                            return value
                        }
                        .get()
                        #expect(value.isMultiple(of: 2) == false && received == value)
                    } catch {
                        #expect(value.isMultiple(of: 2) && error as? ChannelError == .eof)
                    }
                }
            }
        }
    }
    try await eventLoops.shutdownGracefully()
}
