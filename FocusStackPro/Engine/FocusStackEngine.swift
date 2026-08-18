import CoreImage
import Vision
import Accelerate

class FocusStackEngine {
    private let context = CIContext()

    func alignImages(_ images: [CIImage], progressHandler: @escaping (Double) -> Void) async -> [CIImage] {
        guard images.count > 1 else { return images }
        let refIndex = images.count / 2
        let reference = images[refIndex]
        var aligned: [CIImage] = []
        for (i, image) in images.enumerated() {
            if i == refIndex {
                aligned.append(image)
            } else {
                aligned.append(await alignImage(image, to: reference) ?? image)
            }
            progressHandler(Double(i + 1) / Double(images.count))
        }
        return aligned
    }

    private func alignImage(_ image: CIImage, to reference: CIImage) async -> CIImage? {
        let request = VNTranslationalImageRegistrationRequest(targetedCIImage: reference)
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let obs = request.results?.first as? VNImageTranslationAlignmentObservation else { return image }
            return image.transformed(by: CGAffineTransform(
                translationX: obs.alignmentTransform.tx,
                y: obs.alignmentTransform.ty
            ))
        } catch {
            return image
        }
    }

    func generateDepthMap(_ images: [CIImage], progressHandler: @escaping (Double) -> Void) async -> DepthMapResult {
        let w = Int(images[0].extent.width)
        let h = Int(images[0].extent.height)
        var sharpnessMaps: [vImage_Buffer] = []
        for (i, img) in images.enumerated() {
            if let m = calculateSharpness(for: img) {
                sharpnessMaps.append(m)
            }
            progressHandler(Double(i + 1) / Double(images.count))
        }
        let depthBuf = createDepthMap(from: sharpnessMaps, width: w, height: h)
        let depthImage = bufferToCIImage(depthBuf, width: w, height: h)
        for var b in sharpnessMaps { b.free() }
        depthBuf.free()
        return DepthMapResult(depthMap: depthImage, sharpnessMaps: [])
    }

    private func calculateSharpness(for image: CIImage) -> vImage_Buffer? {
        let kernel: [Float] = [0, 1, 0, 1, -4, 1, 0, 1, 0]
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        var src = createBuffer(from: cg)
        var dst = createEmptyBuffer(width: Int(image.extent.width), height: Int(image.extent.height))
        let k = [Int16](kernel.map { Int16($0 * 256) })
        k.withUnsafeBufferPointer { ptr in
            vImageConvolve_Planar8(
                &src,
                &dst,
                nil,
                0,
                0,
                ptr.baseAddress,
                3,
                3,
                1,
                0,
                vImage_Flags(kvImageEdgeExtend)
            )
        }
        src.free()
        return dst
    }

    private func createDepthMap(from maps: [vImage_Buffer], width: Int, height: Int) -> vImage_Buffer {
        var depth = createEmptyBuffer(width: width, height: height)
        guard let depthData = depth.data.assumingMemoryBound(to: UInt8.self), !maps.isEmpty else { return depth }
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                var maxS: UInt8 = 0
                var maxI: UInt8 = 0
                for (mi, map) in maps.enumerated() {
                    guard let md = map.data.assumingMemoryBound(to: UInt8.self) else { continue }
                    if md[idx] > maxS {
                        maxS = md[idx]
                        maxI = UInt8(mi)
                    }
                }
                depthData[idx] = UInt8((Double(maxI) / Double(maps.count - 1)) * 255.0)
            }
        }
        return depth
    }

    func blendStack(
        _ images: [CIImage],
        depthMap: DepthMapResult,
        method: StackingMethod,
        progressHandler: @escaping (Double) -> Void
    ) async -> CIImage {
        switch method {
        case .weightedAverage:
            return blendWeightedAverage(images, progressHandler: progressHandler)
        case .depthMap:
            return blendWithDepthMap(images, depthMap: depthMap, progressHandler: progressHandler)
        case .pyramid:
            return blendPyramid(images, progressHandler: progressHandler)
        }
    }

    private func blendWeightedAverage(_ images: [CIImage], progressHandler: @escaping (Double) -> Void) -> CIImage {
        guard !images.isEmpty else { return CIImage.empty() }
        var result = CIImage.empty()
        let weight = 1.0 / Double(images.count)
        for (i, image) in images.enumerated() {
            let w = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: weight, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: weight, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: weight, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
            result = i == 0 ? w : w.composited(over: result)
            progressHandler(Double(i + 1) / Double(images.count))
        }
        return result
    }

    private func blendWithDepthMap(
        _ images: [CIImage],
        depthMap: DepthMapResult,
        progressHandler: @escaping (Double) -> Void
    ) -> CIImage {
        guard !images.isEmpty else { return CIImage.empty() }
        var result = CIImage.empty()
        for (i, image) in images.enumerated() {
            let norm = Double(i) / Double(images.count - 1)
            let mask = createMaskForSource(depthMap: depthMap.depthMap, sourceIndex: norm)
            let masked = image.applyingFilter("CIBlendWithMask", parameters: [
                "inputBackgroundImage": CIImage(color: .clear).cropped(to: image.extent),
                "inputMaskImage": mask
            ])
            result = i == 0 ? masked : masked.composited(over: result)
            progressHandler(Double(i + 1) / Double(images.count))
        }
        return result
    }

    private func blendPyramid(_ images: [CIImage], progressHandler: @escaping (Double) -> Void) -> CIImage {
        blendWeightedAverage(
            images.map { $0.applyingGaussianBlur(sigma: 0.5) },
            progressHandler: progressHandler
        )
    }

    private func createMaskForSource(depthMap: CIImage, sourceIndex: Double) -> CIImage {
        depthMap.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": sourceIndex - 0.05])
    }

    private func createBuffer(from cg: CGImage) -> vImage_Buffer {
        let w = cg.width
        let h = cg.height
        let data = UnsafeMutableRawPointer.allocate(byteCount: w * h, alignment: 16)
        return vImage_Buffer(
            data: data,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w
        )
    }

    private func createEmptyBuffer(width: Int, height: Int) -> vImage_Buffer {
        let data = UnsafeMutableRawPointer.allocate(byteCount: width * height, alignment: 16)
        data.initializeMemory(as: UInt8.self, repeating: 0, count: width * height)
        return vImage_Buffer(
            data: data,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width
        )
    }

    private func bufferToCIImage(_ buffer: vImage_Buffer, width: Int, height: Int) -> CIImage {
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: buffer.data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: buffer.rowBytes,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue).rawValue
        ),
        let cg = ctx.makeImage() else { return CIImage.empty() }
        return CIImage(cgImage: cg)
    }
}

struct DepthMapResult {
    let depthMap: CIImage
    let sharpnessMaps: [vImage_Buffer]
}

extension vImage_Buffer {
    mutating func free() {
        data.deallocate()
    }
}
