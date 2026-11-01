enum ProbeTiming {
    static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        let value = seconds * 1000 + attoseconds / 1_000_000_000_000_000
        return Int(clamping: value)
    }
}
