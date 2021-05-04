//
//  EquallyFlowDividedBucketSplitter.swift
//  
//
//  Created by a.belyaev3 on 29.04.2021.
//

import Foundation
import QueueModels
import UniqueIdentifierGenerator

public final class EquallyFlowDividedBucketSplitter: BucketSplitter {
    public init(uniqueIdentifierGenerator: UniqueIdentifierGenerator) {
        super.init(
            description: "Equally flow divided strategy",
            uniqueIdentifierGenerator: uniqueIdentifierGenerator
        )
    }
    
    public override func split(inputs: [TestEntryConfiguration], bucketSplitInfo: BucketSplitInfo) -> [[TestEntryConfiguration]] {
        let size = UInt(ceil(Double(inputs.count) / (Double(bucketSplitInfo.flowNumber) * 2)))
        return inputs.splitToChunks(withSize: size)
    }
}
