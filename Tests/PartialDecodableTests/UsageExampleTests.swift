import Testing
import Foundation
@testable import PartialDecodable

@Suite struct UsageExampleTests {

    struct Content: Decodable, Equatable {
        var text: String?
        var metadata: String?
    }

    struct Item: Decodable, Equatable {
        var data: Content?
        var description: String?
    }

    struct Response: Decodable, Equatable {
        var content: Content?
        var items: [Item]?
    }
    
    @Test func singleCharacterIncremental() async throws {
        let chunks = AsyncStream<String> { continuation in
            continuation.yield("{")
            continuation.yield("\"")
            continuation.yield("cont")
            continuation.yield("ent")
            continuation.yield("\"")
            continuation.yield(":")
            continuation.yield(" {")
            continuation.yield("\"")
            continuation.yield("tex")
            continuation.yield("t")
            continuation.yield("\"")
            continuation.yield(":")
            continuation.yield(" \"")
            continuation.yield("Hell")
            continuation.yield("o")
            continuation.yield("\"")
            continuation.yield("}")
            continuation.yield("}")
            continuation.finish()
        }

        var results: [Response] = []
        for try await chunk in incrementalDecode(Response.self, from: chunks) {
            results.append(chunk)
        }

        #expect(results.count > 0)
        #expect(results.last?.content?.text == "Hello")
    }

    @Test func incorrectUsagePattern() async throws {
        let fullJSON = #"{"content":{"text":"Hello"}}"#
        var errors: [Error] = []

        for char in fullJSON {
            do {
                for try await _ in incrementalDecode(Response.self, from: AsyncStream<String> { c in
                    c.yield(String(char))
                    c.finish()
                }) {
                }
            } catch {
                errors.append(error)
            }
        }

        #expect(errors.count > 0)
    }

    @Test func correctUsagePatternWithChunks() async throws {
        let chunks = AsyncStream<String> { continuation in
            continuation.yield(#"{"content":{"text":"He"#)
            continuation.yield(#"llo"}}"#)
            continuation.finish()
        }

        var results: [Response] = []
        for try await chunk in incrementalDecode(Response.self, from: chunks) {
            results.append(chunk)
        }

        #expect(results.count > 0)
        #expect(results.last?.content?.text == "Hello")
    }

    @Test func correctUsagePatternCharByChar() async throws {
        let fullJSON = #"{"content":{"text":"Hello"}}"#

        let charStream = AsyncStream<String> { continuation in
            for char in fullJSON {
                continuation.yield(String(char))
            }
            continuation.finish()
        }

        var results: [Response] = []
        for try await chunk in incrementalDecode(Response.self, from: charStream) {
            results.append(chunk)
        }

        #expect(results.count > 0)
        #expect(results.last?.content?.text == "Hello")
    }

    @Test func correctUsageWithURLSession() async throws {
        let jsonData = Data(#"{"content":{"text":"Streaming text"}}"#.utf8)

        let mockBytes = AsyncStream<UInt8> { continuation in
            for byte in jsonData {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        let stringStream = AsyncStream<String> { continuation in
            Task {
                var buffer = ""
                for await byte in mockBytes {
                    buffer.append(Character(UnicodeScalar(byte)))
                    if buffer.count >= 5 {
                        continuation.yield(buffer)
                        buffer = ""
                    }
                }
                if !buffer.isEmpty {
                    continuation.yield(buffer)
                }
                continuation.finish()
            }
        }

        var results: [Response] = []
        for try await chunk in incrementalDecode(Response.self, from: stringStream) {
            results.append(chunk)
        }

        #expect(results.count > 0)
        #expect(results.last?.content?.text == "Streaming text")
    }

    @Test func correctUsageWithAsyncBytes() async throws {
        let jsonData = Data(#"{"content":{"text":"Streaming text"}}"#.utf8)

        struct MockAsyncBytes: AsyncSequence, Sendable {
            typealias Element = UInt8

            let data: Data

            struct AsyncIterator: AsyncIteratorProtocol {
                var iterator: Data.Iterator

                mutating func next() async throws -> UInt8? {
                    return iterator.next()
                }
            }

            func makeAsyncIterator() -> AsyncIterator {
                return AsyncIterator(iterator: data.makeIterator())
            }
        }

        let mockAsyncBytes = MockAsyncBytes(data: jsonData)

        var results: [Response] = []
        for try await chunk in incrementalDecode(Response.self, asyncBytes: mockAsyncBytes) {
            results.append(chunk)
        }

        #expect(results.count > 0)
        #expect(results.last?.content?.text == "Streaming text")
    }
    
    @Test func correctUsageWithAsyncBytesInJapanese() async throws {
        let jsonData = Data(#"{"content":{"text":"こんにちは"}}"#.utf8)

        struct MockAsyncBytes: AsyncSequence, Sendable {
            typealias Element = UInt8

            let data: Data

            struct AsyncIterator: AsyncIteratorProtocol {
                var iterator: Data.Iterator

                mutating func next() async throws -> UInt8? {
                    return iterator.next()
                }
            }

            func makeAsyncIterator() -> AsyncIterator {
                return AsyncIterator(iterator: data.makeIterator())
            }
        }

        let mockAsyncBytes = MockAsyncBytes(data: jsonData)

        var results: [Response] = []
        for try await chunk in incrementalDecode(Response.self, asyncBytes: mockAsyncBytes) {
            results.append(chunk)
        }

        #expect(results.count > 0)
        #expect(results.first?.content?.text == nil)
        #expect(results.last?.content?.text == "こんにちは")
    }
}
