import Foundation
import UniqueIdentifierGenerator

public extension ScheduleStrategyType {
    func bucketSplitter(uniqueIdentifierGenerator: UniqueIdentifierGenerator) -> BucketSplitter {
        switch self {
        case .individual:
            return IndividualBucketSplitter(uniqueIdentifierGenerator: uniqueIdentifierGenerator)
        case .equallyDivided:
            return EquallyDividedBucketSplitter(uniqueIdentifierGenerator: uniqueIdentifierGenerator)
        case .progressive:
            return ProgressiveBucketSplitter(uniqueIdentifierGenerator: uniqueIdentifierGenerator)
        case .unsplit:
            return UnsplitBucketSplitter(uniqueIdentifierGenerator: uniqueIdentifierGenerator)
        case .equallyFlowDivided:
            return EquallyFlowDividedBucketSplitter(uniqueIdentifierGenerator: uniqueIdentifierGenerator)
        }
    }
}
