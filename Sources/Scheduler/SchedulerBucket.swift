import BuildArtifacts
import DeveloperDirModels
import Foundation
import PluginSupport
import QueueModels
import SimulatorPoolModels
import RunnerModels

public struct SchedulerBucket: CustomStringConvertible {
    public let bucketId: BucketId
    public let bucketPayload: BucketPayload
    
    public var description: String {
        var result = [String]()
        
        result.append("\(bucketId)")
        result.append("bucketPayload: \(bucketPayload)")
        
        return "<\((type(of: self))) " + result.joined(separator: " ") + ">"
    }

    public init(
        bucketId: BucketId,
        bucketPayload: BucketPayload
    ) {
        self.bucketId = bucketId
        self.bucketPayload = bucketPayload
    }
    
    public static func from(bucket: Bucket) -> SchedulerBucket {
        return SchedulerBucket(
            bucketId: bucket.bucketId,
            bucketPayload: bucket.bucketPayload
        )
    }
}
