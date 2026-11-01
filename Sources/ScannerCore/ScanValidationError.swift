/// A request was rejected before any probe was sent.
public enum ScanValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The target text was empty.
    case emptyTarget
    /// The target text was not a supported IPv4 form.
    case invalidTarget(String)
    /// A range end was numerically below its start.
    case invertedRange
    /// The expanded address count is above `limit`.
    case rangeTooLarge(count: Int, limit: Int)
    /// The port text was not a list of TCP ports.
    case invalidPortList(String)
    /// Concurrency was outside `1...256`.
    case invalidConcurrency
    /// A timeout was zero or negative.
    case invalidTimeout
    /// At least one address is public and the caller has not acknowledged it.
    case publicRangeRequiresAcknowledgement
    /// A scan is already `running` or `paused`.
    case alreadyRunning

    public var description: String {
        switch self {
        case .emptyTarget:
            return "Enter an IPv4 address, range, or CIDR prefix."
        case .invalidTarget(let text):
            return "\"\(text)\" is not an IPv4 address, range, or CIDR prefix."
        case .invertedRange:
            return "The range end is below the start."
        case .rangeTooLarge(let count, let limit):
            return "That range has \(count) addresses, which is above the limit of \(limit)."
        case .invalidPortList(let text):
            return "\"\(text)\" is not a list of TCP ports."
        case .invalidConcurrency:
            return "Concurrency must be between 1 and 256."
        case .invalidTimeout:
            return "The probe timeout must be greater than zero."
        case .publicRangeRequiresAcknowledgement:
            return "This range includes public addresses. Acknowledge the warning before scanning."
        case .alreadyRunning:
            return "A scan is already in progress."
        }
    }
}
