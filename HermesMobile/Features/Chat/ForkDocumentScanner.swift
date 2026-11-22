import SwiftUI
import VisionKit

struct ForkDocumentScanner: UIViewControllerRepresentable {
    var onFinish: (Result<Data, Error>?) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    @MainActor
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var onFinish: (Result<Data, Error>?) -> Void

        init(onFinish: @escaping (Result<Data, Error>?) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish(nil)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish(.failure(error))
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish(Result { try ForkScanPDF.make(pageCount: scan.pageCount, imageAt: scan.imageOfPage(at:)) })
        }
    }
}

enum ForkScanPDF {
    private enum Failure: Error { case emptyScan }

    static func make(pageCount: Int, imageAt: (Int) -> UIImage) throws -> Data {
        guard pageCount > 0 else { throw Failure.emptyScan }
        return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            ForkScanPages.append(count: pageCount) { index in
                autoreleasepool {
                    let image = imageAt(index)
                    let longest = max(image.size.width, image.size.height)
                    guard longest > 0 else { return }
                    let pdfScale = 792 / longest
                    let bounds = CGRect(origin: .zero, size: CGSize(
                        width: image.size.width * pdfScale, height: image.size.height * pdfScale
                    ))
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 2
                    format.opaque = true
                    let raster = UIGraphicsImageRenderer(size: bounds.size, format: format).image { rasterContext in
                        rasterContext.cgContext.setFillColor(UIColor.white.cgColor)
                        rasterContext.cgContext.fill(bounds)
                        image.draw(in: bounds)
                    }
                    let compressed = raster.jpegData(compressionQuality: 0.78).flatMap { UIImage(data: $0) } ?? raster
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    compressed.draw(in: bounds)
                }
            }
        }
    }
}
