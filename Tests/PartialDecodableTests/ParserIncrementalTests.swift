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
        "val",
        "value",
        "value",
    ]
    
    var actuals: [String?] = []
    for try await value in parse(chunks) {
        let data = try value.toJSONData()
        let decoded = try? JSONDecoder().decode(Simple.self, from: data)
        actuals.append(decoded?.key)
    }
    
    #expect(actuals == expects)
}

@Test func testSimpleArray() async throws {
    let chunks = AsyncStream<String> { continuation in
        continuation.yield("[1, ")
        continuation.yield("2, ")
        continuation.yield("3]")
        continuation.finish()
    }

    let expects: [[Int]] = [
        [1],
        [1, 2],
        [1, 2, 3],
        [1, 2, 3]
    ]

    var actuals: [[Int]] = []
    for try await value in parse(chunks) {
        let data = try value.toJSONData()
        let decoded = try? JSONDecoder().decode([Int].self, from: data)
        actuals.append(decoded ?? [])
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
        Nested(name: "test", nested: nil),
        Nested(name: "test", nested: NestedValue(value: 42)),
        Nested(name: "test", nested: NestedValue(value: 42))
    ]

    var actuals: [Nested?] = []
    for try await value in parse(chunks) {
        let data = try value.toJSONData()
        let decoded = try? JSONDecoder().decode(Nested.self, from: data)
        actuals.append(decoded)
    }

    #expect(actuals == expects)
}

@Test func testPrimitives() async throws {
    let testCases: [(String, JsonValue)] = [
        ("null", .null),
        ("true", .boolean(true)),
        ("false", .boolean(false)),
        ("123", .number(123)),
        ("-45.67", .number(-45.67)),
        (#""hello""#, .string("hello"))
    ]

    for (input, expected) in testCases {
        let chunks = AsyncStream<String> { continuation in
            continuation.yield(input)
            continuation.finish()
        }

        var lastValue: JsonValue?
        for try await value in parse(chunks) {
            lastValue = value
        }

        #expect(lastValue == expected, "Failed for input: \(input)")
    }
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
        Escaped(escaped: "line1\nline2\ttab\"quote"),
        Escaped(escaped: "line1\nline2\ttab\"quote")
    ]

    var actuals: [Escaped?] = []
    for try await value in parse(chunks) {
        let data = try value.toJSONData()
        let decoded = try? JSONDecoder().decode(Escaped.self, from: data)
        actuals.append(decoded)
    }

    #expect(actuals == expects)
}
