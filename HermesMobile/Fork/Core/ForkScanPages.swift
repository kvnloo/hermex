enum ForkScanPages {
    /// Append exactly once per captured page, in the scanner's review order.
    static func append(count: Int, page: (Int) -> Void) {
        for index in 0..<max(0, count) { page(index) }
    }
}
