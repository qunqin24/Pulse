// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Ported from Open Bot Avatar's fluffy renderer (`dist/dom/fluffy/renderer.js`,
// https://github.com/DominikScholz/open-bot-avatar, v0.4.0), Copyright (c)
// 2026 Dominik Scholz, MIT License — see THIRD_PARTY_NOTICES.md.
import CoreGraphics
import Foundation
import Metal

/// How much of a coat to draw at a scale, as the original's `fluffyDetail`
/// decides it (a test checks this port against the bundled one).
struct FluffyDetail: Equatable, Sendable {
    /// Shells of pile between the body and the strands, at full detail.
    static let shellsInFull = 5
    /// Pixels per viewBox unit from which a coat is drawn in full.
    static let fullDetail = 2.56
    /// The mesh stores its roots in this many passes (`ROOT_PASSES`).
    static let rootPasses = 8

    var shells: Int
    var strandPasses: Int
    var fineSockets: Bool

    init(shells: Int, strandPasses: Int, fineSockets: Bool) {
        self.shells = shells
        self.strandPasses = strandPasses
        self.fineSockets = fineSockets
    }

    /// At `scale` device pixels per viewBox unit.
    init(scale: Double) {
        let detail = min(1, scale / Self.fullDetail)
        shells = max(2, Int((Double(Self.shellsInFull) * detail).rounded(.up)))
        strandPasses = max(Self.rootPasses / 4, Int((Double(Self.rootPasses) * detail.squareRoot()).rounded(.up)))
        fineSockets = detail > 0.75
    }

    /// `rootsIn`: how many of `total` roots the first `passes` passes hold.
    static func roots(in total: Int, passes: Int) -> Int {
        (0..<passes).reduce(0) { count, pass in count + max(0, (total - pass + rootPasses - 1) / rootPasses) }
    }
}

/// The view's rotation, as `liveFrame` reports it in `surface.view`.
struct FluffyView: Equatable, Sendable {
    var cY, sY, cP, sP, facing: Double
    static let front = FluffyView(cY: 1, sY: 0, cP: 1, sP: 0, facing: 1)
}

/// One eye on the body's surface, with what the original's `socketRegion`
/// and `socketKey` say of it.
struct FluffyEye: Equatable, Sendable {
    var mark: FluffyTextures.EyeMark
    var region: FluffyTextures.SocketRegion
    var key: String
    var dx, dy: Double
}

/// What a coat is dyed and how its eyes sit.
struct FluffyLook: Equatable, Sendable {
    var color: SIMD3<UInt8>
    var ink: SIMD3<UInt8>
    var eyes: [FluffyEye]

    /// `#rrggbb` as bytes.
    static func bytes(hex: String) -> SIMD3<UInt8>? {
        guard let ink = RobotInk(hex: hex) else { return nil }
        let byte = { (value: Double) in UInt8(max(0, min(255, (value * 255).rounded()))) }
        return SIMD3(byte(ink.red), byte(ink.green), byte(ink.blue))
    }
}

/// A rendered coat: an image of the square `radius` either side of
/// (`cx`, `cy`) in the figure's viewBox units.
struct FluffyImage: @unchecked Sendable {
    let image: CGImage
    let cx: Double
    let cy: Double
    let radius: Double
}

/// One shape's coat on the GPU: the surface for the body and its shells, and
/// the roots its strands grow from, cut to the detail it was uploaded for.
final class FluffyGeometry: @unchecked Sendable {
    let surface: MTLBuffer
    let indices: MTLBuffer
    let indexCount: Int
    let roots: MTLBuffer?
    /// Roots in `roots`: the first `strandPasses` passes of `strandCount`.
    let strandCount: Int
    let strandPasses: Int
    let fineSockets: Bool
    let cx, cy: Double
    let extent: SIMD3<Float>
    let radius: Double
    let eyeZ: (Double, Double)
    var usedAt: TimeInterval = 0

    init(surface: MTLBuffer, indices: MTLBuffer, indexCount: Int, roots: MTLBuffer?, strandCount: Int,
         strandPasses: Int, fineSockets: Bool, cx: Double, cy: Double, extent: SIMD3<Float>, radius: Double,
         eyeZ: (Double, Double)) {
        self.surface = surface
        self.indices = indices
        self.indexCount = indexCount
        self.roots = roots
        self.strandCount = strandCount
        self.strandPasses = strandPasses
        self.fineSockets = fineSockets
        self.cx = cx
        self.cy = cy
        self.extent = extent
        self.radius = radius
        self.eyeZ = eyeZ
    }

    func covers(_ detail: FluffyDetail) -> Bool {
        (fineSockets || !detail.fineSockets) && strandPasses >= detail.strandPasses
    }

    /// GPU memory held, bytes.
    var bytes: Int { surface.length + indices.length + (roots?.length ?? 0) }
}

/// Open Bot Avatar's fluffy renderer, from WebGL2 to Metal: the same passes
/// (body, shells, strands), the same level of detail by pixel size, the same
/// textures, and the image reused while the view has hardly moved.
///
/// One for the app (`shared`): one device, one queue, one pipeline, and the
/// textures every coat samples. Not thread-safe — `BotAvatarEngine` calls it
/// only on its own queue, as it does the script.
///
/// Nil where Metal is unavailable or the shaders do not compile; the robot is
/// then drawn flat, as the original does without WebGL2.
final class FluffyRenderer: @unchecked Sendable {
    static let shared: FluffyRenderer? = FluffyRenderer()

    /// Largest and smallest image, pixels a side.
    static let maxPixels = 1024
    static let minPixels = 32
    /// Room around the body for the pile, viewBox units.
    static let pileReach = 4.0
    /// The eyes sit this far above their host's surface at most.
    static let socketRise = 0.8
    /// A view this close to the last one drawn, in pixels of surface
    /// movement, reuses its image.
    static let sameView = 0.1
    static let rampSize = 96

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let clampLinear: MTLSamplerState
    private let pileSampler: MTLSamplerState
    private let brushedSampler: MTLSamplerState
    private let pile: MTLTexture
    private let brushedPile: MTLTexture
    private let dyeRamp: MTLTexture
    private let eyeField: MTLTexture
    private let sampleCount: Int

    /// Render targets by pixel size; a rail's rings share one or two.
    private struct Target {
        let colour: MTLTexture
        let depth: MTLTexture
        let resolved: MTLTexture
        let readback: MTLBuffer
    }

    private var targets: [Int: Target] = [:]
    /// What the eye texture holds, by slot.
    private var tilesShown: [String] = ["", ""]
    /// Distance tiles by contour: both eyes usually share one, and a figure
    /// returns to the same few.
    private var tiles: [String: [UInt8]] = [:]
    private var tileOrder: [String] = []
    /// What the dye texture holds.
    private var dyeShown: SIMD3<UInt8>?
    private var ramps: [SIMD3<UInt8>: [UInt8]] = [:]

    /// What a drawing last rendered, so a frame whose view hardly moved
    /// reuses the image (the original keeps one; Pulse keeps one per ring).
    private struct Shown {
        let geometry: ObjectIdentifier
        let pixels: Int
        let look: FluffyLook
        let regions: [Float]
        let view: FluffyView
        let image: FluffyImage
    }

    private var shown: [String: Shown] = [:]

    private init?() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue = device.makeCommandQueue()
        else { return nil }
        let options = MTLCompileOptions()
        // GLSL's highp: no fast-math shortcuts in the trigonometry the
        // strands are combed with.
        if #available(macOS 15.0, *) {
            options.mathMode = .safe
        } else {
            options.fastMathEnabled = false
        }
        let sampleCount = device.supportsTextureSampleCount(4) ? 4 : 1
        let descriptor = MTLRenderPipelineDescriptor()
        do {
            let library = try device.makeLibrary(source: FluffyShaders.source, options: options)
            descriptor.vertexFunction = library.makeFunction(name: "fluffyVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "fluffyFragment")
        } catch {
            NSLog("Pulse: the fluffy shaders did not compile, drawing flat: %@", "\(error)")
            return nil
        }
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = sampleCount
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = true
        guard
            let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
            let depthState = device.makeDepthStencilState(descriptor: depth)
        else { return nil }

        func sampler(_ configure: (MTLSamplerDescriptor) -> Void) -> MTLSamplerState? {
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            configure(descriptor)
            return device.makeSamplerState(descriptor: descriptor)
        }
        // WebGL's defaults where the original sets nothing: repeat, and
        // nearest-mipmap-linear for the fibre tile.
        guard
            let clampLinear = sampler({
                $0.sAddressMode = .clampToEdge
                $0.tAddressMode = .clampToEdge
            }),
            let pileSampler = sampler({
                $0.minFilter = .nearest
                $0.mipFilter = .linear
                $0.sAddressMode = .repeat
                $0.tAddressMode = .repeat
            }),
            let brushedSampler = sampler({
                $0.mipFilter = .linear
                $0.sAddressMode = .repeat
                $0.tAddressMode = .repeat
                $0.rAddressMode = .repeat
            })
        else { return nil }

        func texture(_ type: MTLTextureType, _ format: MTLPixelFormat, _ width: Int, _ height: Int, depth: Int = 1,
                     mipmapped: Bool = false) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = type
            descriptor.pixelFormat = format
            descriptor.width = width
            descriptor.height = height
            descriptor.depth = depth
            if mipmapped {
                descriptor.mipmapLevelCount = Int(log2(Double(max(width, height, depth)))) + 1
            }
            descriptor.usage = .shaderRead
            return device.makeTexture(descriptor: descriptor)
        }
        let side = 64
        guard
            let pile = texture(.type2D, .r8Unorm, 128, 128, mipmapped: true),
            let brushedPile = texture(.type3D, .r8Unorm, side, side, depth: side, mipmapped: true),
            let dyeRamp = texture(.type2D, .rgba8Unorm, Self.rampSize, 1),
            let eyeField = texture(.type2D, .r8Unorm, 2 * FluffyTextures.socketTile, FluffyTextures.socketTile)
        else { return nil }
        let fibres = FluffyTextures.fiberTile()
        pile.replace(region: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0, withBytes: fibres, bytesPerRow: 128)
        let roots = FluffyTextures.rootVolume(side: side)
        brushedPile.replace(region: MTLRegionMake3D(0, 0, 0, side, side, side), mipmapLevel: 0, slice: 0,
                            withBytes: roots, bytesPerRow: side, bytesPerImage: side * side)
        eyeField.replace(region: MTLRegionMake2D(0, 0, eyeField.width, eyeField.height), mipmapLevel: 0,
                         withBytes: [UInt8](repeating: 255, count: eyeField.width * eyeField.height),
                         bytesPerRow: eyeField.width)
        guard
            let commands = queue.makeCommandBuffer(),
            let blit = commands.makeBlitCommandEncoder()
        else { return nil }
        blit.generateMipmaps(for: pile)
        blit.generateMipmaps(for: brushedPile)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed else { return nil }

        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.depthState = depthState
        self.clampLinear = clampLinear
        self.pileSampler = pileSampler
        self.brushedSampler = brushedSampler
        self.pile = pile
        self.brushedPile = brushedPile
        self.dyeRamp = dyeRamp
        self.eyeField = eyeField
        self.sampleCount = sampleCount
    }

    // MARK: - Meshes

    /// Uploads what `detail` draws of a mesh `buildMesh` made: the coarse
    /// surface or the one refined round the eyes, and the strands' first
    /// passes. Copies out of the script's typed arrays, which may go after.
    func upload(_ mesh: FluffyMeshArrays, detail: FluffyDetail) -> FluffyGeometry? {
        let triangles = detail.fineSockets ? mesh.fine : mesh.coarse
        guard triangles.count > 0, triangles.start + triangles.count <= mesh.indices.count else { return nil }
        let indices = mesh.indices[triangles.start..<(triangles.start + triangles.count)]
        // The refined vertices follow the grid's, so the coarse surface needs
        // only the vertices up to its largest index.
        let vertexCount = detail.fineSockets ? mesh.vertices.count / 6 : Int(indices.max() ?? 0) + 1
        guard vertexCount * 6 <= mesh.vertices.count else { return nil }
        let strandCount = mesh.roots.count / 8
        let rootCount = FluffyDetail.roots(in: strandCount, passes: detail.strandPasses)
        guard
            let surface = mesh.vertices.withUnsafeBytes({ bytes in
                device.makeBuffer(bytes: bytes.baseAddress!, length: vertexCount * 24, options: .storageModeShared)
            }),
            let indexBuffer = indices.withUnsafeBytes({ bytes in
                device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
            })
        else { return nil }
        let roots = rootCount == 0 ? nil : mesh.roots.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: rootCount * 32, options: .storageModeShared)
        }
        let rx = (mesh.bounds.maxX - mesh.bounds.minX) / 2, ry = (mesh.bounds.maxY - mesh.bounds.minY) / 2
        let rz = mesh.halfDepth
        return FluffyGeometry(
            surface: surface, indices: indexBuffer, indexCount: indices.count, roots: roots,
            strandCount: strandCount, strandPasses: detail.strandPasses, fineSockets: detail.fineSockets,
            cx: mesh.bounds.minX + rx, cy: mesh.bounds.minY + ry, extent: SIMD3(Float(rx), Float(ry), Float(rz)),
            radius: ((rx * rx + ry * ry + rz * rz).squareRoot() + Self.pileReach).rounded(.up), eyeZ: mesh.eyeZ
        )
    }

    // MARK: - Drawing

    /// Lets go of what a drawing last rendered.
    func forget(key: String) {
        shown[key] = nil
    }

    /// Lets go of everything a drawing could reuse; for when no figure is
    /// fluffy any more.
    func releaseAll() {
        shown.removeAll()
        targets.removeAll()
        tiles.removeAll()
        tileOrder.removeAll()
    }

    /// The coat of `geometry` under `view` at `scale` device pixels per
    /// viewBox unit, or nil if the GPU fails it. `ramp` gives the original's
    /// dye ramp for a colour, 96 RGBA texels. `key` names the drawing, whose
    /// last image is reused while its view has hardly moved.
    func render(_ geometry: FluffyGeometry, view: FluffyView, look: FluffyLook, scale: Double, key: String?,
                ramp: (SIMD3<UInt8>) -> [UInt8]?) -> FluffyImage? {
        geometry.usedAt = ProcessInfo.processInfo.systemUptime
        let radius = geometry.radius
        let pixels = min(Self.maxPixels, max(Self.minPixels, Int((2 * radius * scale).rounded(.up))))

        // The sockets: where each eye is, and its contour's distance tile.
        var regions = [Float](repeating: 0, count: 8)
        var sizes = [Float](repeating: 0, count: 4)
        for (slot, eye) in look.eyes.prefix(2).enumerated() {
            let z = slot == 0 ? geometry.eyeZ.0 : geometry.eyeZ.1
            regions.replaceSubrange((4 * slot)..<(4 * slot + 4), with: [
                Float(eye.region.cx + eye.dx), Float(eye.region.cy + eye.dy), Float(eye.region.span),
                Float(z + Self.socketRise),
            ])
            sizes[2 * slot] = Float(eye.region.w)
            sizes[2 * slot + 1] = Float(eye.region.h * eye.region.exposed)
        }

        // Root motion is composited by the painter, so only a turn of the
        // surface or a change of look needs a new image.
        if let key, let last = shown[key], last.geometry == ObjectIdentifier(geometry), last.pixels == pixels,
           last.look.color == look.color, last.look.ink == look.ink,
           last.look.eyes.map(\.key) == look.eyes.map(\.key), last.regions == regions {
            let turn = abs(view.cY - last.view.cY) + abs(view.sY - last.view.sY) + abs(view.sP - last.view.sP)
                + abs(view.cP - last.view.cP)
            if turn < Self.sameView / (radius * scale) { return last.image }
        }

        for (slot, eye) in look.eyes.prefix(2).enumerated() where tilesShown[slot] != eye.key {
            let tile = tile(for: eye)
            eyeField.replace(region: MTLRegionMake2D(slot * FluffyTextures.socketTile, 0, FluffyTextures.socketTile,
                                                     FluffyTextures.socketTile),
                             mipmapLevel: 0, withBytes: tile, bytesPerRow: FluffyTextures.socketTile)
            tilesShown[slot] = eye.key
        }
        if dyeShown != look.color {
            guard let row = rampBytes(look.color, ramp: ramp) else { return nil }
            dyeRamp.replace(region: MTLRegionMake2D(0, 0, Self.rampSize, 1), mipmapLevel: 0, withBytes: row,
                            bytesPerRow: Self.rampSize * 4)
            dyeShown = look.color
        }

        guard let target = target(pixels: pixels), let commands = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target.colour
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        if sampleCount > 1 {
            pass.colorAttachments[0].resolveTexture = target.resolved
            pass.colorAttachments[0].storeAction = .multisampleResolve
        } else {
            pass.colorAttachments[0].storeAction = .store
        }
        pass.depthAttachment.texture = target.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(pixels), height: Double(pixels),
                                        znear: 0, zfar: 1))
        encoder.setVertexBuffer(geometry.surface, offset: 0, index: 0)
        encoder.setVertexBuffer(geometry.roots ?? geometry.surface, offset: 0, index: 1)
        encoder.setVertexTexture(eyeField, index: 0)
        encoder.setVertexSamplerState(clampLinear, index: 0)
        encoder.setFragmentTexture(eyeField, index: 0)
        encoder.setFragmentTexture(pile, index: 1)
        encoder.setFragmentTexture(brushedPile, index: 2)
        encoder.setFragmentTexture(dyeRamp, index: 3)
        encoder.setFragmentSamplerState(clampLinear, index: 0)
        encoder.setFragmentSamplerState(pileSampler, index: 1)
        encoder.setFragmentSamplerState(brushedSampler, index: 2)

        let detail = FluffyDetail(scale: scale)
        var uniforms = FluffyUniforms(geometry: geometry, view: view, look: look, regions: regions, sizes: sizes)
        func set(pass: Int, shell: Float = 0, strandWidth: Float = 1) {
            uniforms.params = SIMD4(Float(radius), shell, strandWidth, Float(pass))
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<FluffyUniforms>.stride, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FluffyUniforms>.stride, index: 0)
        }
        set(pass: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: geometry.indexCount, indexType: .uint32,
                                      indexBuffer: geometry.indices, indexBufferOffset: 0)
        for layer in 1...detail.shells {
            set(pass: 1, shell: Float(layer) / Float(detail.shells))
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: geometry.indexCount, indexType: .uint32,
                                          indexBuffer: geometry.indices, indexBufferOffset: 0)
        }
        let passes = min(detail.strandPasses, geometry.strandPasses)
        let strands = FluffyDetail.roots(in: geometry.strandCount, passes: passes)
        if strands > 0, geometry.roots != nil {
            set(pass: 2, strandWidth: Float(FluffyDetail.rootPasses) / Float(passes))
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 8, instanceCount: strands)
        }
        encoder.endEncoding()
        guard let blit = commands.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: target.resolved, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: pixels, height: pixels, depth: 1), to: target.readback,
                  destinationOffset: 0, destinationBytesPerRow: pixels * 4, destinationBytesPerImage: pixels * pixels * 4)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed, let image = Self.image(target.readback, pixels: pixels) else { return nil }

        let result = FluffyImage(image: image, cx: geometry.cx, cy: geometry.cy, radius: radius)
        if let key {
            shown[key] = Shown(geometry: ObjectIdentifier(geometry), pixels: pixels, look: look, regions: regions,
                               view: view, image: result)
        }
        return result
    }

    private func tile(for eye: FluffyEye) -> [UInt8] {
        if let tile = tiles[eye.key] { return tile }
        let tile = FluffyTextures.socketTile(eye.mark, region: eye.region)
        if tileOrder.count >= 48 { tiles[tileOrder.removeFirst()] = nil }
        tiles[eye.key] = tile
        tileOrder.append(eye.key)
        return tile
    }

    private func rampBytes(_ colour: SIMD3<UInt8>, ramp: (SIMD3<UInt8>) -> [UInt8]?) -> [UInt8]? {
        if let row = ramps[colour] { return row }
        guard let row = ramp(colour), row.count == Self.rampSize * 4 else { return nil }
        if ramps.count >= 64 { ramps.removeAll() }
        ramps[colour] = row
        return row
    }

    private func target(pixels: Int) -> Target? {
        if let target = targets[pixels] { return target }
        func texture(_ format: MTLPixelFormat, samples: Int, usage: MTLTextureUsage) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: pixels,
                                                                      height: pixels, mipmapped: false)
            descriptor.textureType = samples > 1 ? .type2DMultisample : .type2D
            descriptor.sampleCount = samples
            descriptor.storageMode = .private
            descriptor.usage = usage
            return device.makeTexture(descriptor: descriptor)
        }
        guard
            let resolved = texture(.rgba8Unorm, samples: 1, usage: .renderTarget),
            let colour = sampleCount > 1 ? texture(.rgba8Unorm, samples: sampleCount, usage: .renderTarget) : resolved,
            let depth = texture(.depth32Float, samples: sampleCount, usage: .renderTarget),
            let readback = device.makeBuffer(length: pixels * pixels * 4, options: .storageModeShared)
        else { return nil }
        // Rings of a rail share one or two sizes; a zoom or a preview adds
        // a few. More than that is a session that changed size often.
        if targets.count >= 6 { targets.removeAll() }
        let target = Target(colour: colour, depth: depth, resolved: resolved, readback: readback)
        targets[pixels] = target
        return target
    }

    /// Premultiplied RGBA, as WebGL's canvas holds it, in sRGB.
    private static func image(_ buffer: MTLBuffer, pixels: Int) -> CGImage? {
        let data = Data(bytes: buffer.contents(), count: pixels * pixels * 4)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}

/// The shaders' `Uniforms`, all `float4`s so the layouts agree.
private struct FluffyUniforms {
    var view0, view1, view2: SIMD4<Float>
    var pivot, extent: SIMD4<Float>
    var eyeRegion0, eyeRegion1: SIMD4<Float>
    var eyeSize: SIMD4<Float>
    var color, ink: SIMD4<Float>
    var params: SIMD4<Float> = .zero

    init(geometry: FluffyGeometry, view v: FluffyView, look: FluffyLook, regions: [Float], sizes: [Float]) {
        // Rotation by yaw, then pitch, as columns.
        view0 = SIMD4(Float(v.cY), Float(v.sY * v.sP), Float(-v.sY * v.cP), 0)
        view1 = SIMD4(0, Float(v.cP), Float(v.sP), 0)
        view2 = SIMD4(Float(v.sY), Float(-v.cY * v.sP), Float(v.facing), 0)
        pivot = SIMD4(Float(geometry.cx), Float(geometry.cy), 0, 0)
        extent = SIMD4(geometry.extent, 1)
        eyeRegion0 = SIMD4(regions[0], regions[1], regions[2], regions[3])
        eyeRegion1 = SIMD4(regions[4], regions[5], regions[6], regions[7])
        eyeSize = SIMD4(sizes[0], sizes[1], sizes[2], sizes[3])
        color = SIMD4(SIMD3<Float>(look.color) / 255, 1)
        ink = SIMD4(SIMD3<Float>(look.ink) / 255, 1)
    }
}

/// A mesh as `buildMesh` returns it, copied out of JavaScriptCore.
struct FluffyMeshArrays: Sendable {
    /// Position and normal per vertex.
    var vertices: [Float]
    var indices: [UInt32]
    /// Position, normal and two random numbers per root, pass by pass.
    var roots: [Float]
    var coarse: (start: Int, count: Int)
    var fine: (start: Int, count: Int)
    var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)
    var halfDepth: Double
    var eyeZ: (Double, Double)
}
