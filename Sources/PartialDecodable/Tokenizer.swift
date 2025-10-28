import Foundation

public enum JsonTokenType {
    case null
    case boolean
    case number
    case stringStart
    case stringMiddle
    case stringEnd
    case arrayStart
    case arrayEnd
    case objectStart
    case objectEnd

    var description: String {
        switch self {
        case .null: return "null"
        case .boolean: return "boolean"
        case .number: return "number"
        case .stringStart: return "string start"
        case .stringMiddle: return "string middle"
        case .stringEnd: return "string end"
        case .arrayStart: return "array start"
        case .arrayEnd: return "array end"
        case .objectStart: return "object start"
        case .objectEnd: return "object end"
        }
    }
}

public protocol TokenHandler {
    func handleNull()
    func handleBoolean(_ value: Bool)
    func handleNumber(_ value: Double)
    func handleStringStart()
    func handleStringMiddle(_ value: String)
    func handleStringEnd()
    func handleArrayStart()
    func handleArrayEnd()
    func handleObjectStart()
    func handleObjectEnd()
}

private enum TokenizerState {
    case expectingValue
    case inString
    case startArray
    case afterArrayValue
    case startObject
    case afterObjectKey
    case afterObjectValue
    case beforeObjectKey
}

private struct AnyAsyncIterator: AsyncIteratorProtocol {
    typealias Element = String

    private let _next: () async throws -> String?

    init(_ next: @escaping () async throws -> String?) {
        self._next = next
    }

    mutating func next() async throws -> String? {
        return try await _next()
    }
}

private class Input {
    private var buffer = ""
    private var startIndex: String.Index
    var bufferComplete = false
    var moreContentExpected = true
    private var iterator: AnyAsyncIterator

    init<S: AsyncSequence>(_ stream: S) where S.Element == String {
        var iter = stream.makeAsyncIterator()
        self.iterator = AnyAsyncIterator { try await iter.next() }
        self.startIndex = buffer.startIndex
    }

    var length: Int {
        return buffer.distance(from: startIndex, to: buffer.endIndex)
    }

    func advance(_ len: Int) {
        startIndex = buffer.index(startIndex, offsetBy: len)
    }

    func peek(_ offset: Int) -> Character? {
        guard offset < length else { return nil }
        let index = buffer.index(startIndex, offsetBy: offset)
        return buffer[index]
    }

    func peekCharCode(_ offset: Int) -> UInt16? {
        guard let char = peek(offset) else { return nil }
        return char.unicodeScalars.first?.utf16.first
    }

    func slice(_ start: Int, _ end: Int) -> String {
        let startIdx = buffer.index(startIndex, offsetBy: start)
        let endIdx = buffer.index(startIndex, offsetBy: end)
        return String(buffer[startIdx..<endIdx])
    }

    func commit() {
        if startIndex > buffer.startIndex {
            buffer = String(buffer[startIndex...])
            startIndex = buffer.startIndex
        }
    }

    func remaining() -> String {
        return String(buffer[startIndex...])
    }

    func expectEndOfContent() async throws {
        moreContentExpected = false
        let check = {
            self.commit()
            self.skipPastWhitespace()
            if self.length != 0 {
                throw JSONError.unexpectedTrailingContent(self.remaining())
            }
        }
        try check()
        while try await tryToExpandBuffer() {
            try check()
        }
        try check()
    }

    @discardableResult
    func tryToExpandBuffer() async throws -> Bool {
        if bufferComplete {
            if moreContentExpected {
                throw JSONError.unexpectedEndOfContent
            }
            return false
        }

        guard let next = try await iterator.next() else {
            bufferComplete = true
            if moreContentExpected {
                throw JSONError.unexpectedEndOfContent
            }
            return false
        }

        buffer += next
        return true
    }

    func skipPastWhitespace() {
        var idx = startIndex
        while idx < buffer.endIndex {
            let char = buffer[idx]
            if char == " " || char == "\t" || char == "\n" || char == "\r" {
                idx = buffer.index(after: idx)
            } else {
                break
            }
        }
        startIndex = idx
    }

    func tryToTakePrefix(_ prefix: String) -> Bool {
        if buffer[startIndex...].hasPrefix(prefix) {
            startIndex = buffer.index(startIndex, offsetBy: prefix.count)
            return true
        }
        return false
    }

    func tryToTake(_ len: Int) -> String? {
        guard length >= len else { return nil }
        let endIdx = buffer.index(startIndex, offsetBy: len)
        let result = String(buffer[startIndex..<endIdx])
        startIndex = endIdx
        return result
    }

    func tryToTakeCharCode() -> UInt16? {
        guard length > 0 else { return nil }
        let char = buffer[startIndex]
        startIndex = buffer.index(after: startIndex)
        return char.unicodeScalars.first?.utf16.first
    }

    func takeUntilQuoteOrBackslash() -> (String, Bool) {
        var idx = startIndex
        while idx < buffer.endIndex {
            let char = buffer[idx]
            let code = char.unicodeScalars.first?.value ?? 0

            if code <= 0x1f {
                fatalError("Unescaped control character in string")
            }

            if char == "\"" || char == "\\" {
                let result = String(buffer[startIndex..<idx])
                startIndex = idx
                return (result, true)
            }
            idx = buffer.index(after: idx)
        }

        let result = String(buffer[startIndex...])
        startIndex = buffer.endIndex
        return (result, false)
    }
}

public class Tokenizer {
    private let input: Input
    private let handler: TokenHandler
    private var stack: [TokenizerState] = [.expectingValue]
    private var emittedTokens = 0

    public init<S: AsyncSequence>(_ stream: S, handler: TokenHandler) where S.Element == String {
        self.input = Input(stream)
        self.handler = handler
    }

    public func isDone() -> Bool {
        return stack.isEmpty && input.length == 0
    }

    public func pump() async throws {
        let start = emittedTokens
        while true {
            let before = emittedTokens
            try tokenizeMore()

            if emittedTokens > before {
                continue
            }

            if emittedTokens > start {
                input.commit()
                return
            }

            if stack.isEmpty {
                try await input.expectEndOfContent()
                input.commit()
                return
            }

            let expanded = try await input.tryToExpandBuffer()
            if !expanded {
                continue
            }
        }
    }

    private func tokenizeMore() throws {
        guard let state = stack.last else { return }

        switch state {
        case .expectingValue:
            try tokenizeValue()
        case .inString:
            try tokenizeString()
        case .startArray:
            try tokenizeArrayStart()
        case .afterArrayValue:
            try tokenizeAfterArrayValue()
        case .startObject:
            try tokenizeObjectStart()
        case .afterObjectKey:
            try tokenizeAfterObjectKey()
        case .afterObjectValue:
            try tokenizeAfterObjectValue()
        case .beforeObjectKey:
            try tokenizeBeforeObjectKey()
        }
    }

    private func tokenizeValue() throws {
        input.skipPastWhitespace()

        if input.tryToTakePrefix("null") {
            handler.handleNull()
            emittedTokens += 1
            stack.removeLast()
            return
        }

        if input.tryToTakePrefix("true") {
            handler.handleBoolean(true)
            emittedTokens += 1
            stack.removeLast()
            return
        }

        if input.tryToTakePrefix("false") {
            handler.handleBoolean(false)
            emittedTokens += 1
            stack.removeLast()
            return
        }

        if input.length > 0 {
            if let ch = input.peekCharCode(0), (ch >= 48 && ch <= 57) || ch == 45 {
                var i = 0
                while i < input.length {
                    if let c = input.peekCharCode(i) {
                        if (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46 || c == 101 || c == 69 {
                            i += 1
                        } else {
                            break
                        }
                    }
                }

                if i == input.length && !input.bufferComplete {
                    input.moreContentExpected = false
                    return
                }

                let numberChars = input.slice(0, i)
                input.advance(i)
                let number = try parseJsonNumber(numberChars)
                handler.handleNumber(number)
                emittedTokens += 1
                stack.removeLast()
                input.moreContentExpected = true
                return
            }
        }

        if input.tryToTakePrefix("\"") {
            stack.removeLast()
            stack.append(.inString)
            handler.handleStringStart()
            emittedTokens += 1
            try tokenizeString()
            return
        }

        if input.tryToTakePrefix("[") {
            stack.removeLast()
            stack.append(.startArray)
            handler.handleArrayStart()
            emittedTokens += 1
            try tokenizeArrayStart()
            return
        }

        if input.tryToTakePrefix("{") {
            stack.removeLast()
            stack.append(.startObject)
            handler.handleObjectStart()
            emittedTokens += 1
            try tokenizeObjectStart()
            return
        }
    }

    private func tokenizeString() throws {
        while true {
            let (chunk, interrupted) = input.takeUntilQuoteOrBackslash()

            if !chunk.isEmpty {
                handler.handleStringMiddle(chunk)
                emittedTokens += 1
            } else if !interrupted {
                return
            }

            if interrupted {
                if input.length == 0 {
                    return
                }

                guard let nextChar = input.peek(0) else { return }

                if nextChar == "\"" {
                    input.advance(1)
                    handler.handleStringEnd()
                    emittedTokens += 1
                    stack.removeLast()
                    return
                }

                guard let nextChar2 = input.peek(1) else { return }

                let value: String
                switch nextChar2 {
                case "u":
                    if input.length < 6 {
                        return
                    }

                    var code: UInt32 = 0
                    for j in 2..<6 {
                        guard let c = input.peekCharCode(j) else {
                            throw JSONError.badUnicodeEscape
                        }

                        let digit: UInt32
                        if c >= 48 && c <= 57 {
                            digit = UInt32(c - 48)
                        } else if c >= 65 && c <= 70 {
                            digit = UInt32(c - 55)
                        } else if c >= 97 && c <= 102 {
                            digit = UInt32(c - 87)
                        } else {
                            throw JSONError.badUnicodeEscape
                        }
                        code = (code << 4) | digit
                    }

                    input.advance(6)
                    if let scalar = UnicodeScalar(code) {
                        handler.handleStringMiddle(String(scalar))
                    }
                    emittedTokens += 1
                    continue

                case "n": value = "\n"
                case "r": value = "\r"
                case "t": value = "\t"
                case "b": value = "\u{08}"
                case "f": value = "\u{0C}"
                case "\\": value = "\\"
                case "/": value = "/"
                case "\"": value = "\""
                default:
                    throw JSONError.badEscape
                }

                input.advance(2)
                handler.handleStringMiddle(value)
                emittedTokens += 1
            }
        }
    }

    private func tokenizeArrayStart() throws {
        input.skipPastWhitespace()

        if input.length == 0 {
            return
        }

        if input.tryToTakePrefix("]") {
            handler.handleArrayEnd()
            emittedTokens += 1
            stack.removeLast()
            return
        } else {
            stack.removeLast()
            stack.append(.afterArrayValue)
            stack.append(.expectingValue)
            try tokenizeValue()
        }
    }

    private func tokenizeAfterArrayValue() throws {
        input.skipPastWhitespace()

        guard let nextChar = input.tryToTakeCharCode() else { return }

        switch nextChar {
        case 0x5d:
            handler.handleArrayEnd()
            emittedTokens += 1
            stack.removeLast()
            return

        case 0x2c:
            stack.append(.expectingValue)
            try tokenizeValue()
            return

        default:
            throw JSONError.expectedCommaOrBracket(String(UnicodeScalar(UInt32(nextChar))!))
        }
    }

    private func tokenizeObjectStart() throws {
        input.skipPastWhitespace()

        guard let nextChar = input.tryToTakeCharCode() else { return }

        switch nextChar {
        case 0x7d:
            handler.handleObjectEnd()
            emittedTokens += 1
            stack.removeLast()
            return

        case 0x22:
            stack.removeLast()
            stack.append(.afterObjectKey)
            stack.append(.inString)
            handler.handleStringStart()
            emittedTokens += 1
            try tokenizeString()
            return

        default:
            throw JSONError.expectedObjectKey(String(UnicodeScalar(UInt32(nextChar))!))
        }
    }

    private func tokenizeAfterObjectKey() throws {
        input.skipPastWhitespace()

        guard let nextChar = input.tryToTakeCharCode() else { return }

        if nextChar == 0x3a {
            stack.removeLast()
            stack.append(.afterObjectValue)
            stack.append(.expectingValue)
            try tokenizeValue()
            return
        }

        throw JSONError.expectedColon(String(UnicodeScalar(UInt32(nextChar))!))
    }

    private func tokenizeAfterObjectValue() throws {
        input.skipPastWhitespace()

        guard let nextChar = input.tryToTakeCharCode() else { return }

        switch nextChar {
        case 0x7d:
            handler.handleObjectEnd()
            emittedTokens += 1
            stack.removeLast()
            return

        case 0x2c:
            stack.removeLast()
            stack.append(.beforeObjectKey)
            try tokenizeBeforeObjectKey()
            return

        default:
            throw JSONError.expectedCommaOrBrace(String(UnicodeScalar(UInt32(nextChar))!))
        }
    }

    private func tokenizeBeforeObjectKey() throws {
        input.skipPastWhitespace()

        guard let nextChar = input.tryToTakeCharCode() else { return }

        if nextChar == 0x22 {
            stack.removeLast()
            stack.append(.afterObjectKey)
            stack.append(.inString)
            handler.handleStringStart()
            emittedTokens += 1
            try tokenizeString()
            return
        }

        throw JSONError.expectedObjectKey(String(UnicodeScalar(UInt32(nextChar))!))
    }
}

private let jsonNumberPattern = #"^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$"#

private func parseJsonNumber(_ str: String) throws -> Double {
    guard str.range(of: jsonNumberPattern, options: .regularExpression) != nil else {
        throw JSONError.invalidNumber(str)
    }
    guard let number = Double(str) else {
        throw JSONError.invalidNumber(str)
    }
    return number
}

public enum JSONError: Error, CustomStringConvertible {
    case unexpectedTrailingContent(String)
    case unexpectedEndOfContent
    case badUnicodeEscape
    case badEscape
    case invalidNumber(String)
    case expectedCommaOrBracket(String)
    case expectedObjectKey(String)
    case expectedColon(String)
    case expectedCommaOrBrace(String)
    case internalError(String)

    public var description: String {
        switch self {
        case .unexpectedTrailingContent(let content):
            return "Unexpected trailing content \(content)"
        case .unexpectedEndOfContent:
            return "Unexpected end of content"
        case .badUnicodeEscape:
            return "Bad Unicode escape in JSON"
        case .badEscape:
            return "Bad escape in string"
        case .invalidNumber(let str):
            return "Invalid number: \(str)"
        case .expectedCommaOrBracket(let char):
            return "Expected , or ], got \(char)"
        case .expectedObjectKey(let char):
            return "Expected start of object key, got \(char)"
        case .expectedColon(let char):
            return "Expected colon after object key, got \(char)"
        case .expectedCommaOrBrace(let char):
            return "Expected , or } after object value, got \(char)"
        case .internalError(let message):
            return "Internal error: \(message)"
        }
    }
}
