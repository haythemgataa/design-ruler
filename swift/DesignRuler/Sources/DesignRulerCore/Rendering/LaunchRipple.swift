import AppKit
import Metal
import MetalKit
import QuartzCore

/// Launch animation: a frosted, refracting ripple spreads from the hint bar across the frozen
/// screenshot. A Metal shader draws it into a CAMetalLayer inside the content layer (so it
/// follows zoom and pan like the screenshot); outside the ring the layer is transparent and the
/// screenshot shows through. The layer is removed when the animation ends.
///
/// The shader is compiled from inline source at runtime: Raycast ships only the binary, so there
/// can be no .metal / .metallib resources (see "NO Bundle.module Resources").
package final class LaunchRippleRenderer {
    package static let shared = LaunchRippleRenderer()

    /// Give up on the animation if the shader or texture isn't ready this long after launch:
    /// a ripple that starts late reads as a glitch, not a launch animation.
    static let maxStartDelay: CFTimeInterval = 0.25

    let device: MTLDevice?
    let queue: MTLCommandQueue?
    let textureLoader: MTKTextureLoader?
    private(set) var pipeline: MTLRenderPipelineState?
    private var isPreparing = false
    private var pending: [() -> Void] = []

    private init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        textureLoader = device.map { MTKTextureLoader(device: $0) }
    }

    /// Compile the shader off the main thread. Called at the start of every session so it runs
    /// in parallel with screen capture; a no-op once compiled.
    package func prepare() {
        guard pipeline == nil, !isPreparing, let device else { return }
        isPreparing = true
        DispatchQueue.global(qos: .userInitiated).async {
            var state: MTLRenderPipelineState?
            if let library = try? device.makeLibrary(source: Self.shaderSource, options: nil) {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "rippleVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "rippleFragment")
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                state = try? device.makeRenderPipelineState(descriptor: descriptor)
            }
            DispatchQueue.main.async {
                self.pipeline = state
                self.isPreparing = false
                let waiting = self.pending
                self.pending.removeAll()
                if state != nil { waiting.forEach { $0() } }
            }
        }
    }

    /// Run `body` on the main thread once the pipeline is compiled. Dropped if compiling failed.
    func whenReady(_ body: @escaping () -> Void) {
        if pipeline != nil {
            body()
        } else if isPreparing {
            pending.append(body)
        }
    }

    // Look tuned in the browser prototype: ripple from the hint bar, 110% band, 60% distortion,
    // 80% color fringe, 20px blur on a 425px-tall preview, 50% tint, 10% rim glow.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    constant float BAND_WIDTH = 0.66;  // fraction of the distance to the farthest corner
    constant float DISTORTION = 0.6;
    constant float CHROMA = 0.8;
    constant float BLUR = 0.047;       // blur radius as a fraction of screen height
    constant float TINT = 0.5;
    constant float GLOW = 0.1;

    struct VOut { float4 position [[position]]; float2 uv; };

    struct Params {
        float2 res;      // texture size in pixels
        float2 center;   // ripple origin, uv with y up
        float t;         // linear progress 0...1
        float e;         // eased progress 0...1
    };

    // One oversized triangle covering the screen; uv has a top-left origin like the CGImage.
    vertex VOut rippleVertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = float2(p.x, 1.0 - p.y);
        return o;
    }

    // Shader math works with y up (like the prototype); flip back when sampling.
    static float2 texCoord(float2 up) { return clamp(float2(up.x, 1.0 - up.y), 0.0, 1.0); }

    fragment float4 rippleFragment(VOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]],
                                   constant Params &P [[buffer(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear, mip_filter::linear);
        float asp = P.res.x / P.res.y;
        float2 up = float2(in.uv.x, 1.0 - in.uv.y);
        float2 p = float2(up.x * asp, up.y);
        float2 c = float2(P.center.x * asp, P.center.y);
        float2 v = p - c;
        float d = length(v);
        float2 dir = v / max(d, 1e-4);
        float endR = length(float2(max(c.x, asp - c.x), 1.0 - c.y));

        // Ring radius travels past the farthest corner; x is the position across the band.
        float w = BAND_WIDTH * endR;
        float r = -w * 0.3 + (endR + w * 1.3) * P.e;
        float x = (d - r) / w;
        float env = min(1.0, P.t * 8.0) * (1.0 - smoothstep(0.9, 1.0, P.t));

        float frost = (1.0 - smoothstep(0.0, 0.12, x)) * smoothstep(-1.0, 0.0, x) * env;
        float y = (x + 0.08) / 0.16;
        float disp = DISTORTION * 0.05 * (-y * exp(-y * y)) * env;
        float xa = (d - r) / endR;
        float rim = exp(-xa * xa / (0.006 * 0.006)) * env;

        // Outside the band: transparent, the content layer's screenshot shows through.
        if (frost < 0.001 && abs(disp) < 0.00005 && rim < 0.001) {
            return float4(0.0);
        }

        // Refraction along the ring normal, split per channel for the color fringe.
        float2 o = float2(dir.x / asp, dir.y) * disp;
        float ch = CHROMA * 0.6;
        float2 uR = up + o * (1.0 + ch);
        float2 uG = up + o;
        float2 uB = up + o * (1.0 - ch);

        // Frost blur: 16-tap golden-angle disk, sampled from mips so large radii stay smooth.
        float br = BLUR * frost;
        float lod = log2(max(1.0, br * P.res.y / 4.0));
        float3 col = float3(0.0);
        for (int i = 0; i < 16; i++) {
            float fi = float(i);
            float a = fi * 2.39996;
            float rad = sqrt((fi + 0.5) / 16.0);
            float2 k = float2(cos(a) / asp, sin(a)) * rad * br;
            col.r += tex.sample(s, texCoord(uR + k), level(lod)).r;
            col.g += tex.sample(s, texCoord(uG + k), level(lod)).g;
            col.b += tex.sample(s, texCoord(uB + k), level(lod)).b;
        }
        col /= 16.0;

        float gray = dot(col, float3(0.299, 0.587, 0.114));
        float3 frosted = mix(col, float3(gray), 0.55) * 0.82 + float3(0.80, 0.90, 1.0) * 0.28;
        col = mix(col, frosted, frost * TINT);

        float ang = atan2(dir.y, dir.x) / 6.2832 + P.t * 0.6;
        float3 hue = 0.55 + 0.45 * cos(6.2832 * (ang + float3(0.0, 0.33, 0.67)));
        col += rim * GLOW * hue * 0.7;

        return float4(col, 1.0);
    }
    """
}

/// Matches `Params` in the shader.
private struct RippleParams {
    var res: SIMD2<Float>
    var center: SIMD2<Float>
    var t: Float
    var e: Float
}

/// One window's ripple. Loads the screenshot into a mipmapped texture off the main thread, then
/// renders one frame per display refresh until the animation ends or `cancel()` is called.
package final class LaunchRipple: NSObject {
    private let screenshot: CGImage
    private let center: SIMD2<Float>
    private let requestTime = CACurrentMediaTime()
    private var metalLayer: CAMetalLayer?
    private var texture: MTLTexture?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var isFinished = false

    /// `center` is the ripple origin in unit coordinates with y up (0,0 = bottom-left).
    package init(screenshot: CGImage, center: CGPoint) {
        self.screenshot = screenshot
        self.center = SIMD2(Float(center.x), Float(center.y))
    }

    /// Start the ripple inside `contentLayer`, which holds the screenshot.
    /// `view` drives the display link (it must be in a window).
    package func start(in contentLayer: CALayer, view: NSView) {
        let renderer = LaunchRippleRenderer.shared
        guard let loader = renderer.textureLoader else { return finish() }
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .allocateMipmaps: true,
            .generateMipmaps: true,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
        ]
        loader.newTexture(cgImage: screenshot, options: options) { [weak self, weak contentLayer, weak view] texture, _ in
            DispatchQueue.main.async {
                renderer.whenReady {
                    guard let self, !self.isFinished, let contentLayer, let view, let texture,
                          CACurrentMediaTime() - self.requestTime < LaunchRippleRenderer.maxStartDelay else {
                        self?.finish()
                        return
                    }
                    self.begin(texture: texture, in: contentLayer, view: view)
                }
            }
        }
    }

    private func begin(texture: MTLTexture, in contentLayer: CALayer, view: NSView) {
        self.texture = texture
        let duration = DesignTokens.Animation.launchRipple
        let layer = CAMetalLayer()
        layer.device = LaunchRippleRenderer.shared.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.colorspace = screenshot.colorSpace  // present the pixels exactly as the content layer does
        layer.contentsScale = contentLayer.contentsScale
        layer.frame = contentLayer.bounds
        layer.drawableSize = CGSize(width: texture.width, height: texture.height)

        // The shader is already the identity at t = 0 and t = 1; the opacity ramp also hides any
        // color-space mismatch with the content layer at the handoffs.
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.08, 0.88, 1]
        fade.duration = duration
        layer.opacity = 0
        layer.add(fade, forKey: "launchFade")

        CATransaction.instant {
            contentLayer.addSublayer(layer)
        }
        metalLayer = layer

        startTime = CACurrentMediaTime()
        let link = view.displayLink(target: self, selector: #selector(step))
        // A full-Retina frame costs up to ~9ms of GPU time; 60fps keeps ProMotion screens from dropping frames.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        step()
    }

    @objc private func step() {
        let t = (CACurrentMediaTime() - startTime) / DesignTokens.Animation.launchRipple
        if t >= 1 { return finish() }
        render(t: Float(t))
    }

    private func render(t: Float) {
        guard let layer = metalLayer, let texture,
              let pipeline = LaunchRippleRenderer.shared.pipeline,
              let drawable = layer.nextDrawable(),
              let commands = LaunchRippleRenderer.shared.queue?.makeCommandBuffer() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }

        var params = RippleParams(
            res: SIMD2(Float(texture.width), Float(texture.height)),
            center: center, t: t, e: 1 - pow(1 - t, 3)  // easeOut cubic, as in the prototype
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<RippleParams>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    /// Stop immediately and remove the layer (exit, or a new ripple replacing this one).
    package func cancel() {
        finish()
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        displayLink?.invalidate()
        displayLink = nil
        if let layer = metalLayer {
            CATransaction.instant { layer.removeFromSuperlayer() }
        }
        metalLayer = nil
        texture = nil
    }
}
