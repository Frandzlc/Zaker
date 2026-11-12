import Foundation
import Security

// MARK: - الإعدادات واللغة

enum Prefs {
    static let uiLangKey = "uiLang"
    static let outLangKey = "outLang"
    static let modelKey = "geminiModel"
    static let defaultModel = "gemini-3.8-flash"

    static var uiLang: String { UserDefaults.standard.string(forKey: uiLangKey) ?? "ar" }
    static var outLang: String { UserDefaults.standard.string(forKey: outLangKey) ?? "auto" }
    static var model: String {
        let m = (UserDefaults.standard.string(forKey: modelKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? defaultModel : m
    }
}

/// نص بلغتين: يرجع العربي أو الإنجليزي حسب لغة الواجهة.
func tr(_ ar: String, _ en: String) -> String {
    Prefs.uiLang == "en" ? en : ar
}

extension String {
    /// هل أول حرف قوي في النص عربي؟ (عشان نعرض النص من اليمين أو اليسار)
    var isRTL: Bool {
        for scalar in unicodeScalars {
            let v = scalar.value
            if (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) { return true }
            if CharacterSet.letters.contains(scalar) { return false }
        }
        return Prefs.uiLang == "ar"
    }
}

// MARK: - تخزين المفتاح في Keychain

enum Keychain {
    private static let service = "com.fahad.zaker"
    private static let account = "gemini-api-key"

    static func get() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func set(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Gemini API

struct GeminiError: LocalizedError {
    let message: String
    var status: Int = 0
    var errorDescription: String? { message }
}

struct Gemini {
    static let base = "https://generativelanguage.googleapis.com"
    let key: String
    let model: String

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 600
        c.timeoutIntervalForResource = 1200
        return URLSession(configuration: c)
    }()

    /// يرفع ملف PDF عن طريق Files API ويرجع رابطه.
    func upload(fileURL: URL, displayName: String, mimeType: String = "application/pdf") async throws -> (uri: String, name: String) {
        let data = try Data(contentsOf: fileURL)

        var start = URLRequest(url: URL(string: "\(Self.base)/upload/v1beta/files")!)
        start.httpMethod = "POST"
        start.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        start.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        start.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        start.setValue("\(data.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        start.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        start.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let safeName = String(displayName.prefix(100))
        start.httpBody = try JSONSerialization.data(withJSONObject: ["file": ["display_name": safeName]])

        let (d1, r1) = try await Self.session.data(for: start)
        let s1 = (r1 as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(s1),
              let uploadURLString = (r1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-goog-upload-url"),
              let uploadURL = URL(string: uploadURLString) else {
            throw GeminiError(message: Self.errorText(d1, status: s1), status: s1)
        }

        var up = URLRequest(url: uploadURL)
        up.httpMethod = "POST"
        up.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        up.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        up.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        let (d2, r2) = try await Self.session.upload(for: up, from: data)
        let s2 = (r2 as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(s2),
              let obj = try? JSONSerialization.jsonObject(with: d2) as? [String: Any] else {
            throw GeminiError(message: Self.errorText(d2, status: s2), status: s2)
        }
        let file = (obj["file"] as? [String: Any]) ?? obj
        guard let uri = file["uri"] as? String, let name = file["name"] as? String else {
            throw GeminiError(message: tr("ما رجع رابط للملف بعد الرفع.", "Upload returned no file URI."))
        }
        var state = (file["state"] as? String) ?? "ACTIVE"

        // ننتظر لين يجهز الملف
        var tries = 0
        while state == "PROCESSING" && tries < 120 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            tries += 1
            var get = URLRequest(url: URL(string: "\(Self.base)/v1beta/\(name)")!)
            get.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let (d3, _) = try await Self.session.data(for: get)
            if let o = try? JSONSerialization.jsonObject(with: d3) as? [String: Any] {
                let f = (o["file"] as? [String: Any]) ?? o
                state = (f["state"] as? String) ?? "ACTIVE"
            }
        }
        if state == "FAILED" {
            throw GeminiError(message: tr("Gemini ما قدر يقرأ الملف.", "Gemini could not process the file."))
        }
        return (uri, name)
    }

    /// يرسل طلب ويرجع النص.
    func generate(contents: [[String: Any]], system: String?, schema: [String: Any]?) async throws -> String {
        let urlString = "\(Self.base)/v1beta/models/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            throw GeminiError(message: tr("اسم الموديل غير صحيح.", "Invalid model name."))
        }
        var body: [String: Any] = ["contents": contents]
        if let system {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }
        var config: [String: Any] = ["temperature": 0.6]
        if let schema {
            config["responseMimeType"] = "application/json"
            config["responseSchema"] = schema
        }
        body["generationConfig"] = config

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await Self.session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw GeminiError(message: Self.errorText(data, status: status), status: status)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError(message: tr("رد غير مفهوم من Gemini.", "Unreadable response from Gemini."))
        }
        let candidates = obj["candidates"] as? [[String: Any]] ?? []
        guard let first = candidates.first else {
            if let fb = obj["promptFeedback"] as? [String: Any], let reason = fb["blockReason"] as? String {
                throw GeminiError(message: tr("Gemini رفض الطلب: ", "Gemini blocked the request: ") + reason)
            }
            throw GeminiError(message: tr("Gemini ما رجع أي رد.", "Gemini returned no answer."))
        }
        let parts = ((first["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = parts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
        if text.isEmpty {
            let reason = (first["finishReason"] as? String) ?? "EMPTY"
            throw GeminiError(message: tr("الرد فاضي (\(reason)). جرّب مرة ثانية.", "Empty answer (\(reason)). Try again."))
        }
        return text
    }

    static func errorText(_ data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any],
           let msg = err["message"] as? String {
            if status == 400 && msg.lowercased().contains("api key") {
                return tr("مفتاح Gemini غير صحيح. تأكد منه في الإعدادات.", "Invalid Gemini API key. Check Settings.")
            }
            if status == 429 {
                return tr("وصلت حد الاستخدام المجاني مؤقتًا. انتظر دقيقة وجرّب.", "Rate limit reached. Wait a minute and retry.") + "\n" + msg
            }
            return "(\(status)) " + msg
        }
        if status == 0 {
            return tr("تأكد من اتصالك بالإنترنت.", "Check your internet connection.")
        }
        return "HTTP \(status)"
    }
}

// MARK: - خدمة الـ AI للتطبيق

@MainActor
enum AI {
    static func client() throws -> Gemini {
        let key = Keychain.get()
        guard !key.isEmpty else {
            throw GeminiError(message: tr("أضف مفتاح Gemini من الإعدادات أول.", "Add your Gemini API key in Settings first."))
        }
        return Gemini(key: key, model: Prefs.model)
    }

    static var languageRule: String {
        switch Prefs.outLang {
        case "ar": return "Write ALL of your output in Arabic (Modern Standard Arabic), even if the book is written in another language."
        case "en": return "Write ALL of your output in English, even if the book is written in another language."
        default: return "Write your output in the same language the book is written in."
        }
    }

    /// أنواع الملفات اللي Gemini يقرأها مباشرة.
    static func geminiReadable(_ mime: String) -> Bool {
        mime.hasPrefix("image/") || mime.hasPrefix("audio/") || mime.hasPrefix("video/") || mime == "application/pdf"
    }

    static func scopeRule(book: Book, from: Int, to: Int) -> String {
        if book.isPDF && from > 0 && to >= from {
            return "Use ONLY pages \(from) to \(to) of the attached PDF (PDF page numbers)."
        }
        return "Cover the whole book."
    }

    private static func bookPart(_ book: Book, client: Gemini, force: Bool) async throws -> [String: Any] {
        let mime = book.isPDF ? "application/pdf" : book.mimeType
        let useFile = book.isPDF || (!book.fileName.isEmpty && Self.geminiReadable(mime)
                                     && book.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if !useFile {
            guard !book.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GeminiError(message: tr("الذكاء الاصطناعي ما يقدر يقرأ هالنوع من الملفات. حوّله لـ PDF وجرب.",
                                              "The AI can't read this file type. Convert it to PDF and try again."))
            }
            return ["text": "BOOK CONTENT START\n" + book.textContent + "\nBOOK CONTENT END"]
        }
        let expired = book.uploadedAt.map { Date().timeIntervalSince($0) > 40 * 3600 } ?? true
        if force || book.remoteURI.isEmpty || expired {
            let r = try await client.upload(fileURL: book.fileURL, displayName: book.title, mimeType: mime)
            book.remoteURI = r.uri
            book.remoteName = r.name
            book.uploadedAt = .now
        }
        return ["fileData": ["mimeType": mime, "fileUri": book.remoteURI]]
    }

    /// turns: [(role, text)] — الكتاب ينضاف تلقائيًا لأول رسالة.
    static func run(book: Book,
                    turns: [(role: String, text: String)],
                    system: String,
                    schema: [String: Any]?,
                    applyLanguageRule: Bool = true) async throws -> String {
        let c = try client()

        func build(_ part: [String: Any]) -> [[String: Any]] {
            var out: [[String: Any]] = []
            for (i, t) in turns.enumerated() {
                var parts: [[String: Any]] = []
                if i == 0 { parts.append(part) }
                parts.append(["text": t.text])
                out.append(["role": t.role, "parts": parts])
            }
            return out
        }

        let sys = applyLanguageRule ? system + "\n" + languageRule : system
        do {
            let part = try await bookPart(book, client: c, force: false)
            return try await c.generate(contents: build(part), system: sys, schema: schema)
        } catch let e as GeminiError where !book.remoteURI.isEmpty && (e.status == 403 || e.status == 404 || (e.status == 400 && e.message.lowercased().contains("file"))) {
            // الملف انتهت صلاحيته عند Gemini: نرفعه من جديد
            let part = try await bookPart(book, client: c, force: true)
            return try await c.generate(contents: build(part), system: sys, schema: schema)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        }
        guard let data = t.data(using: .utf8) else {
            throw GeminiError(message: tr("رد غير مفهوم.", "Unreadable response."))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GeminiError(message: tr("الـAI رجّع رد بشكل غلط. جرّب مرة ثانية.", "The AI returned a malformed answer. Please try again."))
        }
    }

    // MARK: Schemas

    static let quizSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "title": ["type": "STRING"],
            "questions": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "question": ["type": "STRING"],
                        "options": ["type": "ARRAY", "items": ["type": "STRING"]],
                        "correctIndex": ["type": "INTEGER"],
                        "explanation": ["type": "STRING"],
                        "page": ["type": "STRING"],
                    ],
                    "required": ["question", "options", "correctIndex", "explanation"],
                ],
            ],
        ],
        "required": ["title", "questions"],
    ]

    static let deckSchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "title": ["type": "STRING"],
            "cards": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "front": ["type": "STRING"],
                        "back": ["type": "STRING"],
                    ],
                    "required": ["front", "back"],
                ],
            ],
        ],
        "required": ["title", "cards"],
    ]

    static let summarySchema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "title": ["type": "STRING"],
            "overview": ["type": "STRING"],
            "sections": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "heading": ["type": "STRING"],
                        "points": ["type": "ARRAY", "items": ["type": "STRING"]],
                    ],
                    "required": ["heading", "points"],
                ],
            ],
            "keyTerms": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "term": ["type": "STRING"],
                        "definition": ["type": "STRING"],
                    ],
                    "required": ["term", "definition"],
                ],
            ],
        ],
        "required": ["title", "overview", "sections", "keyTerms"],
    ]

    // MARK: Tasks

    static func makeQuiz(book: Book, count: Int, kind: String, difficulty: String, from: Int, to: Int, focus: String) async throws -> QuizPayload {
        let kindRule: String
        switch kind {
        case "mcq": kindRule = "All questions are multiple choice with exactly 4 options."
        case "tf": kindRule = "All questions are true/false. Options must be exactly two: the word for True then the word for False, in the output language."
        default: kindRule = "Mix question types: about 70% multiple choice with exactly 4 options, and 30% true/false with exactly two options (True then False, in the output language)."
        }
        let focusRule = focus.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "Focus especially on: \(focus)."
        let prompt = """
        Create a quiz with exactly \(count) questions from the attached book.
        \(scopeRule(book: book, from: from, to: to))
        Difficulty: \(difficulty).
        \(kindRule)
        \(focusRule)
        Rules:
        - Base every question strictly on the book's content; do not invent facts.
        - correctIndex is the 0-based index of the correct option. Vary the position of the correct answer.
        - Wrong options must be plausible.
        - explanation: one or two sentences explaining why the answer is correct.
        - page: the PDF page number where the answer is found, if you know it.
        - title: a short title for this quiz.
        """
        let text = try await run(book: book, turns: [("user", prompt)],
                                 system: "You are an expert teacher who writes excellent exam questions.",
                                 schema: quizSchema)
        var payload = try decode(QuizPayload.self, from: text)
        payload.questions = payload.questions.filter { $0.options.count >= 2 && $0.options.indices.contains($0.correctIndex) }
        guard !payload.questions.isEmpty else {
            throw GeminiError(message: tr("ما طلعت أسئلة صالحة. جرّب مرة ثانية.", "No valid questions were produced. Try again."))
        }
        return payload
    }

    static func makeDeck(book: Book, count: Int, from: Int, to: Int, focus: String) async throws -> DeckPayload {
        let focusRule = focus.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "Focus especially on: \(focus)."
        let prompt = """
        Create exactly \(count) study flashcards from the attached book.
        \(scopeRule(book: book, from: from, to: to))
        \(focusRule)
        - front: a short question, term, or concept.
        - back: a clear, concise answer (max 3 sentences).
        - Cover the most important ideas, definitions, facts and relationships.
        - title: a short title for this deck.
        """
        let text = try await run(book: book, turns: [("user", prompt)],
                                 system: "You are an expert tutor who creates effective spaced-repetition flashcards.",
                                 schema: deckSchema)
        let payload = try decode(DeckPayload.self, from: text)
        guard !payload.cards.isEmpty else {
            throw GeminiError(message: tr("ما طلعت بطاقات. جرّب مرة ثانية.", "No cards were produced. Try again."))
        }
        return payload
    }

    static func makeSummary(book: Book, detailed: Bool, from: Int, to: Int, focus: String) async throws -> SummaryPayload {
        let focusRule = focus.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "Focus especially on: \(focus)."
        let lengthRule = detailed
            ? "Make it detailed: 6 to 12 sections, each with 4 to 8 points, and 8 to 15 key terms."
            : "Make it brief: 3 to 5 sections, each with 2 to 4 points, and 4 to 8 key terms."
        let prompt = """
        Summarize the attached book for a student who is studying for an exam.
        \(scopeRule(book: book, from: from, to: to))
        \(lengthRule)
        \(focusRule)
        - overview: a short paragraph with the main idea.
        - sections: follow the book's structure (chapters/topics), each heading clear.
        - keyTerms: important terms with short definitions.
        - title: a short title for this summary.
        """
        let text = try await run(book: book, turns: [("user", prompt)],
                                 system: "You are an expert at writing clear, accurate study summaries.",
                                 schema: summarySchema)
        return try decode(SummaryPayload.self, from: text)
    }

    static func ask(book: Book, history: [(role: String, text: String)]) async throws -> String {
        try await run(book: book, turns: history,
                      system: """
                      You are a helpful study assistant. Answer questions using the attached book.
                      Mention page numbers when helpful. If the answer is not in the book, say so clearly, then give a short general answer.
                      Use short paragraphs and simple Markdown (bold, bullet lists).
                      Always reply in the same language as the user's latest question (Arabic or English).
                      """,
                      schema: nil,
                      applyLanguageRule: false)
    }
}
