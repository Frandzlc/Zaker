import SwiftUI
import SwiftData
import UIKit

// MARK: - بطاقات المراجعة

struct DeckListView: View {
    @Environment(\.modelContext) private var ctx
    let book: Book
    @State private var showSetup = false
    @State private var created: Deck?
    @State private var openDeck: Deck?

    private var decks: [Deck] { book.decks.sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        List {
            Section {
                Button { showSetup = true } label: {
                    Label(tr("سوّ بطاقات جديدة بالـAI", "Create new AI flashcards"), systemImage: "sparkles")
                        .font(.headline)
                }
            }
            if !decks.isEmpty {
                Section(tr("مجموعاتك", "Your decks")) {
                    ForEach(decks) { d in
                        NavigationLink { DeckStudyView(deck: d) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(d.title).font(.headline).lineLimit(2)
                                Text(tr("\(d.cardCount) بطاقة · ", "\(d.cardCount) cards · ") + d.createdAt.shortLabel)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in
                        for i in idx { ctx.delete(decks[i]) }
                        try? ctx.save()
                    }
                }
            }
        }
        .navigationTitle(tr("بطاقات المراجعة", "Flashcards"))
        .sheet(isPresented: $showSetup, onDismiss: {
            if let c = created { openDeck = c; created = nil }
        }) {
            DeckSetupView(book: book) { created = $0 }.appLanguage()
        }
        .navigationDestination(item: $openDeck) { DeckStudyView(deck: $0) }
    }
}

struct DeckSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    let book: Book
    let onCreated: (Deck) -> Void

    @State private var count = 20
    @State private var usePages = false
    @State private var fromPage = 1
    @State private var toPage = 10
    @State private var focus = ""
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if working {
                    WorkingView(text: tr("الـAI يجهز البطاقات", "The AI is preparing your cards"))
                } else {
                    Form {
                        if let errorText { Section { ErrorBox(message: errorText) } }
                        Section(tr("البطاقات", "Cards")) {
                            Picker(tr("العدد", "Count"), selection: $count) {
                                ForEach([10, 20, 30, 50], id: \.self) { Text("\($0)").tag($0) }
                            }
                        }
                        ScopeFields(book: book, usePages: $usePages, fromPage: $fromPage, toPage: $toPage, focus: $focus)
                        Section {
                            Button(action: generate) {
                                Label(tr("سوّ البطاقات", "Generate cards"), systemImage: "sparkles")
                                    .frame(maxWidth: .infinity).font(.headline)
                            }
                        }
                    }
                }
            }
            .navigationTitle(tr("بطاقات جديدة", "New flashcards"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("إلغاء", "Cancel")) { dismiss() }.disabled(working)
                }
            }
            .interactiveDismissDisabled(working)
            .onAppear { toPage = min(10, max(1, book.pageCount)) }
        }
    }

    private func generate() {
        errorText = nil
        working = true
        Task {
            do {
                let p = try await AI.makeDeck(book: book, count: count,
                                              from: usePages ? fromPage : 0, to: usePages ? toPage : 0, focus: focus)
                let deck = Deck(title: p.title, payload: try JSONEncoder().encode(p), cardCount: p.cards.count, book: book)
                ctx.insert(deck)
                try? ctx.save()
                working = false
                onCreated(deck)
                dismiss()
            } catch {
                working = false
                errorText = error.localizedDescription
            }
        }
    }
}

struct DeckStudyView: View {
    let deck: Deck
    @State private var all: [FlashCard] = []
    @State private var queue: [FlashCard] = []
    @State private var index = 0
    @State private var flipped = false
    @State private var known = 0
    @State private var unknown: [FlashCard] = []
    @State private var done = false

    var body: some View {
        VStack(spacing: 20) {
            if queue.isEmpty {
                ContentUnavailableView(tr("ما فيه بطاقات", "No cards"), systemImage: "rectangle.on.rectangle")
            } else if done {
                finishedView
            } else {
                Text(tr("بطاقة \(index + 1) من \(queue.count)", "Card \(index + 1) of \(queue.count)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(index), total: Double(queue.count)).tint(.teal)

                card(queue[index])
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { flipped.toggle() }
                    }

                Text(flipped ? tr("عرفتها؟", "Did you know it?") : tr("اضغط على البطاقة عشان تشوف الجواب", "Tap the card to see the answer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Button { answer(false) } label: {
                        Label(tr("ما عرفتها", "Didn't know"), systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(.red)
                    Button { answer(true) } label: {
                        Label(tr("عرفتها", "Knew it"), systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                }
                .controlSize(.large)
                .disabled(!flipped)
            }
        }
        .padding()
        .navigationTitle(deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { restart(with: all.shuffled()) } label: { Image(systemName: "shuffle") }
            }
        }
        .onAppear {
            guard all.isEmpty, let p = try? JSONDecoder().decode(DeckPayload.self, from: deck.payload) else { return }
            all = p.cards
            queue = p.cards
        }
    }

    private func card(_ c: FlashCard) -> some View {
        ZStack {
            face(text: c.front, label: tr("السؤال", "Question"), color: .teal)
                .opacity(flipped ? 0 : 1)
            face(text: c.back, label: tr("الجواب", "Answer"), color: Theme.accent)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipped ? 1 : 0)
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .frame(maxWidth: .infinity)
        .frame(height: 340)
    }

    private func face(text: String, label: String, color: Color) -> some View {
        VStack(spacing: 14) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
            ScrollView {
                Text(text)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color.gradient, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: color.opacity(0.35), radius: 12, y: 6)
        .textDirection(for: text)
    }

    private func answer(_ knew: Bool) {
        if knew { known += 1 } else { unknown.append(queue[index]) }
        flipped = false
        if index + 1 < queue.count {
            index += 1
        } else {
            done = true
        }
    }

    private func restart(with cards: [FlashCard]) {
        queue = cards
        index = 0
        known = 0
        unknown = []
        flipped = false
        done = false
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Image(systemName: unknown.isEmpty ? "star.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundStyle(unknown.isEmpty ? .yellow : .teal)
            Text(tr("خلصت المجموعة!", "Deck complete!")).font(.title2.bold())
            Text(tr("عرفت \(known) من \(queue.count)", "You knew \(known) of \(queue.count)"))
                .foregroundStyle(.secondary)
            if !unknown.isEmpty {
                Button { restart(with: unknown) } label: {
                    Label(tr("راجع اللي ما عرفتها (\(unknown.count))", "Review missed cards (\(unknown.count))"),
                          systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Button { restart(with: all) } label: {
                Label(tr("ابدأ من جديد", "Start over"), systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - الملخصات

struct SummaryListView: View {
    @Environment(\.modelContext) private var ctx
    let book: Book
    @State private var showSetup = false
    @State private var created: Summary?
    @State private var openSummary: Summary?

    private var items: [Summary] { book.summaries.sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        List {
            Section {
                Button { showSetup = true } label: {
                    Label(tr("سوّ ملخص جديد بالـAI", "Create a new AI summary"), systemImage: "sparkles").font(.headline)
                }
            }
            if !items.isEmpty {
                Section(tr("ملخصاتك", "Your summaries")) {
                    ForEach(items) { s in
                        NavigationLink { SummaryDetailView(summary: s) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.title).font(.headline).lineLimit(2)
                                Text(s.detail + " · " + s.createdAt.shortLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in
                        for i in idx { ctx.delete(items[i]) }
                        try? ctx.save()
                    }
                }
            }
        }
        .navigationTitle(tr("الملخصات", "Summaries"))
        .sheet(isPresented: $showSetup, onDismiss: {
            if let c = created { openSummary = c; created = nil }
        }) {
            SummarySetupView(book: book) { created = $0 }.appLanguage()
        }
        .navigationDestination(item: $openSummary) { SummaryDetailView(summary: $0) }
    }
}

struct SummarySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    let book: Book
    let onCreated: (Summary) -> Void

    @State private var detailed = false
    @State private var usePages = false
    @State private var fromPage = 1
    @State private var toPage = 10
    @State private var focus = ""
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if working {
                    WorkingView(text: tr("الـAI يلخص الكتاب", "The AI is summarizing the book"))
                } else {
                    Form {
                        if let errorText { Section { ErrorBox(message: errorText) } }
                        Section(tr("الطول", "Length")) {
                            Picker(tr("الطول", "Length"), selection: $detailed) {
                                Text(tr("مختصر", "Brief")).tag(false)
                                Text(tr("مفصّل", "Detailed")).tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                        ScopeFields(book: book, usePages: $usePages, fromPage: $fromPage, toPage: $toPage, focus: $focus)
                        Section {
                            Button(action: generate) {
                                Label(tr("لخّص", "Summarize"), systemImage: "sparkles")
                                    .frame(maxWidth: .infinity).font(.headline)
                            }
                        }
                    }
                }
            }
            .navigationTitle(tr("ملخص جديد", "New summary"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("إلغاء", "Cancel")) { dismiss() }.disabled(working)
                }
            }
            .interactiveDismissDisabled(working)
            .onAppear { toPage = min(10, max(1, book.pageCount)) }
        }
    }

    private func generate() {
        errorText = nil
        working = true
        Task {
            do {
                let p = try await AI.makeSummary(book: book, detailed: detailed,
                                                 from: usePages ? fromPage : 0, to: usePages ? toPage : 0, focus: focus)
                var detail = detailed ? tr("مفصّل", "Detailed") : tr("مختصر", "Brief")
                if usePages { detail += tr(" · ص \(fromPage)–\(toPage)", " · p. \(fromPage)–\(toPage)") }
                let s = Summary(title: p.title, payload: try JSONEncoder().encode(p), detail: detail, book: book)
                ctx.insert(s)
                try? ctx.save()
                working = false
                onCreated(s)
                dismiss()
            } catch {
                working = false
                errorText = error.localizedDescription
            }
        }
    }
}

struct SummaryDetailView: View {
    @Environment(\.modelContext) private var ctx
    let summary: Summary
    @State private var payload: SummaryPayload?
    @State private var savedNote = false

    var body: some View {
        ScrollView {
            if let p = payload {
                VStack(alignment: .leading, spacing: 18) {
                    Text(p.title).font(.title2.bold())
                    Text(p.overview)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                    ForEach(p.sections, id: \.self) { s in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.heading).font(.headline).foregroundStyle(Theme.accent)
                            ForEach(s.points, id: \.self) { pt in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•").bold()
                                    Text(pt).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    }

                    if !p.keyTerms.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tr("مصطلحات مهمة", "Key terms")).font(.headline)
                            ForEach(p.keyTerms, id: \.self) { k in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(k.term).font(.subheadline.bold())
                                    Text(k.definition).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding()
                .textDirection(for: p.overview)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let p = payload {
                    ShareLink(item: Self.plainText(p)) { Image(systemName: "square.and.arrow.up") }
                    Button {
                        ctx.insert(Note(title: p.title, body: Self.plainText(p), book: summary.book))
                        try? ctx.save()
                        savedNote = true
                    } label: {
                        Image(systemName: savedNote ? "checkmark" : "note.text.badge.plus")
                    }
                    .disabled(savedNote)
                }
            }
        }
        .onAppear {
            if payload == nil { payload = try? JSONDecoder().decode(SummaryPayload.self, from: summary.payload) }
        }
    }

    static func plainText(_ p: SummaryPayload) -> String {
        var out = p.title + "\n\n" + p.overview + "\n"
        for s in p.sections {
            out += "\n" + s.heading + "\n"
            for pt in s.points { out += "• " + pt + "\n" }
        }
        if !p.keyTerms.isEmpty {
            out += "\n" + tr("مصطلحات مهمة", "Key terms") + "\n"
            for k in p.keyTerms { out += "• " + k.term + ": " + k.definition + "\n" }
        }
        return out
    }
}

// MARK: - اسأل الكتاب

struct ChatView: View {
    @Environment(\.modelContext) private var ctx
    let book: Book
    @State private var input = ""
    @State private var sending = false
    @State private var errorText: String?
    @State private var savedID: PersistentIdentifier?
    @FocusState private var focused: Bool

    private var messages: [ChatMsg] { book.messages.sorted { $0.createdAt < $1.createdAt } }

    private var suggestions: [String] {
        Prefs.uiLang == "en"
            ? ["What is the main idea of this book?", "Explain the most important concepts simply", "What should I focus on for the exam?"]
            : ["وش الفكرة الرئيسية للكتاب؟", "اشرح لي أهم المفاهيم ببساطة", "وش أهم شي أركز عليه للاختبار؟"]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                                    .font(.system(size: 44)).foregroundStyle(.pink)
                                Text(tr("اسأل أي سؤال عن الكتاب", "Ask anything about the book"))
                                    .font(.headline)
                                ForEach(suggestions, id: \.self) { s in
                                    Button { send(s) } label: {
                                        Text(s).font(.subheadline)
                                            .padding(.horizontal, 14).padding(.vertical, 10)
                                            .background(Theme.card, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 40)
                        }
                        ForEach(messages) { m in
                            bubble(m).id(m.persistentModelID)
                        }
                        if sending {
                            HStack {
                                ProgressView()
                                Text(tr("يفكر…", "Thinking…")).font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("typing")
                        }
                        if let errorText {
                            ErrorBox(message: errorText).padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.persistentModelID, anchor: .bottom) }
                }
                .onChange(of: sending) { _, v in
                    if v { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
                }
            }

            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField(tr("اكتب سؤالك…", "Type your question…"), text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                    .focused($focused)
                Button { send(input) } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                }
                .disabled(sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
            .background(.bar)
        }
        .navigationTitle(tr("اسأل الكتاب", "Ask the book"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        for m in book.messages { ctx.delete(m) }
                        try? ctx.save()
                    } label: {
                        Label(tr("مسح المحادثة", "Clear chat"), systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ m: ChatMsg) -> some View {
        let isUser = m.role == "user"
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                MarkdownText(text: m.text)
                    .textSelection(.enabled)
                    .foregroundStyle(isUser ? Color.white : Color.primary)
                if !isUser {
                    HStack(spacing: 16) {
                        Button {
                            UIPasteboard.general.string = m.text
                        } label: { Image(systemName: "doc.on.doc") }
                        Button {
                            let title = String(m.text.prefix(40))
                            ctx.insert(Note(title: title, body: m.text, book: book))
                            try? ctx.save()
                            savedID = m.persistentModelID
                        } label: {
                            Image(systemName: savedID == m.persistentModelID ? "checkmark" : "note.text.badge.plus")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(isUser ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card),
                        in: RoundedRectangle(cornerRadius: 18))
            .textDirection(for: m.text)
            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        input = ""
        errorText = nil
        var h: [(role: String, text: String)] = Array(messages.suffix(19)).map { (role: $0.role, text: $0.text) }
        h.append((role: "user", text: text))
        // أول رسالة لازم تكون من المستخدم
        while let first = h.first, first.role != "user" { h.removeFirst() }
        let history = h
        ctx.insert(ChatMsg(role: "user", text: text, book: book))
        try? ctx.save()
        sending = true
        Task {
            do {
                let reply = try await AI.ask(book: book, history: history)
                ctx.insert(ChatMsg(role: "model", text: reply, book: book))
                try? ctx.save()
            } catch {
                errorText = error.localizedDescription
            }
            sending = false
        }
    }
}

// MARK: - الملاحظات

struct NotesListView: View {
    @Environment(\.modelContext) private var ctx
    let book: Book
    @State private var openNote: Note?

    private var notes: [Note] { book.notes.sorted { $0.updatedAt > $1.updatedAt } }

    var body: some View {
        List {
            Section {
                Button {
                    let n = Note(title: "", body: "", book: book)
                    ctx.insert(n)
                    try? ctx.save()
                    openNote = n
                } label: {
                    Label(tr("ملاحظة جديدة", "New note"), systemImage: "square.and.pencil").font(.headline)
                }
            }
            if !notes.isEmpty {
                Section {
                    ForEach(notes) { n in
                        NavigationLink { NoteEditorView(note: n) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(n.title.isEmpty ? tr("بدون عنوان", "Untitled") : n.title)
                                    .font(.headline).lineLimit(1)
                                Text(n.body.isEmpty ? tr("فاضية", "Empty") : n.body)
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                Text(n.updatedAt.shortLabel).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .textDirection(for: n.title + n.body)
                        }
                    }
                    .onDelete { idx in
                        for i in idx { ctx.delete(notes[i]) }
                        try? ctx.save()
                    }
                }
            }
        }
        .navigationTitle(tr("ملاحظاتي", "My notes"))
        .navigationDestination(item: $openNote) { NoteEditorView(note: $0) }
    }
}

struct NoteEditorView: View {
    @Bindable var note: Note
    @FocusState private var bodyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(tr("العنوان", "Title"), text: $note.title)
                .font(.title2.bold())
                .padding(.horizontal)
                .padding(.top, 8)
            TextEditor(text: $note.body)
                .font(.body)
                .padding(.horizontal, 12)
                .focused($bodyFocused)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: note.title + "\n\n" + note.body) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .keyboard) {
                HStack { Spacer(); Button(tr("تم", "Done")) { bodyFocused = false } }
            }
        }
        .onChange(of: note.body) { _, _ in note.updatedAt = .now }
        .onChange(of: note.title) { _, _ in note.updatedAt = .now }
        .onAppear { if note.body.isEmpty && note.title.isEmpty { bodyFocused = true } }
    }
}
