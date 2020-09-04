import DI

public protocol BucketPayload {
    func createBucketProcessor(di: DI) throws -> BucketProcessor
}

public protocol BucketResult {
    
}

public protocol BucketProcessor {
    func execute(
        completion: @escaping (Result<BucketResult, Error>) -> ()
    )
}
