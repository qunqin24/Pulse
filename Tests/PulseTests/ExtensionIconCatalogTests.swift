import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Pulse

private struct IconSandbox {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ExtensionIconTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func add(_ id: String = "acme", icon: Any? = nil) throws -> URL {
        let folder = root.appending(path: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var manifest: [String: Any] = ["schemaVersion": 1, "id": id, "name": id, "executable": "run"]
        if let icon { manifest["icon"] = icon }
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: "pulse-extension.json"))
        let executable = folder.appending(path: "run")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return folder
    }

    static func png(width: Int = 16, height: Int = 12, red: CGFloat = 0.8) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let image = try #require(context.makeImage())
        let data = try #require(CFDataCreateMutable(nil, 0))
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

@Suite("Extension icon discovery")
struct ExtensionIconCatalogTests {
    @Test("A fresh extension loads its own PNG without any application resource overlay")
    func loadsLocalPNG() throws {
        let sandbox = try IconSandbox()
        defer { sandbox.remove() }
        let folder = try sandbox.add(icon: "icon.png")
        let bytes = try IconSandbox.png()
        try bytes.write(to: folder.appending(path: "icon.png"))
        let scan = ExtensionCatalog.scan(in: sandbox.root)
        #expect(scan.problems.isEmpty)
        #expect(scan.extensions.first?.iconData == bytes)
    }

    @Test("An old manifest still works with the generic mark")
    func oldManifest() throws {
        let sandbox = try IconSandbox()
        defer { sandbox.remove() }
        try sandbox.add()
        let scan = ExtensionCatalog.scan(in: sandbox.root)
        #expect(scan.extensions.count == 1)
        #expect(scan.extensions.first?.iconData == nil)
    }

    @Test("An icon cannot point outside its own extension, even through a symlink")
    func rejectsOutsidePaths() throws {
        let sandbox = try IconSandbox()
        defer { sandbox.remove() }
        let outside = sandbox.root.appending(path: "outside.png")
        try IconSandbox.png().write(to: outside)
        try sandbox.add("absolute", icon: outside.path)
        try sandbox.add("relative", icon: "../outside.png")
        let linked = try sandbox.add("linked", icon: "icon.png")
        try FileManager.default.createSymbolicLink(at: linked.appending(path: "icon.png"), withDestinationURL: outside)
        let scan = ExtensionCatalog.scan(in: sandbox.root)
        #expect(scan.problems.isEmpty)
        #expect(scan.extensions.count == 3)
        #expect(scan.extensions.allSatisfy { $0.iconData == nil })
    }

    @Test("Missing, non-file, non-image and remote icons do not disable quota readings")
    func invalidIconsFallBack() throws {
        let sandbox = try IconSandbox()
        defer { sandbox.remove() }
        try sandbox.add("missing", icon: "missing.png")
        let garbage = try sandbox.add("garbage", icon: "icon.png")
        try Data("not a PNG".utf8).write(to: garbage.appending(path: "icon.png"))
        let directory = try sandbox.add("directory", icon: "icon.png")
        try FileManager.default.createDirectory(at: directory.appending(path: "icon.png"), withIntermediateDirectories: false)
        try sandbox.add("remote", icon: "https://example.invalid/icon.png")
        let scan = ExtensionCatalog.scan(in: sandbox.root)
        #expect(scan.extensions.count == 4)
        #expect(scan.problems.isEmpty)
        #expect(scan.extensions.allSatisfy { $0.iconData == nil })
    }

    @Test("Invalid optional icon field types leave the extension usable")
    func invalidFieldTypes() throws {
        let sandbox = try IconSandbox()
        defer { sandbox.remove() }
        let values: [Any] = [true, 42, ["path": "icon.png"], NSNull()]
        for (index, value) in values.enumerated() {
            try sandbox.add("wrong-type-\(index)", icon: value)
        }
        let scan = ExtensionCatalog.scan(in: sandbox.root)
        #expect(scan.extensions.count == values.count)
        #expect(scan.problems.isEmpty)
        #expect(scan.extensions.allSatisfy { $0.iconData == nil })
    }

    @Test("Oversized files and oversized image dimensions fall back before rendering")
    func enforcesImageBudgets() throws {
        let sandbox = try IconSandbox()
        defer { sandbox.remove() }
        let file = try sandbox.add("file-budget", icon: "icon.png")
        try Data(repeating: 0, count: ExtensionCatalog.iconByteCeiling + 1).write(to: file.appending(path: "icon.png"))
        let pixels = try sandbox.add("pixel-budget", icon: "icon.png")
        try IconSandbox.png(width: ExtensionCatalog.iconDimensionCeiling + 1, height: 1)
            .write(to: pixels.appending(path: "icon.png"))
        let scan = ExtensionCatalog.scan(in: sandbox.root)
        #expect(scan.extensions.count == 2)
        #expect(scan.problems.isEmpty)
        #expect(scan.extensions.allSatisfy { $0.iconData == nil })
    }

    @Test("Look again sees replacement and removal at the same icon path")
    func samePathReplacement() throws {
        let sandbox = try IconSandbox()
        defer { sandbox.remove() }
        let folder = try sandbox.add(icon: "icon.png")
        let path = folder.appending(path: "icon.png")
        let first = try IconSandbox.png(red: 0.2)
        let second = try IconSandbox.png(red: 0.9)
        try first.write(to: path)
        let before = try #require(ExtensionCatalog.scan(in: sandbox.root).extensions.first)
        try second.write(to: path)
        let after = try #require(ExtensionCatalog.scan(in: sandbox.root).extensions.first)
        #expect(before.account == after.account)
        #expect(before != after)
        #expect(after.iconData == second)
        try FileManager.default.removeItem(at: path)
        let removed = try #require(ExtensionCatalog.scan(in: sandbox.root).extensions.first)
        #expect(removed.account == before.account)
        #expect(removed.iconData == nil)
        #expect(removed != after)
    }
}
