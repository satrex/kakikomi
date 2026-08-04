import CoreGraphics
import ScreenCaptureKit

@available(macOS 14.0, *)
final class ScreenshotCaptureService: NSObject, SCContentSharingPickerObserver {
    static let shared = ScreenshotCaptureService()
    private var continuation: CheckedContinuation<CGImage?, Error>?

    func captureImage() async throws -> CGImage? {
        try await withCheckedThrowingContinuation { continuation in
            guard self.continuation == nil else {
                continuation.resume(returning: nil)
                return
            }
            self.continuation = continuation
            let picker = SCContentSharingPicker.shared
            picker.add(self)
            picker.isActive = true
            picker.present()
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        finish(.success(nil))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.captureResolution = .best
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { [weak self] image, error in
            if let error { self?.finish(.failure(error)) }
            else { self?.finish(.success(image)) }
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CGImage?, Error>) {
        let continuation = continuation
        self.continuation = nil
        let picker = SCContentSharingPicker.shared
        picker.remove(self)
        picker.isActive = false
        switch result {
        case .success(let image): continuation?.resume(returning: image)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }
}

@available(macOS 14.0, *)
extension DocumentViewModel {
    func importScreenshot() async {
        guard shouldDiscardCurrentAnnotations() else { return }
        do {
            guard let image = try await ScreenshotCaptureService.shared.captureImage() else { return }
            openImage(image)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
