import Foundation
import SimulatorPoolModels

/// A result of a single test run.
public struct TestRunResult: Codable, CustomStringConvertible, Equatable {
    public let succeeded: Bool
    public let exceptions: [TestException]
    public let logs: [TestLogEntry]
    public let duration: TimeInterval
    public let startTime: TimeInterval
    public let hostName: String
    public let simulatorId: UDID

    public var finishTime: TimeInterval {
        return startTime + duration
    }

    public init(
        succeeded: Bool,
        exceptions: [TestException],
        logs: [TestLogEntry],
        duration: TimeInterval,
        startTime: TimeInterval,
        hostName: String,
        simulatorId: UDID
    ) {
        self.succeeded = succeeded
        self.exceptions = exceptions
        self.logs = logs
        self.duration = duration
        self.startTime = startTime
        self.hostName = hostName
        self.simulatorId = simulatorId
    }
    
    public var description: String {
        var result: [String] = ["\(type(of: self)) \(succeeded ? "succeeded" : "failed")"]
        result += ["duration \(duration) sec"]
        result += ["hostName \(hostName)"]
        result += ["\(simulatorId)"]
        if !exceptions.isEmpty {
            result += ["exceptions: \(exceptions)"]
        }
        if !logs.isEmpty {
            result += ["\(logs.count) log entries"]
        }
        return "<\(result.joined(separator: ", "))>"
    }
}
