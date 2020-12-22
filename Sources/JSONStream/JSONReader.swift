import Foundation

/**
 * JSON reader that utilizes JSONStream to parse the JSON stream on the fly.
 */
public final class JSONReader {
    let inputStream: JSONStream
    let eventStream: JSONReaderEventStream
    var context = [ParsingContext.root]
    
    let anyCharacterSet = CharacterSet([]).inverted
    let numberChars = CharacterSet(charactersIn: "-1234567890")
    let whiteCharacters = CharacterSet.whitespacesAndNewlines
    public private(set) var collectedBytes = [UInt8]()
    
    enum `Error`: Swift.Error {
        case unexpectedCharacter(UInt8)
        case unexpectedCharacters([UInt8], expected: [UInt8])
        case streamHasNoData
        case streamEndedAtRootContext
        case unexpectedEndOfStream
        case invalidData
        case invalidNumberValue(Data)
        case arrayCannotHaveKeys(parent: ParsingContext, child: ParsingContext)
        case objectMustHaveKey(parent: ParsingContext, child: ParsingContext)
        case unhandledContextCombination(parent: ParsingContext, child: ParsingContext)
    }
    
    public init(inputStream: JSONStream, eventStream: JSONReaderEventStream) {
        self.inputStream = inputStream
        self.eventStream = eventStream
    }
    
    public func start() throws {
        try readAndThrowErrorOnFailure()
    }
    
    private func readAndThrowErrorOnFailure() throws {
        do {
            try readRecursively()
        } catch {
            if let readerError = error as? Error, case Error.streamEndedAtRootContext = readerError {
                return
            } else {
                throw error
            }
        }
    }
    
    private func readRecursively() throws {
        while true {
            switch currentContext {
            case .root:
                try validateRootContext()
            case .inObject(let key, let storage):
                try validateObjectContext(key, storage)
            case .inArray(let key, let storage):
                try validateArrayContext(key, storage)
            case .inKey(let keyStorage):
                try validateKeyContext(keyStorage as Data)
            case .inValue(let key):
                try validateValueForKeyContext(key)
            case .inStringValue(_, let mutableData):
                try validateStringContext(mutableData)
            case .inStringObject(let storage):
                try validateStringContext(storage)
            case .inNullValue(_):
                try validateNullContext()
            case .inTrueValue(_):
                try validateTrueContext()
            case .inFalseValue(_):
                try validateFalseContext()
            case .inNumericValue(let key, let storage):
                try validateNumericContext(key, storage)
            }
        }
    }
    
    private func validateRootContext() throws {
        let readResult = read(untilAnyCharacterFrom: anyCharacterSet, ignoreCharacters: whiteCharacters)
        guard let byte = readResult.matchingByte else { throw Error.streamEndedAtRootContext }
        
        switch byte {
        case 0x5b: // "["
            pushContext(.inArray(key: nil, storage: NSMutableArray()))
        case 0x7b: // "{"
            pushContext(.inObject(key: nil, storage: NSMutableDictionary()))
        default:
            throw Error.unexpectedCharacter(byte)
        }
    }
    
    private func validateObjectContext(
        _ key: String?,
        _ storage: NSMutableDictionary,
        expectingAnotherKeyValue: Bool = false) throws {
        // {  "key": "value"}, {"key": []}, {"key": {}  }
        //  ^
        let readResult = read(untilAnyCharacterFrom: anyCharacterSet, ignoreCharacters: whiteCharacters)
        guard let byte = readResult.matchingByte else { throw Error.streamHasNoData }
        
        switch byte {
        case 0x7d: // "}"
            if !expectingAnotherKeyValue {
                try popContext()
            } else {
                throw Error.unexpectedCharacter(byte)
            }
        case 0x22: // "\""
            pushContext(.inKey(NSMutableData()))
        case 0x2c: // ","
            if storage.count == 0 || expectingAnotherKeyValue {
                throw Error.unexpectedCharacter(byte)
            } 
            try validateObjectContext(key, storage, expectingAnotherKeyValue: true)
        default:
            throw Error.unexpectedCharacter(byte)
        }
    }
    
    private func validateKeyContext(_ keyStorage: Data) throws {
        // "key" :
        //  ^ we're here
        var readResult = read(untilAnyCharacterFrom: CharacterSet(["\""]))
        guard readResult.matchingByte == 0x22 /* "\""  */ else { throw Error.streamHasNoData }
        
        var keyData = Data()
        keyData.append(contentsOf: readResult.passedBytes)
        
        // "key" :
        //      ^ we're here
        readResult = read(untilAnyCharacterFrom: CharacterSet([":"]), ignoreCharacters: whiteCharacters)
        guard readResult.passedBytes.isEmpty else { throw Error.unexpectedCharacter(readResult.passedBytes[0]) }
        guard let byte = readResult.matchingByte else { throw Error.streamHasNoData }
        guard byte == 0x3a /* ":" */ else { throw Error.unexpectedCharacter(byte) }
        
        guard let key = String(data: keyData, encoding: .utf8) else {
            throw Error.invalidData // TODO - make this invalidStringData
        }
        
        try popContext()
        pushContext(.inValue(key: key))
    }
    
    private func validateValueForKeyContext(_ key: String) throws {
        // "key":  _____
        //       ^ we're here
        let readResult = read(untilAnyCharacterFrom: anyCharacterSet, ignoreCharacters: whiteCharacters)
        guard let byte = readResult.matchingByte else { throw Error.streamHasNoData }
        
        try popContext()
        
        switch byte {
        case 0x5b: // "["
            pushContext(.inArray(key: key, storage: NSMutableArray()))
        case 0x7b: // "{"
            pushContext(.inObject(key: key, storage: NSMutableDictionary()))
        case 0x22: // "\""
            pushContext(.inStringValue(key: key, storage: NSMutableData()))
        case 0x6e: // "n"
            pushContext(.inNullValue(key: key))
        case 0x74: // "t"
            pushContext(.inTrueValue(key: key))
        case 0x66: // "f"
            pushContext(.inFalseValue(key: key))
        case 0x30 ... 0x39, 0x2d: // "0123456789", "-"
            pushContext(.inNumericValue(key: key, storage: NumericStorage(Data([byte]))))
        default:
            throw Error.unexpectedCharacter(byte)
        }
    }
    
    private func validateStringContext(_ storage: NSMutableData) throws {
        // "some string"
        //  ^ we're here
        var data = Data()
        var expectedEscapedValue = false
        while true {
            guard let byte = readByte() else { throw Error.streamHasNoData }
            
            if byte == 0x5c /* "\\" */ && !expectedEscapedValue {
                expectedEscapedValue = true
            } else if expectedEscapedValue {
                expectedEscapedValue = false
            } else if !expectedEscapedValue && byte == 0x22 /* "\"" */ {
                break
            }
            data.append(byte)
        }
        storage.setData(data)
        
        try popContext()
    }
    
    private func validateArrayContext(
        _ key: String?,
        _ storage: NSMutableArray,
        expectingAnotherObject: Bool = false) throws
    {
        // [   "object", {}, [], -12.4e4 ]
        //   ^ we're here
        var expectedChars = CharacterSet(["]", "\"", "{", "[", ",", "n", "f", "t"])
        expectedChars.formUnion(numberChars)
        
        let readResult = read(untilAnyCharacterFrom: expectedChars, ignoreCharacters: whiteCharacters)
        guard readResult.passedBytes.isEmpty else { throw Error.unexpectedCharacter(readResult.passedBytes[0]) }
        guard let byte = readResult.matchingByte else { throw Error.streamHasNoData }
        
        switch byte {
        case 0x5D: // "]"
            if !expectingAnotherObject {
                try popContext()
            } else {
                throw Error.unexpectedCharacter(byte)
            }
        case 0x22: //"\""
            pushContext(.inStringObject(storage: NSMutableData()))
        case 0x7B: // "{"
            pushContext(.inObject(key: nil, storage: NSMutableDictionary()))
        case 0x5B: // "["
            pushContext(.inArray(key: nil, storage: NSMutableArray()))
        case 0x2C: // ","
            if storage.count == 0 || expectingAnotherObject {
                throw Error.unexpectedCharacter(byte)
            }
            try validateArrayContext(key, storage, expectingAnotherObject: true)
        case 0x6E: // "n"
            pushContext(.inNullValue(key: nil))
        case 0x74: // "t"
            pushContext(.inTrueValue(key: nil))
        case 0x66: // "f"
            pushContext(.inFalseValue(key: nil))
        case 0x30 ... 0x39, 0x2D: // "0123456789", "-"
            pushContext(.inNumericValue(key: nil, storage: NumericStorage(Data([byte]))))
        default:
            throw Error.unexpectedCharacter(byte)
        }
    }
    
    private func validateNullContext() throws {
        // null
        //  ^
        try readAndValidateBytes([0x75, 0x6C, 0x6C])
        try popContext()
    }
    
    private func validateTrueContext() throws {
        // true
        //  ^
        try readAndValidateBytes([0x72, 0x75, 0x65])
        try popContext()
    }
    
    private func validateFalseContext() throws {
        // false
        //  ^
        try readAndValidateBytes([0x61, 0x6C, 0x73, 0x65])
        try popContext()
    }
    
    private func validateNumericContext(_ key: String?, _ storage: NumericStorage) throws {
        // first symbol ('-' or digit) is part of storage already, so we read the rest
        // 1234.56e-21
        //  ^
        let endOfContainerContextScalar: Unicode.Scalar
        if key == nil {
            // nil key means this number is part of array
            endOfContainerContextScalar = "]"
        } else {
            // non-nil key means this number is part of object key->number
            endOfContainerContextScalar = "}"
        }
        let readBreakers = Set<Unicode.Scalar>([",", endOfContainerContextScalar])
        
        while true {
            guard let nextByte = inputStream.touch() else { throw Error.streamHasNoData }
            let nextScalar = Unicode.Scalar(nextByte)
            if readBreakers.contains(nextScalar) || whiteCharacters.contains(nextScalar) { break }
            
            guard let byte = readByte() else { throw Error.streamHasNoData }
            storage.bytes.append(byte)
        }
        
        guard let stringRepresentation = String(data: Data(storage.bytes), encoding: .utf8) else {
            throw Error.invalidNumberValue(storage.bytes)
        }
        storage.parsedNumber = try NumberValidator.validateStringRepresentationOfNumber(stringRepresentation)
        
        try popContext()
    }
    
    private func read(times: Int) throws -> [UInt8] {
        var result = [UInt8]()
        for _ in 0 ..< times {
            guard let byte = readByte() else { throw Error.streamHasNoData }
            result.append(byte)
        }
        return result
    }
    
    private func readAndValidateBytes(_ expectedBytes: [UInt8]) throws {
        let actualBytes = try read(times: expectedBytes.count)
        guard actualBytes == expectedBytes else {
            throw Error.unexpectedCharacters(actualBytes, expected: expectedBytes)
        }
    }
    
    private func readByte() -> UInt8? {
        guard let scalar = inputStream.read() else { return nil }
        collectedBytes.append(scalar)
        return scalar
    }
    
    /*
     * Reads the input stream up until any scalar from the given set of characters is met.
     * Returns tuple of all scalars that were read from the stream, excluding any characters from ignoreCharacters set,
     * and the scalar that interrupted the read operation.
     * If stream ends, matching scalar will be nil.
     */
    private func read(
        untilAnyCharacterFrom characterSet: CharacterSet,
        ignoreCharacters: CharacterSet? = nil)
        -> (passedBytes: [UInt8], matchingByte: UInt8?)
    {
        var passedBytes = [UInt8]()
        while true {
            guard let inputByte = readByte() else { break }
            let inputScalar = Unicode.Scalar(inputByte)
            if ignoreCharacters?.contains(inputScalar) == true { continue }
            
            if characterSet.contains(inputScalar) {
                return (passedBytes: passedBytes, matchingByte: inputByte)
            } else {
                passedBytes.append(inputByte)
            }
        }
        return (passedBytes: passedBytes, matchingByte: nil)
    }
    
    // MARK: - Context
    
    private func pushContext(_ context: ParsingContext) {
        self.context.append(context)
    }
    
    private var currentContext: ParsingContext {
        return self.context.last!
    }
    
    private func popContext() throws {
        let popedContext = self.context.removeLast()
        
        switch (popedContext, currentContext) {
            
            /**
             * When parent context is object
             */
        case (.inKey(_), .inObject(_, _)):
            break
        case (.inValue(_), .inObject(_, _)):
            break
        case (.inStringValue(let key, let data), .inObject(_, let object)):
            // case: {"key": "stringValue"}
            guard let key = key else { throw Error.objectMustHaveKey(parent: currentContext, child: popedContext) }
            guard let stringValue = String(data: data as Data, encoding: .utf8) else { throw Error.invalidData }
            object[key] = stringValue
        case (.inObject(let key, let objectValue), .inObject(_, let object)):
            // case: {"key": {...}}
            guard let key = key else { throw Error.objectMustHaveKey(parent: currentContext, child: popedContext) }
            object[key] = objectValue
        case (.inArray(let key, let array), .inObject(_, let object)):
            // case: {"key": []]}
            guard let key = key else { throw Error.objectMustHaveKey(parent: currentContext, child: popedContext) }
            object[key] = array
        case (.inNullValue(let key), .inObject(_, let object)):
            // case: {"key": null}
            guard let key = key else { throw Error.objectMustHaveKey(parent: currentContext, child: popedContext) }
            object[key] = NSNull()
        case (.inTrueValue(let key), .inObject(_, let object)):
            // case: {"key": true}
            guard let key = key else { throw Error.objectMustHaveKey(parent: currentContext, child: popedContext) }
            object[key] = true
        case (.inFalseValue(let key), .inObject(_, let object)):
            // case: {"key": false}
            guard let key = key else { throw Error.objectMustHaveKey(parent: currentContext, child: popedContext) }
            object[key] = false
        case (.inNumericValue(let key, let storage), .inObject(_, let object)):
            // case: {"key": -123.45e-3}
            guard let key = key else { throw Error.objectMustHaveKey(parent: currentContext, child: popedContext) }
            guard let parsedNumber = storage.parsedNumber else { throw Error.invalidNumberValue(storage.bytes) }
            object[key] = parsedNumber
            
            /**
             * When parent context is array
             */
        case (.inStringObject(let data), .inArray(_, let array)):
            guard let stringValue = String(data: data as Data, encoding: .utf8) else { throw Error.invalidData }
            // case: ["string"]
            array.add(stringValue)
        case (.inObject(let key, let object), .inArray(_, let array)):
            // case: [{}]
            // arrays do not have keys so key must be nil
            guard key == nil else { throw Error.arrayCannotHaveKeys(parent: currentContext, child: popedContext) }
            array.add(object)
        case (.inArray(let key, let subarray), .inArray(_, let array)):
            // case: [[]]
            // arrays do not have keys so key must be nil
            guard key == nil else { throw Error.arrayCannotHaveKeys(parent: currentContext, child: popedContext) }
            array.add(subarray)
        case (.inNullValue(let key), .inArray(_, let array)):
            // case: [null]
            // arrays do not have keys so key must be nil
            guard key == nil else { throw Error.arrayCannotHaveKeys(parent: currentContext, child: popedContext) }
            array.add(NSNull())
        case (.inTrueValue(let key), .inArray(_, let array)):
            // case: [true]
            // arrays do not have keys so key must be nil
            guard key == nil else { throw Error.arrayCannotHaveKeys(parent: currentContext, child: popedContext) }
            array.add(true)
        case (.inFalseValue(let key), .inArray(_, let array)):
            // case: [false]
            // arrays do not have keys so key must be nil
            guard key == nil else { throw Error.arrayCannotHaveKeys(parent: currentContext, child: popedContext) }
            array.add(false)
        case (.inNumericValue(let key, let storage), .inArray(_, let array)):
            // case: [-123.45e-3]
            // arrays do not have keys so key must be nil
            guard key == nil, let parsedNumber = storage.parsedNumber else { throw Error.invalidNumberValue(storage.bytes) }
            array.add(parsedNumber)
            
            /**
             * When parent context is root, we expect specific child contexts
             */
        case (.inObject(_, let object), .root):
            eventStream.newObject(NSDictionary(dictionary: object), bytes: collectedBytes)
            collectedBytes.removeAll()
        case (.inArray(_, let array), .root):
            eventStream.newArray(NSArray(array: array), bytes: collectedBytes)
            collectedBytes.removeAll()
        default:
            throw Error.unhandledContextCombination(parent: currentContext, child: popedContext)
        }
    }
}
