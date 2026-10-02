// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// A small RFC 4180 reader for the CSV exports some agents still write.
///
/// The legacy Cursor cache is the reason this exists: its rows embed model
/// names and money, a field can be wrapped in double quotes, and a quoted value
/// can hold a comma — so splitting on `,` puts the columns in the wrong places
/// and reads a model name as a token count. This walks the text once with a
/// quote state instead.
///
/// It is deliberately a **record reader, not a schema**: it returns rows of
/// fields and nothing else. Interpreting a header, coercing a number or
/// deciding what a blank means belongs to the caller, so a malformed row can be
/// skipped without this having guessed.
enum CapturedCSV {
    /// Every record in `text`, each a list of fields.
    ///
    /// Handles:
    /// - a field wrapped in `"…"`, with `""` inside it as one literal quote;
    /// - a comma inside a quoted field, kept as part of that field;
    /// - `\r\n`, `\n` and a lone `\r` all ending a record;
    /// - a final record with no trailing newline;
    /// - a leading UTF-8 byte-order mark, stripped rather than read as part of
    ///   the first header name.
    ///
    /// Newlines *inside* a quoted field are kept in the field, which is what
    /// RFC 4180 asks for. Nothing is repaired: an unterminated quote is simply
    /// the last field to the end of the file.
    static func rows(in text: String) -> [[String]] {
        let characters = text.unicodeScalars

        var rows: [[String]] = []
        var record: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false

        func endField() {
            record.append(String(field))
            field = String.UnicodeScalarView()
        }

        func endRecord() {
            endField()
            rows.append(record)
            record = []
        }

        var index = characters.startIndex
        if characters.first?.value == 0xFEFF { index = characters.index(after: index) }
        while index < characters.endIndex {
            guard !Task.isCancelled else { return [] }
            let character = characters[index]
            let next = characters.index(after: index)
            if inQuotes {
                if character == "\"" {
                    // A doubled quote is one literal quote; a lone one closes.
                    if next < characters.endIndex, characters[next] == "\"" {
                        field.append("\"")
                        index = characters.index(after: next)
                    } else {
                        inQuotes = false
                        index = next
                    }
                } else {
                    field.append(character)
                    index = next
                }
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
                index = next
            case ",":
                endField()
                index = next
            case "\r":
                index = next < characters.endIndex && characters[next] == "\n" ? characters.index(after: next) : next
                endRecord()
            case "\n":
                index = next
                endRecord()
            default:
                field.append(character)
                index = next
            }
        }

        // A record is only pending if something was written for it. A file that
        // ends on a newline must not grow a phantom empty record.
        if !field.isEmpty || !record.isEmpty { endRecord() }
        return rows
    }
}
