// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Replayable, synchronous line IO with a cancellation checkpoint per read and
/// per line. Memory is one 64 KiB chunk plus the current line, never the file.
/// A fresh iterator owns its descriptor; breaking a loop closes it on release.
struct LogLines: Sequence {
    private let file: URL?
    private let data: Data?
    private let chunkSize: Int

    init(at file: URL, chunkSize: Int = 64 * 1024) {
        self.file = file
        self.data = nil
        self.chunkSize = Swift.max(1, chunkSize)
    }

    /// The fixture parsers share the exact same line semantics as disk reads.
    init(data: Data) {
        self.file = nil
        self.data = data
        self.chunkSize = 64 * 1024
    }

    func makeIterator() -> Iterator { Iterator(file: file, data: data, chunkSize: chunkSize) }

    func forEachLine(_ body: (Data) -> Void) {
        for line in self { autoreleasepool { body(line) } }
    }

    final class Iterator: IteratorProtocol {
        private var handle: FileHandle?
        private var chunk: Data
        private var offset: Int
        private let chunkSize: Int

        init(file: URL?, data: Data?, chunkSize: Int) {
            handle = Task.isCancelled ? nil : file.flatMap { try? FileHandle(forReadingFrom: $0) }
            chunk = data ?? Data()
            offset = chunk.startIndex
            self.chunkSize = chunkSize
        }

        deinit { try? handle?.close() }

        func next() -> Data? {
            var line = Data()
            while !Task.isCancelled {
                if offset < chunk.endIndex {
                    if let end = chunk[offset...].firstIndex(of: 0x0a) {
                        line.append(contentsOf: chunk[offset..<end])
                        offset = end + 1
                        if line.isEmpty { continue }
                        return line
                    }
                    line.append(contentsOf: chunk[offset...])
                    offset = chunk.endIndex
                }
                guard let handle else { return line.isEmpty ? nil : line }
                let bytes = autoreleasepool { try? handle.read(upToCount: chunkSize) }
                guard let bytes, !bytes.isEmpty else {
                    close()
                    return line.isEmpty ? nil : line
                }
                chunk = bytes
                offset = chunk.startIndex
            }
            close()
            return nil
        }

        private func close() {
            try? handle?.close()
            handle = nil
            chunk = Data()
            offset = 0
        }
    }
}
