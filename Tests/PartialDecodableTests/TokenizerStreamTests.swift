import Testing
@testable import PartialDecodable

class TestTokenHandler: TokenHandler {
    var events: [String] = []

    func handleNull() {
        events.append("null")
    }

    func handleBoolean(_ value: Bool) {
        events.append("boolean:\(value)")
    }

    func handleNumber(_ value: Double) {
        events.append("number:\(value)")
    }

    func handleStringStart() {
        events.append("string:start")
    }

    func handleStringMiddle(_ value: String) {
        events.append("string:middle:\(value)")
    }

    func handleStringEnd() {
        events.append("string:end")
    }

    func handleArrayStart() {
        events.append("array:start")
    }

    func handleArrayEnd() {
        events.append("array:end")
    }

    func handleObjectStart() {
        events.append("object:start")
    }

    func handleObjectEnd() {
        events.append("object:end")
    }
}

@Test func testTokenizeNull() async throws {
    let handler = TestTokenHandler()
    let stream = AsyncStream<String> { continuation in
        continuation.yield("null")
        continuation.finish()
    }

    let tokenizer = Tokenizer(stream, handler: handler)
    try await tokenizer.pump()
    try await tokenizer.pump()

    #expect(handler.events == ["null"])
}

@Test func testTokenizeBoolean() async throws {
    let handler = TestTokenHandler()
    let stream = AsyncStream<String> { continuation in
        continuation.yield("true")
        continuation.finish()
    }

    let tokenizer = Tokenizer(stream, handler: handler)
    try await tokenizer.pump()
    try await tokenizer.pump()

    #expect(handler.events == ["boolean:true"])
}

@Test func testTokenizeNumber() async throws {
    let handler = TestTokenHandler()
    let stream = AsyncStream<String> { continuation in
        continuation.yield("42.5")
        continuation.finish()
    }

    let tokenizer = Tokenizer(stream, handler: handler)
    try await tokenizer.pump()
    try await tokenizer.pump()

    #expect(handler.events == ["number:42.5"])
}

@Test func testTokenizeString() async throws {
    let handler = TestTokenHandler()
    let stream = AsyncStream<String> { continuation in
        continuation.yield(#""hello"#)
        continuation.yield(#" world""#)
        continuation.finish()
    }

    let tokenizer = Tokenizer(stream, handler: handler)
    while !tokenizer.isDone() {
        try await tokenizer.pump()
    }

    #expect(handler.events.contains("string:start"))
    #expect(handler.events.contains("string:middle:hello"))
    #expect(handler.events.contains("string:middle: world"))
    #expect(handler.events.contains("string:end"))
}

@Test func testTokenizeArray() async throws {
    let handler = TestTokenHandler()
    let stream = AsyncStream<String> { continuation in
        continuation.yield("[1, 2]")
        continuation.finish()
    }

    let tokenizer = Tokenizer(stream, handler: handler)
    try await tokenizer.pump()

    #expect(handler.events.contains("array:start"))
    #expect(handler.events.contains("number:1.0"))
    #expect(handler.events.contains("number:2.0"))
    #expect(handler.events.contains("array:end"))
}

@Test func testTokenizeObject() async throws {
    let handler = TestTokenHandler()
    let stream = AsyncStream<String> { continuation in
        continuation.yield(#"{"key": "value"}"#)
        continuation.finish()
    }

    let tokenizer = Tokenizer(stream, handler: handler)
    try await tokenizer.pump()

    #expect(handler.events.contains("object:start"))
    #expect(handler.events.contains("string:start"))
    #expect(handler.events.contains("string:middle:key"))
    #expect(handler.events.contains("string:middle:value"))
    #expect(handler.events.contains("object:end"))
}

@Test func testTokenizeStringEscapes() async throws {
    let handler = TestTokenHandler()
    let stream = AsyncStream<String> { continuation in
        continuation.yield(#""line1\nline2""#)
        continuation.finish()
    }

    let tokenizer = Tokenizer(stream, handler: handler)
    try await tokenizer.pump()

    #expect(handler.events.contains("string:start"))
    #expect(handler.events.contains("string:middle:line1"))
    #expect(handler.events.contains("string:middle:\n"))
    #expect(handler.events.contains("string:middle:line2"))
    #expect(handler.events.contains("string:end"))
}

@Test func testTokenizeChunkedInput() async throws {
    let handler = TestTokenHandler()
    let stream = AsyncStream<String> { continuation in
        continuation.yield("{")
        continuation.yield(#""a""#)
        continuation.yield(":")
        continuation.yield("1")
        continuation.yield("}")
        continuation.finish()
    }

    let tokenizer = Tokenizer(stream, handler: handler)
    while !tokenizer.isDone() {
        try await tokenizer.pump()
    }

    #expect(handler.events.contains("object:start"))
    #expect(handler.events.contains("number:1.0"))
    #expect(handler.events.contains("object:end"))
}
