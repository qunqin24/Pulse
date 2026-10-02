// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Darwin
import Foundation

/// Streaming Zstandard decoding for DeepSeek Harness transcripts and any other
/// reader that needs it, bound to a **locally installed** `libzstd`.
///
/// **No zstd implementation is vendored or bundled.** The symbols are resolved
/// from a library already on this machine, tried in a fixed, explicit order:
/// the system location (`/usr/lib`), then `/opt/homebrew/lib`, then
/// `/usr/local/lib`. A bare library name is deliberately **not** used, because
/// `dlopen` of a bare name searches an unpredictable set of paths and could
/// load a different copy than the one intended. Nothing is installed and no
/// source or binary is added.
///
/// **This is a local-library dependency, not an OS guarantee.** macOS does not
/// ship `libzstd` in `/usr/lib` on every version, and libarchive's zstd filter
/// is not a substitute (it is offered as an external program filter here, which
/// Pulse will not run). When no candidate loads, `limitation` says so and the
/// callers report the store as unreadable rather than as empty — an undecoded
/// transcript is never counted as zero.
///
/// **Streaming, because a live writer appends one frame per flush.** A scan can
/// catch a transcript mid-write and see a torn trailing frame. Complete frames
/// and the decodable prefix of a **truncated** one are kept; a frame that
/// reports a real zstd error (bad data, failed checksum) throws instead, so
/// corrupt bytes are never silently accepted as a complete account. Both the
/// raw input and the decoded output are bounded, so a high-ratio frame cannot
/// allocate without limit.
enum DSHZstdDecoder {
    enum Failure: Error, CustomStringConvertible, Sendable {
        /// No candidate library, or one of its symbols, could be loaded.
        case unavailable(String)
        /// The stream reported a zstd error, or made no progress.
        case corrupt(String)
        /// A bound was reached before the stream ended.
        case tooLarge

        var description: String {
            switch self {
            case let .unavailable(reason): "zstd unavailable: \(reason)"
            case let .corrupt(reason): "zstd decode failed: \(reason)"
            case .tooLarge: "zstd stream exceeded the decoding ceiling"
            }
        }
    }

    /// The four bytes that begin a zstd frame; the suffix alone is not trusted.
    static let magic: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]

    /// Bounds mirroring the reader's: 64 MiB of input and 64 MiB of output.
    static let maxRawBytes = 64 * 1024 * 1024
    static let maxDecodedBytes = 64 * 1024 * 1024

    /// Explicit locations, in the order they are tried. Never a bare name.
    static let libraryPaths = [
        "/usr/lib/libzstd.1.dylib",
        "/opt/homebrew/lib/libzstd.1.dylib",
        "/usr/local/lib/libzstd.1.dylib",
    ]

    static func isZstd(_ data: Data) -> Bool {
        data.count >= magic.count && Array(data.prefix(magic.count)) == magic
    }

    /// nil when a local library is usable; the reason when none is.
    static var limitation: String? {
        if case let .failure(error) = loaded { return error.description }
        return nil
    }

    /// Decodes a zstd stream (one or more concatenated frames).
    ///
    /// Throws `tooLarge` past either ceiling, `unavailable` when no local
    /// library can be loaded, and `corrupt` when the stream reports a zstd
    /// error. A **torn** trailing frame — the input simply ends mid-frame — is
    /// not corruption: its decodable prefix is returned so the complete JSONL
    /// records before the break survive.
    static func decode(
        _ data: Data,
        rawLimit: Int = maxRawBytes,
        decodedLimit: Int = maxDecodedBytes
    ) throws -> Data {
        try Task.checkCancellation()
        guard data.count <= rawLimit else { throw Failure.tooLarge }
        let api = try library()
        guard let stream = api.create() else { throw Failure.corrupt("no decoder stream") }
        defer { _ = api.free(stream) }
        guard api.isError(api.initialize(stream)) == 0 else {
            throw Failure.corrupt("decoder would not initialise")
        }

        var output = Data()
        let chunk = 256 * 1024

        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var input = ZSTD_inBuffer(src: base, size: data.count, pos: 0)

            try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: chunk) { buffer in
                while true {
                    try Task.checkCancellation()
                    let consumedBefore = input.pos
                    var out = ZSTD_outBuffer(dst: buffer.baseAddress, size: chunk, pos: 0)

                    let result = withUnsafeMutablePointer(to: &out) { outPointer in
                        withUnsafeMutablePointer(to: &input) { inPointer in
                            api.decompress(
                                stream,
                                UnsafeMutableRawPointer(outPointer),
                                UnsafeMutableRawPointer(inPointer)
                            )
                        }
                    }

                    if out.pos > 0, let bytes = buffer.baseAddress {
                        if output.count + out.pos > decodedLimit { throw Failure.tooLarge }
                        output.append(bytes, count: out.pos)
                    }

                    // A real zstd error is thrown even after a prefix decoded:
                    // bad data must not be accepted as a whole transcript.
                    if api.isError(result) != 0 {
                        let name = api.errorName(result).map { String(cString: $0) } ?? "zstd error"
                        throw Failure.corrupt(name)
                    }

                    // Frame boundary. More input means another concatenated
                    // frame follows.
                    if result == 0 {
                        if input.pos >= input.size { return }
                        continue
                    }

                    // The decoder wants more input. If the input is exhausted
                    // the trailing frame is torn, and the complete records
                    // before it stand.
                    if input.pos >= input.size { return }

                    // Input remains and nothing moved: not a clean torn tail.
                    if out.pos == 0 && input.pos == consumedBefore {
                        throw Failure.corrupt("decoder made no progress")
                    }
                }
            }
        }

        return output
    }

    // MARK: - The local library

    private struct API: Sendable {
        let create: @convention(c) () -> OpaquePointer?
        let free: @convention(c) (OpaquePointer?) -> Int
        let initialize: @convention(c) (OpaquePointer?) -> Int
        let decompress: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int
        let isError: @convention(c) (Int) -> UInt32
        let errorName: @convention(c) (Int) -> UnsafePointer<CChar>?
    }

    private struct ZSTD_inBuffer {
        var src: UnsafeRawPointer?
        var size: Int
        var pos: Int
    }

    private struct ZSTD_outBuffer {
        var dst: UnsafeMutableRawPointer?
        var size: Int
        var pos: Int
    }

    private static let loaded: Result<API, Failure> = {
        func open(_ path: String) -> API? {
            guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }

            func symbol<T>(_ name: String, _ type: T.Type) -> T? {
                guard let pointer = dlsym(handle, name) else { return nil }
                return unsafeBitCast(pointer, to: T.self)
            }

            guard
                let create = symbol("ZSTD_createDStream", (@convention(c) () -> OpaquePointer?).self),
                let free = symbol("ZSTD_freeDStream", (@convention(c) (OpaquePointer?) -> Int).self),
                let initialize = symbol("ZSTD_initDStream", (@convention(c) (OpaquePointer?) -> Int).self),
                let decompress = symbol(
                    "ZSTD_decompressStream",
                    (@convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int).self
                ),
                let isError = symbol("ZSTD_isError", (@convention(c) (Int) -> UInt32).self),
                let errorName = symbol(
                    "ZSTD_getErrorName",
                    (@convention(c) (Int) -> UnsafePointer<CChar>?).self
                )
            else {
                return nil
            }

            return API(
                create: create,
                free: free,
                initialize: initialize,
                decompress: decompress,
                isError: isError,
                errorName: errorName
            )
        }

        for path in libraryPaths {
            if let api = open(path) { return .success(api) }
        }
        return .failure(.unavailable(
            "no local libzstd (tried \(libraryPaths.joined(separator: ", ")))"
        ))
    }()

    private static func library() throws -> API {
        switch loaded {
        case let .success(api): return api
        case let .failure(error): throw error
        }
    }
}
