enum ForkScanPages {
    static func append(count: Int, page: (Int) -> Void) {
        for index in 0..<max(0, count) { page(index) }
    }
}
