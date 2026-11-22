import PDFKit
import UIKit
import XCTest
@testable import HermesMobile

final class ForkScanPDFTests: XCTestCase {
    @MainActor
    func testPDFKeepsOrientedPagesInCaptureOrder() throws {
        let sizes = [CGSize(width: 200, height: 100), CGSize(width: 100, height: 200)]
        let data = try ForkScanPDF.make(pageCount: sizes.count) { index in
            let size = sizes[index]
            return UIGraphicsImageRenderer(size: size).image {
                $0.cgContext.fill(CGRect(origin: .zero, size: size))
            }
        }
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 792, height: 396))
        XCTAssertEqual(pdf.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 396, height: 792))
    }
}
