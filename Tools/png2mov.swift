#!/usr/bin/env swift

// png2mov.swift — Convert a folder of PNG frames into a transparent .mov
// suitable for use as a WalkerCharacter animation in Lil Agents.
//
// USAGE:
//   chmod +x Tools/png2mov.swift
//   ./Tools/png2mov.swift --input ./frames/my_char_walk --output ./LilAgents/walk-my-char-01.mov --fps 24
//
// BATCH EXAMPLE (all animation folders at once):
//   ./Tools/png2mov.swift --batch ./frames --output ./LilAgents --fps 24
//   This scans every sub-folder in ./frames and writes walk-<foldername>-01.mov for each.
//
// NOTES FOR LIL AGENTS:
//   • Existing characters use 1080×1920 @ 24 fps HEVC-with-alpha .mov files.
//   • All frames must be the same pixel size (the script validates this).
//   • Keep pixel art at native resolution — no upscaling; the app renders at
//     CharacterSize heights (100/150/200 px) and scales via AVPlayerLayer.
//   • Codec preference: HEVC with alpha → ProRes 4444 fallback (both preserve alpha).
//   • After generating the .mov, add it to the Xcode project and create a
//     WalkerCharacter(videoName: "walk-my-char-01", name: "MyChar") in
//     LilAgentsController.start().

import Foundation
import AVFoundation
import AppKit
import CoreVideo
import CoreMedia

// MARK: - Errors

enum ScriptError: LocalizedError {
    case usage(String)
    case inputFolderNotFound(String)
    case noPNGFiles(String)
    case failedToLoadImage(String)
    case inconsistentFrameSize(expected: CGSize, found: CGSize, file: String)
    case failedToCreateWriter(String)
    case writerCannotApplySettings
    case failedToAddInput
    case failedToStartWriting(String)
    case pixelBufferPoolUnavailable
    case failedToCreatePixelBuffer
    case failedToAppendFrame(Int, String)
    case writerFailed(String)
    case invalidFPS(String)

    var errorDescription: String? {
        switch self {
        case .usage(let msg):
            return msg
        case .inputFolderNotFound(let path):
            return "Input folder does not exist: \(path)"
        case .noPNGFiles(let path):
            return "No PNG files found in folder: \(path)"
        case .failedToLoadImage(let path):
            return "Failed to load PNG as CGImage: \(path)"
        case .inconsistentFrameSize(let expected, let found, let file):
            return """
            Frame size mismatch in \(file)
            Expected: \(Int(expected.width))x\(Int(expected.height))
            Found:    \(Int(found.width))x\(Int(found.height))
            """
        case .failedToCreateWriter(let msg):
            return "Failed to create AVAssetWriter: \(msg)"
        case .writerCannotApplySettings:
            return "AVAssetWriter cannot apply the chosen output settings for video."
        case .failedToAddInput:
            return "AVAssetWriter cannot add the video input."
        case .failedToStartWriting(let msg):
            return "Failed to start writing: \(msg)"
        case .pixelBufferPoolUnavailable:
            return "Pixel buffer pool is unavailable (pool is nil after startWriting — ensure startWriting() was called first)."
        case .failedToCreatePixelBuffer:
            return "Failed to create pixel buffer."
        case .failedToAppendFrame(let index, let file):
            return "Failed to append frame \(index) (\(file))."
        case .writerFailed(let msg):
            return "Writer failed: \(msg)"
        case .invalidFPS(let value):
            return "Invalid fps value '\(value)' — must be a positive integer."
        }
    }
}

// MARK: - Config

struct Config {
    let inputFolder: URL
    let outputFile: URL
    let fps: Int32
}

// MARK: - Argument Parsing

func parseArgs() throws -> (configs: [Config], isBatch: Bool) {
    let args = Array(CommandLine.arguments.dropFirst())
    var inputPath: String?
    var outputPath: String?
    var fpsString: String = "24"       // default matches existing Lil Agents videos
    var isBatch = false

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--input", "-i":
            i += 1
            guard i < args.count else { throw ScriptError.usage("Missing value after --input") }
            inputPath = args[i]
        case "--output", "-o":
            i += 1
            guard i < args.count else { throw ScriptError.usage("Missing value after --output") }
            outputPath = args[i]
        case "--fps", "-f":
            i += 1
            guard i < args.count else { throw ScriptError.usage("Missing value after --fps") }
            fpsString = args[i]
        case "--batch", "-b":
            // --batch <frames_dir> --output <output_dir> [--fps N]
            isBatch = true
            i += 1
            guard i < args.count else { throw ScriptError.usage("Missing value after --batch") }
            inputPath = args[i]
        case "--help", "-h":
            throw ScriptError.usage(helpText)
        default:
            throw ScriptError.usage("Unknown argument: \(args[i])\n\n\(helpText)")
        }
        i += 1
    }

    guard let fps = Int32(fpsString), fps > 0 else {
        throw ScriptError.invalidFPS(fpsString)
    }

    guard let input = inputPath, let output = outputPath else {
        throw ScriptError.usage(helpText)
    }

    let inputURL = URL(fileURLWithPath: input)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDir), isDir.boolValue else {
        throw ScriptError.inputFolderNotFound(inputURL.path)
    }
    let outputURL = URL(fileURLWithPath: output)

    if isBatch {
        // inputURL is the parent folder; outputURL is the output directory.
        // Produce walk-<subfoldername>-01.mov for each sub-folder containing PNGs.
        let subfolders = try FileManager.default.contentsOfDirectory(
            at: inputURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            var d: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &d) && d.boolValue
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        let configs = subfolders.compactMap { sub -> Config? in
            let name = sub.lastPathComponent
            let outFile = outputURL.appendingPathComponent("walk-\(name)-01.mov")
            return Config(inputFolder: sub, outputFile: outFile, fps: fps)
        }
        return (configs, true)
    } else {
        return ([Config(inputFolder: inputURL, outputFile: outputURL, fps: fps)], false)
    }
}

let helpText = """
USAGE:
  png2mov.swift --input <frames_dir> --output <output.mov> [--fps N]
  png2mov.swift --batch <parent_dir> --output <output_dir> [--fps N]

OPTIONS:
  -i, --input    Folder containing PNG frames (single-animation mode)
  -o, --output   Output .mov path (single mode) or output directory (batch mode)
  -f, --fps      Frame rate (default: 24, matching existing Lil Agents videos)
  -b, --batch    Batch mode: encode every sub-folder in <parent_dir>
  -h, --help     Show this help

EXAMPLES:
  # Single animation
  ./Tools/png2mov.swift -i ./frames/my_char_walk -o ./LilAgents/walk-my-char-01.mov

  # Batch — encodes frames/hello → walk-hello-01.mov, frames/walk_left → walk-walk_left-01.mov, etc.
  ./Tools/png2mov.swift --batch ./frames --output ./LilAgents --fps 24

LIL AGENTS INTEGRATION:
  After generating the .mov:
  1. Add it to the Xcode project (drag into LilAgents group, tick "Add to target")
  2. In LilAgentsController.start(), add:
       let char3 = WalkerCharacter(videoName: "walk-my-char-01", name: "MyChar")
  3. Configure walk timing properties (accelStart, fullSpeedStart, etc.) to match
     the animation's action timing.
"""

// MARK: - File Loading

func numericSortKey(for url: URL) -> [Int] {
    let name = url.deletingPathExtension().lastPathComponent
    let regex = try? NSRegularExpression(pattern: "(\\d+)")
    let range = NSRange(name.startIndex..., in: name)
    let nsMatches = regex?.matches(in: name, range: range) ?? []
    let ints = nsMatches.compactMap { m -> Int? in
        guard let r = Range(m.range(at: 1), in: name) else { return nil }
        return Int(name[r])
    }
    return ints.isEmpty ? [Int.max] : ints
}

func sortedPNGFiles(in folder: URL) throws -> [URL] {
    let files = try FileManager.default.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    let pngs = files.filter { $0.pathExtension.lowercased() == "png" }
    guard !pngs.isEmpty else { throw ScriptError.noPNGFiles(folder.path) }

    return pngs.sorted {
        let k0 = numericSortKey(for: $0)
        let k1 = numericSortKey(for: $1)
        if k0 != k1 { return k0.lexicographicallyPrecedes(k1) }
        return $0.lastPathComponent < $1.lastPathComponent
    }
}

func loadCGImages(_ urls: [URL]) throws -> [(url: URL, image: CGImage)] {
    try urls.map { url in
        guard
            let nsImage = NSImage(contentsOf: url),
            let tiff = nsImage.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let cg = rep.cgImage
        else {
            throw ScriptError.failedToLoadImage(url.path)
        }
        return (url, cg)
    }
}

func validateFrameSizes(_ frames: [(url: URL, image: CGImage)]) throws -> CGSize {
    guard let first = frames.first else { fatalError("validateFrameSizes called with empty array") }
    let expected = CGSize(width: first.image.width, height: first.image.height)
    for frame in frames {
        let found = CGSize(width: frame.image.width, height: frame.image.height)
        guard found == expected else {
            throw ScriptError.inconsistentFrameSize(expected: expected, found: found, file: frame.url.lastPathComponent)
        }
    }
    return expected
}

// MARK: - Codec Selection

func preferredCodec() -> AVVideoCodecType {
    if #available(macOS 10.15, *) { return .hevcWithAlpha }
    return .proRes4444
}

func codecDescription(_ codec: AVVideoCodecType) -> String {
    switch codec {
    case .hevcWithAlpha: return "HEVC with alpha (hvc1 + alpha)"
    case .proRes4444:    return "Apple ProRes 4444"
    default:             return codec.rawValue
    }
}

// MARK: - Pixel Buffer

func makeOutputSettings(width: Int, height: Int, codec: AVVideoCodecType) -> [String: Any] {
    [AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height]
}

func makePixelBufferAttributes(width: Int, height: Int) -> [String: Any] {
    [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]
}

func createPixelBuffer(from image: CGImage, pool: CVPixelBufferPool) throws -> CVPixelBuffer {
    var maybeBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer) == kCVReturnSuccess,
          let buf = maybeBuffer else {
        throw ScriptError.failedToCreatePixelBuffer
    }

    CVPixelBufferLockBaseAddress(buf, [])
    defer { CVPixelBufferUnlockBaseAddress(buf, []) }

    guard let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(buf),
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
        space: CGColorSpaceCreateDeviceRGB(),
        // premultiplied alpha + little-endian BGRA — matches HEVC-with-alpha pipeline
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
        throw ScriptError.failedToCreatePixelBuffer
    }

    ctx.clear(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buf
}

// MARK: - Encoding

func waitForInput(_ input: AVAssetWriterInput) {
    while !input.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.005)
    }
}

func encode(config: Config) throws {
    let pngs   = try sortedPNGFiles(in: config.inputFolder)
    let frames = try loadCGImages(pngs)
    let size   = try validateFrameSizes(frames)
    let width  = Int(size.width)
    let height = Int(size.height)

    print("\n── \(config.inputFolder.lastPathComponent) ──────────────────────────")
    print("Found \(frames.count) PNG frames  |  \(width)×\(height)  |  \(config.fps) fps")

    if FileManager.default.fileExists(atPath: config.outputFile.path) {
        try FileManager.default.removeItem(at: config.outputFile)
    }

    // Ensure output directory exists
    try FileManager.default.createDirectory(
        at: config.outputFile.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let codec    = preferredCodec()
    var settings = makeOutputSettings(width: width, height: height, codec: codec)

    let writer: AVAssetWriter
    do {
        writer = try AVAssetWriter(outputURL: config.outputFile, fileType: .mov)
    } catch {
        throw ScriptError.failedToCreateWriter(error.localizedDescription)
    }

    // Fall back to ProRes 4444 if HEVC-with-alpha is not available (rare on Catalina+)
    if !writer.canApply(outputSettings: settings, forMediaType: .video) {
        if codec == .hevcWithAlpha {
            print("⚠︎  HEVC with alpha not accepted — falling back to ProRes 4444")
            let fallback = AVVideoCodecType.proRes4444
            settings = makeOutputSettings(width: width, height: height, codec: fallback)
            guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
                throw ScriptError.writerCannotApplySettings
            }
        } else {
            throw ScriptError.writerCannotApplySettings
        }
    }

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    guard writer.canAdd(input) else { throw ScriptError.failedToAddInput }
    writer.add(input)

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: makePixelBufferAttributes(width: width, height: height)
    )

    guard writer.startWriting() else {
        throw ScriptError.failedToStartWriting(writer.error?.localizedDescription ?? "unknown")
    }
    writer.startSession(atSourceTime: .zero)

    // Pool is only available after startWriting + startSession
    guard let pool = adaptor.pixelBufferPool else {
        throw ScriptError.pixelBufferPoolUnavailable
    }

    let codecName = codecDescription(
        settings[AVVideoCodecKey] as? AVVideoCodecType ?? codec
    )
    print("Codec: \(codecName)")
    print("Output: \(config.outputFile.path)")

    for (index, frame) in frames.enumerated() {
        autoreleasepool {
            do {
                waitForInput(input)
                let buf  = try createPixelBuffer(from: frame.image, pool: pool)
                let time = CMTime(value: CMTimeValue(index), timescale: config.fps)
                guard adaptor.append(buf, withPresentationTime: time) else {
                    throw ScriptError.failedToAppendFrame(index, frame.url.lastPathComponent)
                }
                let pct = Int(Double(index + 1) / Double(frames.count) * 100.0)
                print("  [\(index + 1)/\(frames.count)] \(pct)%  \(frame.url.lastPathComponent)")
            } catch {
                print("  ✗ Frame \(index + 1): \(error.localizedDescription)")
                writer.cancelWriting()
            }
        }

        if writer.status == .failed || writer.status == .cancelled {
            throw ScriptError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    input.markAsFinished()

    let sem = DispatchSemaphore(value: 0)
    writer.finishWriting { sem.signal() }
    sem.wait()

    guard writer.status == .completed else {
        throw ScriptError.writerFailed(writer.error?.localizedDescription ?? "unknown")
    }

    print("✓ Done → \(config.outputFile.lastPathComponent)")
}

// MARK: - Entry Point

do {
    let (configs, isBatch) = try parseArgs()

    if isBatch {
        print("Batch mode: \(configs.count) animation folder(s) found")
    }

    var failures: [(String, Error)] = []
    for config in configs {
        do {
            try encode(config: config)
        } catch {
            failures.append((config.inputFolder.lastPathComponent, error))
            fputs("✗ \(config.inputFolder.lastPathComponent): \(error.localizedDescription)\n", stderr)
        }
    }

    if !failures.isEmpty {
        fputs("\n\(failures.count) of \(configs.count) animation(s) failed.\n", stderr)
        exit(1)
    }

    if isBatch || configs.count > 1 {
        print("\n\(configs.count) animation(s) encoded successfully.")
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
