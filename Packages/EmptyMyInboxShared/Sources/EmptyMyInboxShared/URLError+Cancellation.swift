import Foundation

extension Error {
    /// `NSURLErrorCancelled` (-999): request superseded or torn down — not an actionable failure for logging.
    public var isURLSessionCancellation: Bool {
        let ns = self as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}
