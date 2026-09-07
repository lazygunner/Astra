import AVFoundation
import CoreImage
import CoreVideo
import Metal
import QuartzCore
import RealityKit
import simd
import UIKit
import Observation

/// Keeps the projector optional so the rest of the app can still run on visionOS 26.
/// The projective-texture API itself is available starting in visionOS 27.
@MainActor
@Observable
final class ProjectorController {
    @ObservationIgnored private var implementation: AnyObject?
    private(set) var status = "选择视频后生效"

    func showTestPattern() {
        guard #available(visionOS 27.0, *),
              let projector = implementation as? VideoProjector else { return }
        projector.showTestPattern()
    }

    var isAvailable: Bool {
        guard #available(visionOS 27.0, *),
              let projector = implementation as? VideoProjector else {
            return false
        }
        return projector.isAttached
    }

    func attach(to asset: Entity) {
        detach()
        guard #available(visionOS 27.0, *), let projector = VideoProjector() else { return }
        projector.reportStatus = { [weak self] in self?.status = $0 }
        projector.attach(to: asset)
        implementation = projector
    }

    func prepare(item: AVPlayerItem) {
        guard #available(visionOS 27.0, *),
              let projector = implementation as? VideoProjector else { return }
        projector.prepare(item: item)
    }

    func start(item: AVPlayerItem) {
        guard #available(visionOS 27.0, *),
              let projector = implementation as? VideoProjector else { return }
        projector.start(item: item)
    }

    func stopVideo() {
        guard #available(visionOS 27.0, *),
              let projector = implementation as? VideoProjector else { return }
        projector.stopVideo()
    }

    func stopProjection() {
        guard #available(visionOS 27.0, *),
              let projector = implementation as? VideoProjector else { return }
        projector.stopProjection()
    }

    func detach() {
        if #available(visionOS 27.0, *),
           let projector = implementation as? VideoProjector {
            projector.detach()
        }
        implementation = nil
    }
}

@available(visionOS 27.0, *)
@MainActor
private final class VideoProjector {
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let entity = Entity()

    private weak var asset: Entity?
    private var item: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var texture: TextureResource?
    private var lowLevelTexture: LowLevelTexture?
    private var testTexture: TextureResource?
    private var hasSubmittedFrame = false
    private var startedAt = CACurrentMediaTime()
    private var generation = UUID()
    private var isFrameInFlight = false
    var reportStatus: (String) -> Void = { _ in }
    private var frameTask: Task<Void, Never>?

    private(set) var isAttached = false

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              device.supportsFamily(.apple6),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = commandQueue
        ciContext = CIContext(mtlDevice: device)
    }

    func attach(to asset: Entity) {
        detach()
        self.asset = asset
        isAttached = false

        guard let screen = asset.findEntity(named: "Display___convex_glass___image_bearing_surface") else {
            return
        }

        // The display mesh is thin along its normal. Use the model bounds to put
        // the projector just behind the model, instead of baking an authored offset.
        let screenBounds = screen.visualBounds(relativeTo: asset)
        let assetBounds = asset.visualBounds(relativeTo: asset)
        let screenExtents = screenBounds.extents
        let normalAxis: Int
        if screenExtents.x <= screenExtents.y && screenExtents.x <= screenExtents.z {
            normalAxis = 0
        } else if screenExtents.y <= screenExtents.z {
            normalAxis = 1
        } else {
            normalAxis = 2
        }

        let screenCenter = screenBounds.center
        let assetCenter = assetBounds.center
        let frontSign: Float = screenCenter[normalAxis] < assetCenter[normalAxis] ? -1 : 1
        let backSign = -frontSign
        let spacing = max(assetBounds.extents[normalAxis] * 0.08, 0.01)

        var position = screenCenter
        position[normalAxis] = assetCenter[normalAxis]
            + backSign * (assetBounds.extents[normalAxis] * 0.5 + spacing)

        var backDirection = SIMD3<Float>.zero
        backDirection[normalAxis] = backSign

        entity.name = "AstraVideoProjector"
        entity.position = position
        entity.orientation = rotation(from: [0, 0, -1], to: backDirection)
        entity.components.set(
            SpotLightComponent(
                color: .white,
                intensity: 20_000,
                innerAngleInDegrees: 46,
                outerAngleInDegrees: 48,
                attenuationRadius: 6
            )
        )
        asset.addChild(entity)
        entity.isEnabled = false
        isAttached = true
    }

    /// Adds a second consumer to the same player item. The existing AVPlayer and
    /// VideoMaterial remain responsible for the model screen's playback.
    func prepare(item: AVPlayerItem) {
        stopVideo()

        let attributes = CVPixelBufferAttributes(
            pixelFormatTypes: [CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA)],
            compatibility: .metalTexture
        )
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        item.add(output)
        self.item = item
        videoOutput = output
    }

    func start(item: AVPlayerItem) {
        guard self.item === item,
              videoOutput != nil,
              item.presentationSize.width > 0,
              item.presentationSize.height > 0 else {
            return
        }

        frameTask?.cancel()
        frameTask = nil
        generation = UUID()
        isFrameInFlight = false

        entity.isEnabled = hasSubmittedFrame
        entity.components.set(SpotLightComponent.SurroundingsLight())
        if let texture, hasSubmittedFrame {
            // Re-enabling while paused must keep displaying the last frame.
            entity.components.set(SpotLightComponent.ProjectiveTexture(texture: texture))
            reportStatus("已提交视频画面；投向模型背后 6 米内的表面")
        } else {
            entity.components.remove(SpotLightComponent.ProjectiveTexture.self)
            reportStatus("正在等待视频画面…")
        }
        startedAt = CACurrentMediaTime()
        frameTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updateFrame()
                do {
                    try await Task.sleep(for: .milliseconds(33))
                } catch { return }
            }
        }
    }

    func showTestPattern() {
        stopProjection()
        do {
            if testTexture == nil {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { context in
                    UIColor.black.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
                    for y in 0..<8 {
                        for x in 0..<8 where (x + y).isMultiple(of: 2) {
                            UIColor.white.setFill()
                            context.fill(CGRect(x: x * 64, y: y * 64, width: 64, height: 64))
                        }
                    }
                    UIColor.red.setFill()
                    context.fill(CGRect(x: 240, y: 0, width: 32, height: 512))
                    context.fill(CGRect(x: 0, y: 240, width: 512, height: 32))
                }
                guard let cgImage = image.cgImage else { throw ProjectorError.cannotCreateTexture }
                testTexture = try TextureResource(image: cgImage, options: .init(semantic: .color, mipmapsMode: .none))
            }
            guard let testTexture else { return }
            entity.components.set(SpotLightComponent.ProjectiveTexture(texture: testTexture))
            entity.components.set(SpotLightComponent.SurroundingsLight())
            entity.isEnabled = true
            reportStatus("测试图案已开启：将模型背面对准附近墙面")
        } catch {
            reportStatus("投影测试失败：\(error.localizedDescription)")
        }
    }

    func stopVideo() {
        stopProjection()

        if let item, let videoOutput {
            item.remove(videoOutput)
        }
        item = nil
        videoOutput = nil
        lowLevelTexture = nil
        texture = nil
        hasSubmittedFrame = false
    }

    func stopProjection() {
        frameTask?.cancel()
        frameTask = nil
        generation = UUID()
        isFrameInFlight = false
        entity.isEnabled = false
        reportStatus("投影已关闭")
        entity.components.remove(SpotLightComponent.ProjectiveTexture.self)
        entity.components.remove(SpotLightComponent.SurroundingsLight.self)
    }

    func detach() {
        stopVideo()
        entity.removeFromParent()
        asset = nil
        isAttached = false
    }

    private func updateFrame() {
        guard let videoOutput, let item, !isFrameInFlight else { return }
        // Use the player's actual timeline, including a paused frame or seek.
        let itemTime = item.currentTime()
        guard itemTime.isNumeric,
              videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
              let frame = videoOutput.pixelBufferAndDisplayTime(forItemTime: itemTime).pixelBuffer else {
            if !hasSubmittedFrame && CACurrentMediaTime() - startedAt > 3 {
                reportStatus("尚未收到视频画面；可点“测试墙面投影”检查灯光")
            }
            return
        }

        do {
            try frame.withUnsafeBuffer { pixelBuffer in
                let image = CIImage(cvPixelBuffer: pixelBuffer)
                // The decoded buffer can differ from presentationSize (rotation,
                // aperture, adaptive resolution). Fit it into a square light mask
                // so the spotlight does not stretch a widescreen video to a square.
                let side = min(1024, max(CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer)))
                if lowLevelTexture?.descriptor.width != side {
                    let lowLevel = try LowLevelTexture(descriptor: .init(
                        pixelFormat: .bgra8Unorm,
                        width: side, height: side,
                        textureUsage: [.shaderRead, .shaderWrite, .renderTarget]
                    ))
                    texture = try TextureResource(from: lowLevel)
                    lowLevelTexture = lowLevel
                }
                guard let lowLevelTexture, let texture,
                      let commandBuffer = commandQueue.makeCommandBuffer() else {
                    throw ProjectorError.cannotCreateTexture
                }
                let target = lowLevelTexture.replace(using: commandBuffer)
                let bounds = CGRect(x: 0, y: 0, width: side, height: side)
                // Keep all four corners inside the cone's uniform inner region.
                // Fitting the longest edge to the texture clips the corners on the
                // circular spotlight; fitting the diagonal leaves a black border.
                let displaySize = item.presentationSize
                let diagonal = hypot(displaySize.width, displaySize.height)
                guard diagonal > 0 else { throw ProjectorError.cannotCreateTexture }
                let factor = CGFloat(side) * 0.9 / diagonal
                let width = displaySize.width * factor
                let height = displaySize.height * factor
                let normalized = image.transformed(by: CGAffineTransform(
                    translationX: -image.extent.minX, y: -image.extent.minY
                ))
                // Core Image's Y axis is opposite the projector texture's Y axis.
                // Flip only this output; the model's VideoMaterial is already upright.
                let upright = normalized.transformed(by: CGAffineTransform(
                    a: 1, b: 0, c: 0, d: -1, tx: 0, ty: image.extent.height
                ))
                let fitted = upright.transformed(by: CGAffineTransform(
                    scaleX: width / image.extent.width,
                    y: height / image.extent.height
                ))
                let centered = fitted.transformed(by: CGAffineTransform(
                    translationX: (CGFloat(side) - fitted.extent.width) / 2,
                    y: (CGFloat(side) - fitted.extent.height) / 2
                ))
                let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: bounds)
                ciContext.render(centered.composited(over: black), to: target,
                                 commandBuffer: commandBuffer, bounds: bounds, colorSpace: colorSpace)
                // RealityKit waits for this command buffer. No DrawableQueue
                // timeout, black placeholder, or independent presentation queue.
                let request = generation
                isFrameInFlight = true
                commandBuffer.addCompletedHandler { [weak self] buffer in
                    let failure = buffer.error?.localizedDescription
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == request else { return }
                        self.isFrameInFlight = false
                        if let failure {
                            self.stopProjection()
                            self.reportStatus("投影 GPU 更新失败：\(failure)")
                        } else if !self.hasSubmittedFrame {
                            self.hasSubmittedFrame = true
                            self.entity.isEnabled = true
                            self.reportStatus("已提交视频画面；投向模型背后 6 米内的表面")
                        }
                    }
                }
                commandBuffer.commit()
                entity.components.set(SpotLightComponent.ProjectiveTexture(texture: texture))
            }
        } catch {
            reportStatus("投影画面更新失败：\(error.localizedDescription)")
        }
    }

    private func rotation(from source: SIMD3<Float>, to target: SIMD3<Float>) -> simd_quatf {
        let source = simd_normalize(source)
        let target = simd_normalize(target)
        let dot = simd_dot(source, target)
        if dot > 0.9999 { return simd_quatf() }
        if dot < -0.9999 {
            let helper: SIMD3<Float> = abs(source.x) < 0.9 ? [1, 0, 0] : [0, 1, 0]
            return simd_quatf(angle: .pi, axis: simd_normalize(simd_cross(source, helper)))
        }
        let axis = simd_normalize(simd_cross(source, target))
        return simd_quatf(angle: acos(max(-1, min(1, dot))), axis: axis)
    }

    private enum ProjectorError: Error {
        case cannotCreateTexture
    }
}
