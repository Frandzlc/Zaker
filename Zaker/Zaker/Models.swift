import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var fileName: String
    var isPDF: Bool
    var textContent: String
    var pageCount: Int
    var addedAt: Date
    var lastOpened: Date
    /// رابط الملف بعد رفعه لـ Gemini (يبقى صالح 48 ساعة)
    var remoteURI: String
    var remoteName: String
    var uploadedAt: Date?
    /// نوع الملف (MIME) للملفات غير PDF، مثل image/jpeg. فاضي للنصوص.
    var mimeType: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Note.book) var notes: [Note] = []
    @Relationship(deleteRule: .cascade, inverse: \Quiz.book) var quizzes: [Quiz] = []
    @Relationship(deleteRule: .cascade, inverse: \Deck.book) var decks: [Deck] = []
    @Relationship(deleteRule: .cascade, inverse: \Summary.book) var summaries: [Summary] = []
    @Relationship(deleteRule: .cascade, inverse: \ChatMsg.book) var messages: [ChatMsg] = []

    init(title: String, fileName: String = "", isPDF: Bool, textContent: String = "", pageCount: Int = 0) {
        self.id = UUID()
        self.title = title
        self.fileName = fileName
        self.isPDF = isPDF
        self.textContent = textContent
        self.pageCount = pageCount
        self.addedAt = .now
        self.lastOpened = .now
        self.remoteURI = ""
        self.remoteName = ""
        self.uploadedAt = nil
    }

    var fileURL: URL { BookFiles.directory.appendingPathComponent(fileName) }
    var isImage: Bool { mimeType.hasPrefix("image/") }
    var hasFile: Bool { !fileName.isEmpty }

    /// وصف قصير لنوع الكتاب.
    var kindLabel: String {
        if isPDF { return tr("\(pageCount) صفحة", "\(pageCount) pages") }
        if isImage { return tr("صورة", "Image") }
        if hasFile { return fileName.split(separator: ".").last.map { $0.uppercased() } ?? tr("ملف", "File") }
        return tr("نص", "Text")
    }

    var kindIcon: String {
        if isPDF { return "book.closed.fill" }
        if isImage { return "photo.fill" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType.hasPrefix("video/") { return "film.fill" }
        if hasFile { return "doc.fill" }
        return "doc.plaintext.fill"
    }
}

@Model
final class Note {
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var book: Book?

    init(title: String, body: String, book: Book?) {
        self.title = title
        self.body = body
        self.createdAt = .now
        self.updatedAt = .now
        self.book = book
    }
}

@Model
final class Quiz {
    var title: String
    var createdAt: Date
    var payload: Data
    var detail: String
    var questionCount: Int
    var lastScore: Int
    var bestScore: Int
    var book: Book?

    init(title: String, payload: Data, detail: String, questionCount: Int, book: Book?) {
        self.title = title
        self.createdAt = .now
        self.payload = payload
        self.detail = detail
        self.questionCount = questionCount
        self.lastScore = -1
        self.bestScore = -1
        self.book = book
    }
}

@Model
final class Deck {
    var title: String
    var createdAt: Date
    var payload: Data
    var cardCount: Int
    var book: Book?

    init(title: String, payload: Data, cardCount: Int, book: Book?) {
        self.title = title
        self.createdAt = .now
        self.payload = payload
        self.cardCount = cardCount
        self.book = book
    }
}

@Model
final class Summary {
    var title: String
    var createdAt: Date
    var payload: Data
    var detail: String
    var book: Book?

    init(title: String, payload: Data, detail: String, book: Book?) {
        self.title = title
        self.createdAt = .now
        self.payload = payload
        self.detail = detail
        self.book = book
    }
}

@Model
final class ChatMsg {
    var role: String   // "user" أو "model"
    var text: String
    var createdAt: Date
    var book: Book?

    init(role: String, text: String, book: Book?) {
        self.role = role
        self.text = text
        self.createdAt = .now
        self.book = book
    }
}

// MARK: - محتوى الـ AI (JSON)

struct QuizPayload: Codable {
    var title: String
    var questions: [QuizQuestion]
}

struct QuizQuestion: Codable, Hashable {
    var question: String
    var options: [String]
    var correctIndex: Int
    var explanation: String
    var page: String?
}

struct DeckPayload: Codable {
    var title: String
    var cards: [FlashCard]
}

struct FlashCard: Codable, Hashable {
    var front: String
    var back: String
}

struct SummaryPayload: Codable {
    var title: String
    var overview: String
    var sections: [SummarySection]
    var keyTerms: [KeyTerm]
}

struct SummarySection: Codable, Hashable {
    var heading: String
    var points: [String]
}

struct KeyTerm: Codable, Hashable {
    var term: String
    var definition: String
}

// MARK: - ملفات الكتب

enum BookFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Books", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// ينسخ الملف المختار لداخل التطبيق ويرجع اسمه الجديد.
    static func importFile(from source: URL) throws -> String {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.isEmpty ? "pdf" : source.pathExtension.lowercased()
        let name = UUID().uuidString + "." + ext
        let dest = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: dest)
        return name
    }

    static func delete(_ fileName: String) {
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }
}
