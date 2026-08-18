import CoreImage
import UIKit

extension CIImage {
    func applyingGaussianBlur(sigma: Double) -> CIImage {
        applyingFilter("CIGaussianBlur", parameters: ["inputRadius": sigma])
    }
}

extension CIContext {
    static let shared = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .useSoftwareRenderer: false
    ])
}
