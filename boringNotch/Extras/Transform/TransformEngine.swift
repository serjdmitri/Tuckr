//
//  TransformEngine.swift
//  The Shelf's fourth panel does the work here: resize, compress, convert, rotate, cut out the
//  background, strip metadata, combine into one PDF, zip. Everything runs off the main thread
//  and writes a new file; nothing is overwritten.
//

import AppKit
import CoreImage
import Defaults
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

enum TransformAction: String, CaseIterable, Identifiable {
    case resize, compress, convert, rotate, removeBackground, stripMetadata, combinePDF, zip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resize: "Resize"
        case .compress: "Compress"
        case .convert: "Convert"
        case .rotate: "Rotate"
        case .removeBackground: "Cut out"
        case .stripMetadata: "Clean"
        case .combinePDF: "Make PDF"
        case .zip: "Zip"
        }
    }

    var symbol: String {
        switch self {
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .convert: "arrow.triangle.2.circlepath"
        case .rotate: "rotate.right"
        case .removeBackground: "person.crop.circle.badge.minus"
        case .stripMetadata: "eye.slash"
        case .combinePDF: "doc.on.doc"
        case .zip: "doc.zipper"
        }
    }

    var suffix: String {
        switch self {
        case .resize: "resized"
        case .compress: "compressed"
        case .convert: "converted"
        case .rotate: "rotated"
        case .removeBackground: "cutout"
        case .stripMetadata: "clean"
        case .combinePDF: "combined"
        case .zip: ""
        }
    }

    /// What the tile says beneath its name: the preset it will use.
    var presetLabel: String? {
        switch self {
        case .resize: "\(Defaults[.transformResizeEdge]) px"
        case .compress: "\(Int(Defaults[.transformQuality] * 100))%"
        case .convert: Defaults[.transformFormat].rawValue
        case .rotate: Defaults[.transformRotation] == 180 ? "180°" : (Defaults[.transformRotation] == 270 ? "90° left" : "90° right")
        default: nil
        }
    }

    func applies(to urls: [URL]) -> Bool {
        let images = urls.filter(TransformEngine.isImage).count
        switch self {
        case .resize, .compress, .convert, .rotate, .removeBackground, .stripMetadata: return images > 0
        case .combinePDF: return urls.filter { TransformEngine.isImage($0) || TransformEngine.isPDF($0) }.count >= 2
        case .zip: return !urls.isEmpty
        }
    }
}

struct TransformResult {
    var outputs: [URL] = []
    var skipped = 0
    var failed = 0
    var firstError: String?
    var bytesBefore: Int64 = 0
    var bytesAfter: Int64 = 0

    var summary: String {
        if outputs.isEmpty { return firstError ?? "Nothing to do for those files" }
        var text = outputs.count == 1 ? "Saved 1 file" : "Saved \(outputs.count) files"
        if bytesBefore > 0, bytesAfter > 0 {
            let f = ByteCountFormatter()
            f.countStyle = .file
            text += " · \(f.string(fromByteCount: bytesBefore)) → \(f.string(fromByteCount: bytesAfter))"
        }
        if failed > 0 { text += " · \(failed) failed" }
        return text
    }
}

private enum TransformError: LocalizedError {
    case unreadable, noSubject, encode, zip, noChange(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: "Couldn't read that image"
        case .noSubject: "No subject found to cut out"
        case .encode: "Couldn't write the result"
        case .zip: "Couldn't make the zip"
        case .noChange(let why): why
        }
    }
}

enum TransformEngine {
    /// The presets and the output place, read once on the main thread for a job.
    struct Settings: Sendable {
        var folder: URL?
        var edge: Int
        var quality: Double
        var format: TransformFormat
        var rotation: Int

        @MainActor static func current() -> Settings {
            var folder: URL?
            let path = Defaults[.transformFolder]
            if Defaults[.transformOutput] == .pickedFolder, !path.isEmpty {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    folder = URL(fileURLWithPath: path, isDirectory: true)
                }
            }
            return Settings(
                folder: folder, edge: Defaults[.transformResizeEdge], quality: Defaults[.transformQuality],
                format: Defaults[.transformFormat], rotation: Defaults[.transformRotation])
        }
    }

    // MARK: Types

    static func contentType(_ url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = contentType(url) else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .svg)
    }

    static func isPDF(_ url: URL) -> Bool { contentType(url)?.conforms(to: .pdf) ?? false }

    private static let writable: Set<String> = {
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    }()

    // MARK: Running

    static func run(_ action: TransformAction, on urls: [URL], settings: Settings) async -> TransformResult {
        await Task.detached(priority: .userInitiated) {
            runSync(action, on: urls, settings: settings)
        }.value
    }

    private static func runSync(_ action: TransformAction, on urls: [URL], settings: Settings) -> TransformResult {
        var result = TransformResult()
        switch action {
        case .combinePDF:
            do { result.outputs = [try combine(urls, settings: settings)] } catch { result.firstError = error.localizedDescription }
        case .zip:
            do { result.outputs = [try zip(urls, settings: settings)] } catch { result.firstError = error.localizedDescription }
        default:
            for url in urls {
                guard isImage(url) else { result.skipped += 1; continue }
                do {
                    let out = try process(url, action: action, settings: settings)
                    result.outputs.append(out)
                    result.bytesBefore += fileSize(url)
                    result.bytesAfter += fileSize(out)
                } catch TransformError.noChange(let why) {
                    // Nothing to gain: the file is left as it is.
                    result.skipped += 1
                    result.firstError = result.firstError ?? why
                } catch {
                    result.failed += 1
                    result.firstError = result.firstError ?? error.localizedDescription
                }
            }
        }
        return result
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    // MARK: Output names

    private static func outputURL(for source: URL, suffix: String, ext: String, settings: Settings) -> URL {
        let directory = settings.folder ?? source.deletingLastPathComponent()
        var base = source.deletingPathExtension().lastPathComponent
        if !suffix.isEmpty { base += " " + suffix }
        func candidate(_ n: Int) -> URL {
            let name = n == 1 ? base : "\(base) \(n)"
            return directory.appendingPathComponent(name).appendingPathExtension(ext)
        }
        var n = 1
        while FileManager.default.fileExists(atPath: candidate(n).path) { n += 1 }
        return candidate(n)
    }

    // MARK: Images

    private static func process(_ url: URL, action: TransformAction, settings: Settings) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw TransformError.unreadable
        }
        let sourceType = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
        let props = keptProperties(source)
        let longest = longestEdge(source)

        switch action {
        case .resize:
            // Only ever smaller: scaling a picture up just makes the file bigger.
            guard longest > settings.edge else {
                throw TransformError.noChange("Already \(longest) px, not bigger than \(settings.edge)")
            }
            let image = try decode(source, maxEdge: settings.edge)
            let type = writableType(sourceType)
            let out = outputURL(for: url, suffix: action.suffix, ext: fileExtension(type, source: url, sourceType: sourceType), settings: settings)
            try write(image, props: props, type: type, quality: 0.85, to: out)
            return out

        case .compress:
            // JPEG and HEIC shrink with quality; anything else becomes a JPEG (alpha is flattened).
            var type = writableType(sourceType)
            var image = try decode(source, maxEdge: longest)
            if type != .jpeg, type != .heic, type != .png { type = .jpeg }
            if type == .jpeg { image = flatten(image) }
            let out = outputURL(for: url, suffix: action.suffix, ext: fileExtension(type, source: url, sourceType: sourceType), settings: settings)
            try write(image, props: props, type: type, quality: settings.quality, to: out)
            // A re-save that came out no smaller is not a compression: keep only the original.
            // PNG is lossless, so quality does nothing: it has to shrink noticeably to count.
            let saved = type == .png ? 0.95 : 1.0
            if Double(fileSize(out)) >= Double(fileSize(url)) * saved {
                try? FileManager.default.removeItem(at: out)
                throw TransformError.noChange(type == .png ? "PNG is already compressed: use Convert" : "Already as small as it gets")
            }
            return out

        case .convert:
            let type: UTType = switch settings.format { case .jpeg: .jpeg; case .png: .png; case .heic: .heic }
            if type == sourceType { throw TransformError.noChange("Already \(settings.format.rawValue)") }
            var image = try decode(source, maxEdge: longest)
            if type == .jpeg { image = flatten(image) }
            let out = outputURL(for: url, suffix: action.suffix, ext: fileExtension(type, source: url, sourceType: sourceType), settings: settings)
            try write(image, props: props, type: type, quality: 0.9, to: out)
            return out

        case .rotate:
            let image = rotate(try decode(source, maxEdge: longest), degrees: settings.rotation)
            let type = writableType(sourceType)
            let out = outputURL(for: url, suffix: action.suffix, ext: fileExtension(type, source: url, sourceType: sourceType), settings: settings)
            try write(image, props: props, type: type, quality: 0.9, to: out)
            return out

        case .stripMetadata:
            let type = writableType(sourceType)
            let out = outputURL(for: url, suffix: action.suffix, ext: fileExtension(type, source: url, sourceType: sourceType), settings: settings)
            // The pixels are copied as they are; only the tags (camera, place, time) are left out.
            if type == sourceType, copyWithoutMetadata(source, type: type, to: out) { return out }
            try? FileManager.default.removeItem(at: out)
            let image = try decode(source, maxEdge: longest)
            try write(image, props: nil, type: type, quality: 0.9, to: out)
            return out

        case .removeBackground:
            let image = try decode(source, maxEdge: longest)
            let handler = VNImageRequestHandler(cgImage: image)
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let observation = request.results?.first else { throw TransformError.noSubject }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
            let out = outputURL(for: url, suffix: action.suffix, ext: "png", settings: settings)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw TransformError.encode }
            try CIContext().writePNGRepresentation(of: CIImage(cvPixelBuffer: buffer), to: out, format: .RGBA8, colorSpace: space)
            return out

        default:
            throw TransformError.encode
        }
    }

    /// The file's own extension when the type is unchanged (so .jpg stays .jpg), else the type's.
    private static func fileExtension(_ type: UTType, source: URL, sourceType: UTType?) -> String {
        if type == sourceType, !source.pathExtension.isEmpty { return source.pathExtension }
        if type == .jpeg { return "jpg" }
        return type.preferredFilenameExtension ?? "png"
    }

    /// The source's own type when it can be written, otherwise PNG.
    private static func writableType(_ type: UTType?) -> UTType {
        if let type, writable.contains(type.identifier) { return type }
        return .png
    }

    private static func longestEdge(_ source: CGImageSource) -> Int {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(w, h, 1)
    }

    /// The pixels with the camera's orientation already applied, so nothing is turned afterwards.
    private static func decode(_ source: CGImageSource, maxEdge: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw TransformError.unreadable
        }
        return image
    }

    /// The same picture without its metadata, copied rather than re-encoded so the file does not
    /// grow. A photo that relies on its orientation tag cannot be done this way (the tag would go
    /// too), so it returns false and the caller re-encodes upright pixels instead.
    private static func copyWithoutMetadata(_ source: CGImageSource, type: UTType, to url: URL) -> Bool {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if let orientation = props?[kCGImagePropertyOrientation] as? Int, orientation != 1 { return false }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: CGImageMetadataCreateMutable(),
            kCGImageDestinationMergeMetadata: false,
        ]
        return CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil)
    }

    /// The source's own metadata, minus what no longer matches the new pixels.
    private static func keptProperties(_ source: CGImageSource) -> [CFString: Any] {
        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        for key in [kCGImagePropertyOrientation, kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight,
                    kCGImagePropertyDepth, kCGImagePropertyColorModel, kCGImagePropertyProfileName,
                    kCGImagePropertyFileSize] { props[key] = nil }
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = nil
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            props[kCGImagePropertyExifDictionary] = exif
        }
        return props
    }

    private static func write(_ image: CGImage, props: [CFString: Any]?, type: UTType, quality: Double, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw TransformError.encode
        }
        var properties = props ?? [:]
        if type == .jpeg || type == .heic { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw TransformError.encode }
    }

    /// JPEG has no alpha: put the picture on white.
    private static func flatten(_ image: CGImage) -> CGImage {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipFirst, image.alphaInfo != .noneSkipLast,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    /// Clockwise by 90, 180 or 270 degrees.
    private static func rotate(_ image: CGImage, degrees: Int) -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let sideways = degrees == 90 || degrees == 270
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: Int(sideways ? h : w), height: Int(sideways ? w : h), bitsPerComponent: 8,
                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        switch degrees {
        case 90:
            context.translateBy(x: 0, y: w)
            context.rotate(by: -.pi / 2)
        case 270:
            context.translateBy(x: h, y: 0)
            context.rotate(by: .pi / 2)
        default:
            context.translateBy(x: w, y: h)
            context.rotate(by: .pi)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage() ?? image
    }

    // MARK: PDF and zip

    private static func combine(_ urls: [URL], settings: Settings) throws -> URL {
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let document = PDFDocument()
        for url in sorted {
            if isPDF(url), let pdf = PDFDocument(url: url) {
                for index in 0..<pdf.pageCount {
                    if let page = pdf.page(at: index) { document.insert(page, at: document.pageCount) }
                }
            } else if isImage(url), let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
                document.insert(page, at: document.pageCount)
            }
        }
        guard document.pageCount > 0, let first = sorted.first else { throw TransformError.encode }
        let out = outputURL(for: first, suffix: TransformAction.combinePDF.suffix, ext: "pdf", settings: settings)
        guard document.write(to: out) else { throw TransformError.encode }
        return out
    }

    private static func zip(_ urls: [URL], settings: Settings) throws -> URL {
        guard let first = urls.first else { throw TransformError.zip }
        let fm = FileManager.default
        var staging: URL?
        defer { if let staging { try? fm.removeItem(at: staging) } }

        let input: URL
        let out: URL
        if urls.count == 1 {
            input = first
            out = outputURL(for: first, suffix: "", ext: "zip", settings: settings)
        } else {
            // Several items go into one folder first, so the archive opens as one thing.
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let folder = root.appendingPathComponent("Archive", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            staging = root
            for url in urls {
                var target = folder.appendingPathComponent(url.lastPathComponent)
                var n = 2
                while fm.fileExists(atPath: target.path) {
                    target = folder.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(n)")
                        .appendingPathExtension(url.pathExtension)
                    n += 1
                }
                try fm.copyItem(at: url, to: target)
            }
            input = folder
            out = outputURL(for: first.deletingLastPathComponent().appendingPathComponent("Archive"), suffix: "", ext: "zip", settings: settings)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", input.path, out.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw TransformError.zip }
        return out
    }
}
