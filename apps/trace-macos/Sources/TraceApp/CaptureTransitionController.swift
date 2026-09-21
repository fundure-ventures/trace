import AppKit
import MetalKit
import QuartzCore
import TraceAppCore

struct CaptureTransitionSample: Equatable {
    let shaderProgress: Float
    let boardOpacity: CGFloat
    let overlayOpacity: CGFloat
    let revealsToolbar: Bool
}

enum CaptureTransitionPolicy {
    static let duration: TimeInterval = 0.90
    static let boardRevealProgress: CGFloat = 0.50
    static let toolbarRevealProgress: CGFloat = 0.58
    static let toolbarStartYOffset: CGFloat = -20
    static let toolbarRevealDuration: TimeInterval = 0.32
    static let fragmentFunctionName =
        "traceMonochromeFlashFragment"

    static func toolbarAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation(
            keyPath: "transform.translation.y"
        )
        animation.fromValue = toolbarStartYOffset
        animation.toValue = 0
        animation.duration = toolbarRevealDuration
        animation.timingFunction = CAMediaTimingFunction(
            name: .easeOut
        )
        return animation
    }

    static func finalBoardFrame(
        sourceFrame: NSRect,
        defaultFrame: NSRect
    ) -> NSRect {
        NSRect(
            origin: sourceFrame.origin,
            size: defaultFrame.size
        )
    }

    static func sample(
        progress: CGFloat
    ) -> CaptureTransitionSample {
        let progress = min(1, max(0, progress))
        return CaptureTransitionSample(
            shaderProgress: Float(progress),
            boardOpacity: smoothstep(
                boardRevealProgress,
                0.92,
                progress
            ),
            overlayOpacity:
                1 - smoothstep(toolbarRevealProgress, 1, progress),
            revealsToolbar: progress >= toolbarRevealProgress
        )
    }

    private static func smoothstep(
        _ start: CGFloat,
        _ end: CGFloat,
        _ value: CGFloat
    ) -> CGFloat {
        let amount = min(
            1,
            max(0, (value - start) / max(0.000_1, end - start))
        )
        return amount * amount * (3 - 2 * amount)
    }
}

enum BlankCanvasLoadingPolicy {
    static let rendererRevealDuration: TimeInterval = 0.28

    static func waitsForRenderer(
        pageKind: TracePageKind?,
        usesTldraw: Bool
    ) -> Bool {
        pageKind == .blank && usesTldraw
    }
}

final class CaptureTransitionController {
    private var overlayWindow: NSWindow?
    private var animationTimer: Timer?
    private var generation = 0

    func cancel() {
        generation += 1
        animationTimer?.invalidate()
        animationTimer = nil
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    func animate(
        capture: CapturedWindow,
        boardWindow: NSWindow?,
        revealToolbar: @escaping (_ animated: Bool) -> Void,
        durationScale: Double = 1,
        respectsReducedMotion: Bool = true,
        completion: @escaping () -> Void
    ) {
        cancel()
        guard (
                  !respectsReducedMotion
                    || !NSWorkspace.shared
                        .accessibilityDisplayShouldReduceMotion
              ),
              capture.sourceScreenFrame.width > 1,
              capture.sourceScreenFrame.height > 1,
              let captureView = MetalCaptureTransitionView.make(
                  image: capture.cgImage
              )
        else {
            boardWindow?.alphaValue = 1
            boardWindow?.makeKeyAndOrderFront(nil)
            revealToolbar(false)
            completion()
            return
        }

        let overlay = NSWindow(
            contentRect: capture.sourceScreenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = true
        overlay.level = .floating
        overlay.ignoresMouseEvents = true
        overlay.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
        overlay.contentView = captureView
        overlayWindow = overlay

        let animationGeneration = generation
        let duration = max(
            0.001,
            CaptureTransitionPolicy.duration
                * max(0.001, durationScale)
        )
        let startedAt = CACurrentMediaTime()
        var toolbarRevealed = false

        boardWindow?.alphaValue = 0
        boardWindow?.makeKeyAndOrderFront(nil)
        overlay.orderFrontRegardless()

        let timer = Timer(timeInterval: 1 / 60, repeats: true) {
            [weak self, weak boardWindow, weak overlay, weak captureView]
            timer in
            guard let self,
                  self.generation == animationGeneration,
                  let overlay,
                  let captureView
            else {
                timer.invalidate()
                return
            }
            let elapsed = CACurrentMediaTime() - startedAt
            let progress = CGFloat(min(1, elapsed / duration))
            let sample = CaptureTransitionPolicy.sample(
                progress: progress
            )
            captureView.progress = sample.shaderProgress
            boardWindow?.alphaValue = sample.boardOpacity
            overlay.alphaValue = sample.overlayOpacity
            if sample.revealsToolbar, !toolbarRevealed {
                toolbarRevealed = true
                revealToolbar(true)
            }
            guard progress >= 1 else {
                return
            }
            timer.invalidate()
            self.animationTimer = nil
            boardWindow?.alphaValue = 1
            if !toolbarRevealed {
                revealToolbar(true)
            }
            overlay.orderOut(nil)
            self.overlayWindow = nil
            completion()
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        captureView.progress = 0
    }
}

#if DEBUG
enum CaptureTransitionDiagnostics {
    static var fragmentFunctionNames: [String] {
        MetalCaptureTransitionView.fragmentFunctionNamesForTesting
    }

    static var canBuildEffect: Bool {
        MetalCaptureTransitionView.canBuildEffect
    }

    static var canExerciseEffect: Bool {
        guard let image = makeTestImage() else {
            return false
        }
        let frontmostProcessID =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        let controller = CaptureTransitionController()
        let board = NSWindow(
            contentRect: NSRect(
                x: -12_000,
                y: -12_000,
                width: 64,
                height: 48
            ),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        board.alphaValue = 0
        board.ignoresMouseEvents = true
        var toolbarReveal: Bool?
        var completed = false
        controller.animate(
            capture: CapturedWindow(
                descriptor: TraceWindowDescriptor(
                    id: 1,
                    ownerPID: 1,
                    layer: 0,
                    alpha: 1,
                    bounds: TraceRect(
                        x: -12_000,
                        y: -12_000,
                        width: 64,
                        height: 48
                    ),
                    ownerName: "Trace Probe",
                    title: "Monochrome capture"
                ),
                cgImage: image,
                sourceScreenFrame: NSRect(
                    x: -12_000,
                    y: -12_000,
                    width: 64,
                    height: 48
                )
            ),
            boardWindow: board,
            revealToolbar: { animated in
                toolbarReveal = animated
            },
            durationScale: 0.02,
            respectsReducedMotion: false
        ) {
            completed = true
        }
        let deadline = Date().addingTimeInterval(0.25)
        while !completed, Date() < deadline {
            RunLoop.current.run(
                until: Date().addingTimeInterval(0.01)
            )
        }
        controller.cancel()
        board.orderOut(nil)
        return completed
            && toolbarReveal == true
            && board.alphaValue == 1
            && NSWorkspace.shared.frontmostApplication?
                .processIdentifier == frontmostProcessID
    }

    private static func makeTestImage() -> CGImage? {
        guard let context = CGContext(
                  data: nil,
                  width: 64,
                  height: 48,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo:
                      CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return nil
        }
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        return context.makeImage()
    }
}
#endif

private final class MetalCaptureTransitionView:
    MTKView,
    MTKViewDelegate
{
    private struct Uniforms {
        var progress: Float
        var padding = SIMD3<Float>(repeating: 0)
    }

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let texture: MTLTexture

    var progress: Float = 0 {
        didSet {
            draw()
        }
    }

    override var isOpaque: Bool {
        false
    }

    static func make(
        image: CGImage
    ) -> MetalCaptureTransitionView? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(
                  source: shaderSource,
                  options: nil
              ),
              let pipelineState = makePipelineState(
                  device: device,
                  library: library
              ),
              let samplerState = makeSamplerState(device: device),
              let texture = try? MTKTextureLoader(
                  device: device
              ).newTexture(
                  cgImage: image,
                  options: [
                      .SRGB: true,
                      .origin: MTKTextureLoader.Origin.topLeft,
                  ]
              )
        else {
            return nil
        }
        return MetalCaptureTransitionView(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            samplerState: samplerState,
            texture: texture
        )
    }

#if DEBUG
    static var canBuildEffect: Bool {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeLibrary(
                  source: shaderSource,
                  options: nil
              )
        else {
            return false
        }
        return makePipelineState(
            device: device,
            library: library
        ) != nil
            && makeSamplerState(device: device) != nil
    }

    static var fragmentFunctionNamesForTesting: [String] {
        shaderSource.split(separator: "\n").compactMap { line in
            let declaration = line.trimmingCharacters(
                in: .whitespaces
            )
            let prefix = "fragment float4 "
            guard declaration.hasPrefix(prefix),
                  let parenthesis = declaration.firstIndex(of: "(")
            else {
                return nil
            }
            return String(
                declaration[
                    declaration.index(
                        declaration.startIndex,
                        offsetBy: prefix.count
                    )..<parenthesis
                ]
            )
        }
    }
#endif

    private static func makePipelineState(
        device: MTLDevice,
        library: MTLLibrary
    ) -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(
                  name: "traceCaptureVertex"
              ),
              let fragmentFunction = library.makeFunction(
                  name: CaptureTransitionPolicy.fragmentFunctionName
              )
        else {
            return nil
        }
        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.vertexFunction = vertexFunction
        pipeline.fragmentFunction = fragmentFunction
        pipeline.colorAttachments[0].pixelFormat =
            .bgra8Unorm_srgb
        return try? device.makeRenderPipelineState(
            descriptor: pipeline
        )
    }

    private static func makeSamplerState(
        device: MTLDevice
    ) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToZero
        descriptor.tAddressMode = .clampToZero
        return device.makeSamplerState(descriptor: descriptor)
    }

    private init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipelineState: MTLRenderPipelineState,
        samplerState: MTLSamplerState,
        texture: MTLTexture
    ) {
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.samplerState = samplerState
        self.texture = texture
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm_srgb
        clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        delegate = self
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.isOpaque = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {}

    func draw(in view: MTKView) {
        guard let descriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                  descriptor: descriptor
              )
        else {
            return
        }
        var uniforms = Uniforms(
            progress: min(1, max(0, progress))
        )
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 3
        )
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct TraceCaptureVertexOut {
            float4 position [[position]];
            float2 uv;
        };

        struct TraceCaptureUniforms {
            float progress;
            float3 padding;
        };

        vertex TraceCaptureVertexOut traceCaptureVertex(
            uint vertexID [[vertex_id]]
        ) {
            const float2 positions[3] = {
                float2(-1.0, -1.0),
                float2(3.0, -1.0),
                float2(-1.0, 3.0)
            };
            const float2 coordinates[3] = {
                float2(0.0, 1.0),
                float2(2.0, 1.0),
                float2(0.0, -1.0)
            };
            TraceCaptureVertexOut output;
            output.position = float4(positions[vertexID], 0.0, 1.0);
            output.uv = coordinates[vertexID];
            return output;
        }

        float tracePulse(
            float progress,
            float start,
            float peak,
            float end
        ) {
            const float fadeIn = smoothstep(start, peak, progress);
            const float fadeOut = 1.0 - smoothstep(peak, end, progress);
            return fadeIn * fadeOut;
        }

        fragment float4 traceMonochromeFlashFragment(
            TraceCaptureVertexOut input [[stage_in]],
            constant TraceCaptureUniforms &uniforms [[buffer(0)]],
            texture2d<float> capture [[texture(0)]],
            sampler captureSampler [[sampler(0)]]
        ) {
            const float4 base = capture.sample(
                captureSampler,
                input.uv
            );
            const float luminance = dot(
                base.rgb,
                float3(0.2126, 0.7152, 0.0722)
            );
            const float monochromeIn = smoothstep(
                0.02,
                0.32,
                uniforms.progress
            );
            const float colorReturn = smoothstep(
                0.62,
                1.0,
                uniforms.progress
            );
            const float monochrome =
                monochromeIn * (1.0 - colorReturn);
            const float flash = tracePulse(
                uniforms.progress,
                0.30,
                0.50,
                0.82
            );
            const float3 graded = mix(
                base.rgb,
                float3(luminance),
                monochrome
            );
            return float4(
                mix(graded, float3(1.0), flash),
                base.a
            );
        }
        """
}
