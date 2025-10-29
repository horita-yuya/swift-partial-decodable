import Testing
import Foundation
@testable import PartialDecodable

@Test func testSimpleObject() async throws {
    struct Simple: Decodable {
        var key: String?
    }

    let chunks = AsyncStream<String> { continuation in
        continuation.yield(#"{"key":"#)
        continuation.yield(#" "val"#)
        continuation.yield(#"ue""#)
        continuation.yield(#"}"#)
        continuation.finish()
    }
    
    let expects = [
        nil,
        #"val"#,
        #"value"#,
        #"value"#,
    ]
    
    var actuals: [String?] = []
    for try await decoded in incrementalDecode(Simple.self, from: chunks) {
        actuals.append(decoded.key)
    }

    #expect(actuals == expects)
}

@Test func testSimpleArray() async throws {
    let chunks = AsyncStream<String> { continuation in
        continuation.yield(#"[1, "#)
        continuation.yield(#"2, "#)
        continuation.yield(#"3]"#)
        continuation.finish()
    }

    let expects: [[Int]] = [
        [1],
        [1, 2],
        [1, 2, 3],
        [1, 2, 3]
    ]

    var actuals: [[Int]] = []
    for try await decoded in incrementalDecode([Int].self, from: chunks) {
        actuals.append(decoded)
    }

    #expect(actuals == expects)
}

@Test func testNestedObject() async throws {
    struct NestedValue: Decodable, Equatable {
        var value: Int?
    }

    struct Nested: Decodable, Equatable {
        var name: String?
        var nested: NestedValue?
    }

    let chunks = AsyncStream<String> { continuation in
        continuation.yield(#"{"name":"#)
        continuation.yield(#" "test","#)
        continuation.yield(#" "nested": {"value": 42}}"#)
        continuation.finish()
    }

    let expects: [Nested?] = [
        Nested(name: nil, nested: nil),
        Nested(name: #"test"#, nested: nil),
        Nested(name: #"test"#, nested: NestedValue(value: 42)),
        Nested(name: #"test"#, nested: NestedValue(value: 42))
    ]

    var actuals: [Nested] = []
    for try await decoded in incrementalDecode(Nested.self, from: chunks) {
        actuals.append(decoded)
    }

    #expect(actuals == expects.compactMap { $0 })
}

@Test func testPrimitives() async throws {
    let intChunks = AsyncStream<String> { continuation in
        continuation.yield(#"123"#)
        continuation.finish()
    }

    var lastInt: Int?
    for try await decoded in incrementalDecode(Int.self, from: intChunks) {
        lastInt = decoded
    }
    #expect(lastInt == 123)

    let doubleChunks = AsyncStream<String> { continuation in
        continuation.yield(#"-45.67"#)
        continuation.finish()
    }

    var lastDouble: Double?
    for try await decoded in incrementalDecode(Double.self, from: doubleChunks) {
        lastDouble = decoded
    }
    #expect(lastDouble == -45.67)

    let boolChunks = AsyncStream<String> { continuation in
        continuation.yield(#"true"#)
        continuation.finish()
    }

    var lastBool: Bool?
    for try await decoded in incrementalDecode(Bool.self, from: boolChunks) {
        lastBool = decoded
    }
    #expect(lastBool == true)

    let stringChunks = AsyncStream<String> { continuation in
        continuation.yield(#""hello""#)
        continuation.finish()
    }

    var lastString: String?
    for try await decoded in incrementalDecode(String.self, from: stringChunks) {
        lastString = decoded
    }
    #expect(lastString == #"hello"#)
}

@Test func testStringEscapes() async throws {
    struct Escaped: Decodable, Equatable {
        var escaped: String?
    }

    let chunks = AsyncStream<String> { continuation in
        continuation.yield(#"{"escaped": "line1\nline2\ttab\"quote"}"#)
        continuation.finish()
    }

    let expects: [Escaped?] = [
        Escaped(escaped: #"line1"# + "\n" + #"line2"# + "\t" + #"tab"quote"#),
        Escaped(escaped: #"line1"# + "\n" + #"line2"# + "\t" + #"tab"quote"#)
    ]

    var actuals: [Escaped] = []
    for try await decoded in incrementalDecode(Escaped.self, from: chunks) {
        actuals.append(decoded)
    }

    #expect(actuals == expects.compactMap { $0 })
}

@Test func testNestedStructWithArrays() async throws {
    struct Content: Decodable, Equatable {
        var text: String?
        var metadata: String?
    }

    struct Item: Decodable, Equatable {
        var data: Content?
        var description: String?
    }

    struct Container: Decodable, Equatable {
        var mainContent: Content?
        var items: [Item]?
    }

    let chunks = AsyncStream<String> { continuation in
        continuation.yield(#"{"mainContent": {"text": "Hi — are"#)
        continuation.yield(#" you there?"}}"#)
        continuation.finish()
    }

    var actuals: [Container] = []
    for try await decoded in incrementalDecode(Container.self, from: chunks) {
        actuals.append(decoded)
    }

    #expect(actuals.count > 0)
    if let last = actuals.last {
        #expect(last.mainContent?.text == "Hi — are you there?")
    }
}

@Test func testSingleCharacterChunks() async throws {
    struct Simple: Decodable, Equatable {
        var key: String?
    }

    let json = #"{"key":"value"}"#
    let chunks = AsyncStream<String> { continuation in
        for char in json {
            continuation.yield(String(char))
        }
        continuation.finish()
    }

    var actuals: [Simple] = []
    for try await decoded in incrementalDecode(Simple.self, from: chunks) {
        actuals.append(decoded)
    }

    #expect(actuals.count > 0)
    if let last = actuals.last {
        #expect(last.key == "value")
    }
}

@Test func testCharByCharObjectWithNestedObject() async throws {
    struct Content: Decodable, Equatable {
        var text: String?
    }

    struct Container: Decodable, Equatable {
        var content: Content?
    }

    let json = #"{"content":{"text":"Hi"}}"#
    let chunks = AsyncStream<String> { continuation in
        for char in json {
            continuation.yield(String(char))
        }
        continuation.finish()
    }

    var actuals: [Container] = []
    for try await decoded in incrementalDecode(Container.self, from: chunks) {
        actuals.append(decoded)
    }

    #expect(actuals.count > 0)
    if let last = actuals.last {
        #expect(last.content?.text == "Hi")
    }
}

@Test func testChunkedNestedObject() async throws {
    struct Inner: Decodable, Equatable {
        var value: String?
    }

    struct Outer: Decodable, Equatable {
        var inner: Inner?
    }

    let chunks = AsyncStream<String> { continuation in
        continuation.yield("{\"inner\":")
        continuation.yield(#"{"value":"test"}}"#)
        continuation.finish()
    }

    var actuals: [Outer] = []
    for try await decoded in incrementalDecode(Outer.self, from: chunks) {
        actuals.append(decoded)
    }

    #expect(actuals.count > 0)
    if let last = actuals.last {
        #expect(last.inner?.value == "test")
    }
}

@Test func singleCharacterIncremental() async throws {
    struct Content: Decodable, Equatable {
        var text: String?
    }

    struct Response: Decodable, Equatable {
        var content: Content?
    }

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
