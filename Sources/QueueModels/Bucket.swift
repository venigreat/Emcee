import BuildArtifacts
import DI
import DeveloperDirModels
import Foundation
import PluginSupport
import RunnerModels
import SimulatorPoolModels
import WorkerCapabilitiesModels

public struct Bucket: Codable, Hashable, CustomStringConvertible {
    public let bucketId: BucketId
    public let bucketPayload: BucketPayload
    public let workerCapabilityRequirements: Set<WorkerCapabilityRequirement>

    public init(
        bucketId: BucketId,
        bucketPayload: BucketPayload,
        workerCapabilityRequirements: Set<WorkerCapabilityRequirement>
    ) {
        self.bucketId = bucketId
        self.bucketPayload = bucketPayload
        self.workerCapabilityRequirements = workerCapabilityRequirements
    }
    
    public var description: String {
        return "<\((type(of: self))) \(bucketId) \(bucketPayload) \(workerCapabilityRequirements)"
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(bucketId)
    }
    
    public static func == (left: Bucket, right: Bucket) -> Bool {
        left.bucketId == right.bucketId
    }
    
    public class SS: BucketPayload {
        public class VV: BucketProcessor{
            public func execute(completion: @escaping (Result<BucketResult, Error>) -> ()) {
                
            }
        }
        
        public func createBucketProcessor(di: DI) throws -> BucketProcessor { VV() }
    }
    
    public init(from decoder: Decoder) throws {
        bucketId = ""
        bucketPayload = SS()
        workerCapabilityRequirements = []
        // TODO
    }
    
    public func encode(to encoder: Encoder) throws {
        // TODO
    }
}
