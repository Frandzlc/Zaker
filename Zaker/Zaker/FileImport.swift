import Foundation
import SwiftData
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Compression

/// يستورد أي ملف للمكتبة: PDF، صور، نصوص، Word، PowerPoint، Excel، وأي ملف ثاني.
enum FileImport {
    /// يرجع رسالة خطأ إذا فشل، أو nil إذا نجح.
    @discardableResult
    static func importFile(_ url: URL, into ctx: ModelContext) -> String? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let title = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext) ?? .data
        let mime = type.preferredMIMEType ?? "application/octet-stream"

        do {
            if type.conforms(to: .pdf) {
                let name = try BookFiles.importFile(from: url)
                let doc = PDFDocument(url: BookFiles.directory.appendingPathComponent(name))
                ctx.insert(Book(title: title, fileName: name, isPDF: true, pageCount: doc?.pageCount ?? 0))
            } else if type.conforms(to: .image) {
                let name = try BookFiles.importFile(from: url)
                let b = Book(title: title, fileName: name, isPDF: false)
                // HEIC وغيره: Gemini يقبل png/jpeg/webp/heic
                b.mimeType = mime
                ctx.insert(b)
            } else if type.conforms(to: .rtf) || type.conforms(to: .html) || type.conforms(to: .rtfd) {
                let name = try BookFiles.importFile(from: url)
                let text = attributedText(BookFiles.directory.appendingPathComponent(name), type: type)
                let b = Book(title: title, fileName: name, isPDF: false, textContent: text)
                b.mimeType = mime
                ctx.insert(b)
            } else if type.conforms(to: .text) || type.conforms(to: .sourceCode) || ["txt", "md", "csv", "json", "xml"].contains(ext) {
                let data = try Data(contentsOf: url)
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16)
                    ?? String(data: data, encoding: arabicWindows)
                    ?? String(decoding: data, as: UTF8.self)
                ctx.insert(Book(title: title, isPDF: false, textContent: text))
            } else {
                // Word / PowerPoint / Excel / EPUB / صوت / فيديو / أي شيء
                let name = try BookFiles.importFile(from: url)
                let stored = BookFiles.directory.appendingPathComponent(name)
                let text = OfficeText.extract(from: stored, ext: ext) ?? ""
                let b = Book(title: title, fileName: name, isPDF: false, textContent: text)
                b.mimeType = mime
                ctx.insert(b)
            }
            try? ctx.save()
            return nil
        } catch {
            return tr("ما قدرت أفتح الملف: ", "Couldn't open the file: ") + url.lastPathComponent
        }
    }

    private static let arabicWindows = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)))

    private static func attributedText(_ url: URL, type: UTType) -> String {
        let docType: NSAttributedString.DocumentType =
            type.conforms(to: .html) ? .html : (type.conforms(to: .rtfd) ? .rtfd : .rtf)
        let s = try? NSAttributedString(url: url, options: [.documentType: docType], documentAttributes: nil)
        return s?.string ?? ""
    }
}

// MARK: - استخراج النص من ملفات Office (docx / pptx / xlsx / epub)

enum OfficeText {
    static func extract(from url: URL, ext: String) -> String? {
        guard ["docx", "pptx", "xlsx", "epub", "odt", "odp"].contains(ext),
              let data = try? Data(contentsOf: url),
              let zip = ZipArchive(data: data) else { return nil }

        var parts: [String] = []
        switch ext {
        case "docx":
            if let x = zip.read("word/document.xml") { parts.append(paragraphs(x, tag: "w:t", para: "w:p")) }
        case "pptx":
            let slides = zip.names
                .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
                .sorted { number(in: $0) < number(in: $1) }
            for (i, s) in slides.enumerated() {
                if let x = zip.read(s) { parts.append("— Slide \(i + 1) —\n" + paragraphs(x, tag: "a:t", para: "a:p")) }
            }
        case "xlsx":
            if let x = zip.read("xl/sharedStrings.xml") { parts.append(paragraphs(x, tag: "t", para: "si")) }
        case "odt", "odp":
            if let x = zip.read("content.xml") { parts.append(stripTags(x)) }
        case "epub":
            for n in zip.names.sorted() where n.hasSuffix(".xhtml") || n.hasSuffix(".html") || n.hasSuffix(".htm") {
                if let x = zip.read(n) { parts.append(stripTags(x)) }
            }
        default: break
        }
        let out = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    private static func number(in s: String) -> Int {
        Int(s.filter(\.isNumber)) ?? 0
    }

    /// يجمع نص الوسوم <tag>…</tag> ويفصل الفقرات عند نهاية <para>.
    private static func paragraphs(_ xml: String, tag: String, para: String) -> String {
        var out = ""
        let scanner = xml as NSString
        var i = 0
        let len = scanner.length
        let open1 = "<\(tag)>", open2 = "<\(tag) ", close = "</\(tag)>", paraEnd = "</\(para)>"
        while i < len {
            let rest = NSRange(location: i, length: len - i)
            let r1 = scanner.range(of: open1, options: [], range: rest)
            let r2 = scanner.range(of: open2, options: [], range: rest)
            let rp = scanner.range(of: paraEnd, options: [], range: rest)
            let candidates = [r1, r2].filter { $0.location != NSNotFound }
            guard let r = candidates.min(by: { $0.location < $1.location }) else { break }
            if rp.location != NSNotFound && rp.location < r.location {
                out += "\n"
                i = rp.location + rp.length
                continue
            }
            let gt = scanner.range(of: ">", options: [], range: NSRange(location: r.location, length: len - r.location))
            guard gt.location != NSNotFound else { break }
            let start = gt.location + 1
            let end = scanner.range(of: close, options: [], range: NSRange(location: start, length: len - start))
            guard end.location != NSNotFound else { break }
            out += unescape(scanner.substring(with: NSRange(location: start, length: end.location - start)))
            i = end.location + end.length
        }
        return out
    }

    private static func stripTags(_ xml: String) -> String {
        let noTags = xml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let collapsed = noTags.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        return unescape(collapsed)
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// قارئ ZIP بسيط (يكفي لملفات Office).
struct ZipArchive {
    private struct Entry { let method: UInt16; let compSize: Int; let size: Int; let localOffset: Int }
    private let data: Data
    private var entries: [String: Entry] = [:]
    var names: [String] { Array(entries.keys) }

    init?(data: Data) {
        self.data = data
        let bytes = [UInt8](data)
        guard bytes.count > 22 else { return nil }
        // ابحث عن نهاية الدليل المركزي
        var eocd = -1
        var i = bytes.count - 22
        let stop = max(0, bytes.count - 22 - 65_535)
        while i >= stop {
            if bytes[i] == 0x50 && bytes[i + 1] == 0x4b && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x02014b50 else { break }
            let method = UInt16(u16(p + 10))
            let comp = u32(p + 20), size = u32(p + 24)
            let nLen = u16(p + 28), eLen = u16(p + 30), cLen = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nLen <= bytes.count else { break }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nLen)], as: UTF8.self)
            entries[name] = Entry(method: method, compSize: comp, size: size, localOffset: local)
            p += 46 + nLen + eLen + cLen
        }
        if entries.isEmpty { return nil }
    }

    func read(_ name: String) -> String? {
        guard let e = entries[name] else { return nil }
        let bytes = data
        let lo = e.localOffset
        guard lo + 30 <= bytes.count else { return nil }
        let base = bytes.startIndex
        func u16(_ o: Int) -> Int { Int(bytes[base + o]) | Int(bytes[base + o + 1]) << 8 }
        let start = lo + 30 + u16(lo + 26) + u16(lo + 28)
        guard start + e.compSize <= bytes.count else { return nil }
        let comp = bytes.subdata(in: (base + start)..<(base + start + e.compSize))
        if e.method == 0 { return String(decoding: comp, as: UTF8.self) }
        guard e.method == 8, e.size > 0, e.compSize > 0 else { return nil }
        var out = Data(count: e.size)
        let written = out.withUnsafeMutableBytes { dst in
            comp.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, e.size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, e.compSize,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return String(decoding: out.prefix(written), as: UTF8.self)
    }
}
