import AppKit
import MetalKit
import TraceAppCore

enum TraceGridContrastPolicy {
    static let redWeight = 0.2126
    static let greenWeight = 0.7152
    static let blueWeight = 0.0722
    static let lightBackgroundThreshold = 0.5
    static let opacity = 0.20

#if DEBUG
    static func gridColor(
        for background: NSColor,
        style: TraceGridStyle
    ) -> NSColor {
        guard style != .none else {
            return .clear
        }
        guard let color = background.usingColorSpace(.deviceRGB) else {
            return NSColor.white.withAlphaComponent(opacity)
        }
        let luminance =
            color.redComponent * redWeight
            + color.greenComponent * greenWeight
            + color.blueComponent * blueWeight
        return (
            luminance > lightBackgroundThreshold ? NSColor.black : .white
        ).withAlphaComponent(opacity)
    }
#endif
}

final class ScreenshotGridSurfaceView: NSView {
    private let metalView: ProceduralGridMetalView
    private var document: TraceDrawingSession?
    private var screenshotImage: NSImage?
    private var gridStyle: TraceGridStyle = .none
    private var gridSpacingPoints = TraceGridPolicy.defaultSpacingPoints
    private var metalTextureReady = false
    private var viewport = TracePageViewport.full
    private var displaysScreenshot = true

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        guard let metalView = ProceduralGridMetalView.make() else {
            fatalError("Trace requires a Metal grid renderer.")
        }
        self.metalView = metalView
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.needsDisplayOnBoundsChange = true
        metalView.isHidden = true
        metalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metalView)
        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setDocument(_ document: TraceDrawingSession) {
        self.document = document
        screenshotImage = displayImage(for: document)
        viewport = document.manifest.viewport ?? TracePageViewport.full
        metalTextureReady = metalView.setScreenshot(
            screenshotImage ?? document.screenshot,
            pointSize: sourcePointSize(for: document),
            viewport: viewport
        )
        if gridStyle != .none, !metalTextureReady {
            fatalError("Trace could not create the Metal grid texture.")
        }
        applyGridStateIfReady()
        needsDisplay = true
    }

    func setBackgroundColor(_ color: TraceRGBAColor) {
        guard let document else {
            return
        }
        if document.manifest.pageKind == .blank {
            screenshotImage = solidImage(color)
            metalTextureReady = metalView.setScreenshot(
                screenshotImage ?? document.screenshot,
                pointSize: sourcePointSize(for: document),
                viewport: TracePageViewport.full
            )
            if gridStyle != .none, !metalTextureReady {
                fatalError("Trace could not update the Metal grid texture.")
            }
            applyGridStateIfReady()
        }
        needsDisplay = true
    }

    func setDisplaysScreenshot(_ displaysScreenshot: Bool) {
        guard self.displaysScreenshot != displaysScreenshot else {
            return
        }
        self.displaysScreenshot = displaysScreenshot
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard displaysScreenshot else {
            return nil
        }
        return super.hitTest(point)
    }

    func refreshDocumentGeometry() {
        guard let document else {
            return
        }
        viewport = document.manifest.viewport ?? TracePageViewport.full
        metalView.setGeometry(
            pointSize: sourcePointSize(for: document),
            viewport: viewport
        )
        needsDisplay = true
    }

    func setGrid(
        style: TraceGridStyle,
        spacingPoints: Int
    ) {
        let spacing = TraceGridPolicy.clampedSpacing(spacingPoints)
        guard style != gridStyle || spacing != gridSpacingPoints else {
            return
        }
        gridStyle = style
        gridSpacingPoints = spacing
        applyGridStateIfReady()
    }

    private func applyGridStateIfReady() {
        metalView.isHidden = gridStyle == .none || !metalTextureReady
        guard metalTextureReady else {
            return
        }
        metalView.setGrid(
            style: gridStyle,
            spacingPoints: gridSpacingPoints
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if displaysScreenshot, let screenshotImage {
            let sourceRect = NSRect(
                x: screenshotImage.size.width * viewport.x,
                y: screenshotImage.size.height
                    * (1 - viewport.y - viewport.height),
                width: screenshotImage.size.width * viewport.width,
                height: screenshotImage.size.height * viewport.height
            )
            screenshotImage.draw(
                in: bounds,
                from: sourceRect,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
    }

    private func displayImage(
        for document: TraceDrawingSession
    ) -> NSImage {
        if document.manifest.pageKind == .blank {
            return solidImage(
                document.manifest.backgroundColor
                    ?? TraceRGBAColor(red: 1, green: 1, blue: 1)
            )
        }
        return document.screenshot
    }

    private func solidImage(_ color: TraceRGBAColor) -> NSImage {
        guard let representation = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: 1,
                  pixelsHigh: 1,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bitmapFormat: [],
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(
                  bitmapImageRep: representation
              )
        else {
            fatalError("Trace could not create a blank Metal grid texture.")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(color).setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.addRepresentation(representation)
        return image
    }

    private func sourcePointSize(
        for document: TraceDrawingSession
    ) -> TraceSize {
        if let bounds = document.manifest.sourceWindowBounds {
            return TraceSize(
                width: max(1, bounds.width),
                height: max(1, bounds.height)
            )
        }
        return TraceSize(
            width: max(1, document.screenshot.size.width),
            height: max(1, document.screenshot.size.height)
        )
    }

#if DEBUG
    var displaysScreenshotForTesting: Bool {
        displaysScreenshot
    }

    var submittedMetalFrameCountForTesting: Int {
        metalView.submittedFrameCountForTesting
    }

    var submittedGridStateForTesting: (
        style: TraceGridStyle,
        spacingPoints: Int
    )? {
        metalView.submittedGridStateForTesting
    }

    var submittedGridGeometryForTesting: (
        viewPointSize: TraceSize,
        horizontalSpacing: Double,
        verticalSpacing: Double,
        dotDiameter: Double,
        lineWidth: Double
    )? {
        metalView.submittedGridGeometryForTesting
    }

    var usesIsotropicViewPointGridForTesting: Bool {
        metalView.usesIsotropicViewPointGridForTesting
    }

    func resetSubmittedMetalFrameCountForTesting() {
        metalView.resetSubmittedFrameCountForTesting()
    }

    func flushScheduledMetalDrawForTesting() {
        metalView.flushScheduledDrawForTesting()
    }

    var metalGridGeometryForTesting: (
        sourcePointSize: TraceSize,
        viewport: TraceRect
    ) {
        metalView.geometryForTesting
    }

    var configuredGridStateForTesting: (
        style: TraceGridStyle,
        spacingPoints: Int,
        textureReady: Bool,
        metalHidden: Bool
    ) {
        (
            gridStyle,
            gridSpacingPoints,
            metalTextureReady,
            metalView.isHidden
        )
    }
#endif
}

private final class ProceduralGridMetalView: MTKView, MTKViewDelegate {
    private struct Uniforms {
        var viewPointSize: SIMD2<Float>
        var viewportOrigin: SIMD2<Float>
        var viewportSize: SIMD2<Float>
        var spacingPoints: Float
        var dotRadiusPoints: Float
        var lineHalfWidthPoints: Float
        var style: UInt32
    }

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let textureLoader: MTKTextureLoader
    private var screenshotTexture: MTLTexture?
    private var sourcePointSize = SIMD2<Float>(repeating: 1)
    private var viewportOrigin = SIMD2<Float>(repeating: 0)
    private var viewportSize = SIMD2<Float>(repeating: 1)
    private var gridStyle: TraceGridStyle = .none
    private var gridSpacingPoints = TraceGridPolicy.defaultSpacingPoints
    private var redrawPending = false
    private var redrawScheduled = false
    private var frameInFlight = false
#if DEBUG
    private(set) var submittedFrameCountForTesting = 0
    private(set) var submittedGridStateForTesting: (
        style: TraceGridStyle,
        spacingPoints: Int
    )?
    private(set) var submittedGridGeometryForTesting: (
        viewPointSize: TraceSize,
        horizontalSpacing: Double,
        verticalSpacing: Double,
        dotDiameter: Double,
        lineWidth: Double
    )?
#endif

    override var isOpaque: Bool {
        false
    }

    static func make() -> ProceduralGridMetalView? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(
                  source: Self.shaderSource,
                  options: nil
              ),
              let vertexFunction = library.makeFunction(
                  name: "traceGridVertex"
              ),
              let fragmentFunction = library.makeFunction(
                  name: "traceGridFragment"
              )
        else {
            return nil
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat =
            .bgra8Unorm_srgb
        guard let pipelineState = try? device.makeRenderPipelineState(
            descriptor: pipelineDescriptor
        ) else {
            return nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let samplerState = device.makeSamplerState(
            descriptor: samplerDescriptor
        ) else {
            return nil
        }
        return ProceduralGridMetalView(
            device: device,
            commandQueue: commandQueue,
            pipelineState: pipelineState,
            samplerState: samplerState
        )
    }

    private init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipelineState: MTLRenderPipelineState,
        samplerState: MTLSamplerState
    ) {
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.samplerState = samplerState
        textureLoader = MTKTextureLoader(device: device)
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
        layer?.isOpaque = false
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setScreenshot(
        _ image: NSImage,
        pointSize: TraceSize,
        viewport: TraceRect
    ) -> Bool {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            screenshotTexture = nil
            return false
        }
        do {
            screenshotTexture = try textureLoader.newTexture(
                cgImage: cgImage,
                options: [
                    .SRGB: true,
                    .origin: MTKTextureLoader.Origin.topLeft,
                ]
            )
            (layer as? CAMetalLayer)?.colorspace = cgImage.colorSpace
            sourcePointSize = SIMD2<Float>(
                Float(max(1, pointSize.width)),
                Float(max(1, pointSize.height))
            )
            setViewport(viewport)
            if gridStyle != .none {
                requestDraw()
            }
            return true
        } catch {
            screenshotTexture = nil
            return false
        }
    }

    func setGeometry(
        pointSize: TraceSize,
        viewport: TraceRect
    ) {
        sourcePointSize = SIMD2<Float>(
            Float(max(1, pointSize.width)),
            Float(max(1, pointSize.height))
        )
        setViewport(viewport)
        if gridStyle != .none {
            requestDraw()
        }
    }

    private func setViewport(_ viewport: TraceRect) {
        viewportOrigin = SIMD2<Float>(
            Float(viewport.x),
            Float(viewport.y)
        )
        viewportSize = SIMD2<Float>(
            Float(viewport.width),
            Float(viewport.height)
        )
    }

    func setGrid(
        style: TraceGridStyle,
        spacingPoints: Int
    ) {
        let spacing = TraceGridPolicy.clampedSpacing(spacingPoints)
        guard style != gridStyle || spacing != gridSpacingPoints else {
            return
        }
        gridStyle = style
        gridSpacingPoints = spacing
        guard style != .none else {
            redrawPending = false
            return
        }
        requestDraw()
    }

    func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {
        requestDraw()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleDrawIfNeeded()
    }

    func draw(in view: MTKView) {
        guard !frameInFlight else {
            redrawPending = true
            return
        }
        guard let screenshotTexture,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                  descriptor: renderPassDescriptor
              )
        else {
            redrawPending = true
            return
        }
        guard let gridMetrics = TraceGridPolicy.metrics(
            spacingPoints: gridSpacingPoints,
            displaySize: TraceSize(
                width: Double(bounds.width),
                height: Double(bounds.height)
            )
        ) else {
            redrawPending = true
            return
        }
        redrawPending = false
        frameInFlight = true

        var uniforms = Uniforms(
            viewPointSize: SIMD2<Float>(
                Float(bounds.width),
                Float(bounds.height)
            ),
            viewportOrigin: viewportOrigin,
            viewportSize: viewportSize,
            spacingPoints: Float(gridMetrics.horizontalSpacing),
            dotRadiusPoints: Float(gridMetrics.dotDiameter / 2),
            lineHalfWidthPoints: Float(gridMetrics.lineWidth / 2),
            style: UInt32(
                TraceGridControlPolicy.segment(for: gridStyle)
            )
        )
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(screenshotTexture, index: 0)
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
#if DEBUG
        submittedFrameCountForTesting += 1
        submittedGridStateForTesting = (
            gridStyle,
            gridSpacingPoints
        )
        submittedGridGeometryForTesting = (
            viewPointSize: TraceSize(
                width: Double(uniforms.viewPointSize.x),
                height: Double(uniforms.viewPointSize.y)
            ),
            horizontalSpacing: gridMetrics.horizontalSpacing,
            verticalSpacing: gridMetrics.verticalSpacing,
            dotDiameter: gridMetrics.dotDiameter,
            lineWidth: gridMetrics.lineWidth
        )
#endif
        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.frameInFlight = false
                self.scheduleDrawIfNeeded()
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func requestDraw() {
        redrawPending = true
        if window == nil {
            setNeedsDisplay(bounds)
            return
        }
        scheduleDrawIfNeeded()
    }

    private func scheduleDrawIfNeeded() {
        guard window != nil,
              redrawPending,
              !redrawScheduled,
              !frameInFlight
        else {
            return
        }
        redrawScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.redrawScheduled = false
            guard self.window != nil,
                  self.redrawPending,
                  !self.frameInFlight
            else {
                return
            }
            self.draw()
            if !self.frameInFlight {
                self.setNeedsDisplay(self.bounds)
            }
        }
    }

#if DEBUG
    var geometryForTesting: (
        sourcePointSize: TraceSize,
        viewport: TraceRect
    ) {
        (
            sourcePointSize: TraceSize(
                width: Double(sourcePointSize.x),
                height: Double(sourcePointSize.y)
            ),
            viewport: TraceRect(
                x: Double(viewportOrigin.x),
                y: Double(viewportOrigin.y),
                width: Double(viewportSize.x),
                height: Double(viewportSize.y)
            )
        )
    }

    func resetSubmittedFrameCountForTesting() {
        submittedFrameCountForTesting = 0
    }

    func flushScheduledDrawForTesting() {
        redrawScheduled = false
        guard redrawPending, !frameInFlight else {
            return
        }
        draw()
    }

    var usesIsotropicViewPointGridForTesting: Bool {
        Self.shaderSource.contains(
            "input.uv * uniforms.viewPointSize;"
        )
            && Self.shaderSource.contains(
                "uniforms.dotRadiusPoints - dotAA"
            )
            && !Self.shaderSource.contains(
                "sampleUV * uniforms.sourcePointSize"
            )
    }
#endif

    private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct TraceGridVertexOut {
            float4 position [[position]];
            float2 uv;
        };

        struct TraceGridUniforms {
            float2 viewPointSize;
            float2 viewportOrigin;
            float2 viewportSize;
            float spacingPoints;
            float dotRadiusPoints;
            float lineHalfWidthPoints;
            uint style;
        };

        vertex TraceGridVertexOut traceGridVertex(
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
            TraceGridVertexOut output;
            output.position = float4(positions[vertexID], 0.0, 1.0);
            output.uv = coordinates[vertexID];
            return output;
        }

        fragment float4 traceGridFragment(
            TraceGridVertexOut input [[stage_in]],
            constant TraceGridUniforms &uniforms [[buffer(0)]],
            texture2d<float> screenshot [[texture(0)]],
            sampler screenshotSampler [[sampler(0)]]
        ) {
            const float2 sampleUV = uniforms.viewportOrigin
                + input.uv * uniforms.viewportSize;
            const float4 base = screenshot.sample(
                screenshotSampler,
                sampleUV
            );
            if (uniforms.style == 0 || base.a <= 0.0) {
                return float4(0.0);
            }

            const float spacing = max(uniforms.spacingPoints, 1.0);
            const float2 viewPoint =
                input.uv * uniforms.viewPointSize;
            const float2 cell = fmod(viewPoint, float2(spacing));
            const float2 lineDistance = min(
                cell,
                float2(spacing) - cell
            );
            const float2 lineAA = max(
                fwidth(viewPoint),
                float2(0.001)
            );
            const float vertical = 1.0 - smoothstep(
                uniforms.lineHalfWidthPoints - lineAA.x,
                uniforms.lineHalfWidthPoints + lineAA.x,
                lineDistance.x
            );
            const float horizontal = 1.0 - smoothstep(
                uniforms.lineHalfWidthPoints - lineAA.y,
                uniforms.lineHalfWidthPoints + lineAA.y,
                lineDistance.y
            );

            float mask = 0.0;
            const float opacity = \(TraceGridContrastPolicy.opacity);
            if (uniforms.style == 1) {
                const float distanceToCenter = length(
                    cell - float2(spacing * 0.5)
                );
                const float dotAA = max(
                    fwidth(distanceToCenter),
                    0.001
                );
                mask = 1.0 - smoothstep(
                    uniforms.dotRadiusPoints - dotAA,
                    uniforms.dotRadiusPoints + dotAA,
                    distanceToCenter
                );
            } else if (uniforms.style == 2) {
                mask = max(vertical, horizontal);
            } else if (uniforms.style == 3) {
                mask = horizontal;
            } else if (uniforms.style == 4) {
                mask = vertical;
            }

            const float alpha = saturate(mask * opacity) * base.a;
            const float luminance = dot(
                base.rgb,
                float3(
                    \(TraceGridContrastPolicy.redWeight),
                    \(TraceGridContrastPolicy.greenWeight),
                    \(TraceGridContrastPolicy.blueWeight)
                )
            );
            const float3 adaptiveGridColor =
                luminance
                    > \(TraceGridContrastPolicy.lightBackgroundThreshold)
                ? float3(0.0)
                : float3(1.0);
            return float4(
                adaptiveGridColor * alpha,
                alpha
            );
        }
        """
}
