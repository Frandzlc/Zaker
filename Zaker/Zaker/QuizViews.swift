import SwiftUI
import SwiftData

struct QuizListView: View {
    @Environment(\.modelContext) private var ctx
    let book: Book
    @State private var showSetup = false
    @State private var created: Quiz?
    @State private var openQuiz: Quiz?

    private var quizzes: [Quiz] { book.quizzes.sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        List {
            Section {
                Button { showSetup = true } label: {
                    Label(tr("سوّ اختبار جديد بالـAI", "Create a new AI quiz"), systemImage: "sparkles")
                        .font(.headline)
                }
            }
            if !quizzes.isEmpty {
                Section(tr("اختباراتك", "Your quizzes")) {
                    ForEach(quizzes) { q in
                        NavigationLink {
                            QuizTakeView(quiz: q)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(q.title).font(.headline).lineLimit(2)
                                Text(q.detail).font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 10) {
                                    Text(q.createdAt.shortLabel)
                                    if q.bestScore >= 0 {
                                        Label(tr("أفضل نتيجة \(q.bestScore)/\(q.questionCount)",
                                                 "Best \(q.bestScore)/\(q.questionCount)"),
                                              systemImage: "trophy.fill")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete { idx in
                        for i in idx { ctx.delete(quizzes[i]) }
                        try? ctx.save()
                    }
                }
            }
        }
        .navigationTitle(tr("الاختبارات", "Quizzes"))
        .sheet(isPresented: $showSetup, onDismiss: {
            if let c = created { openQuiz = c; created = nil }
        }) {
            QuizSetupView(book: book) { quiz in created = quiz }
                .appLanguage()
        }
        .navigationDestination(item: $openQuiz) { q in QuizTakeView(quiz: q) }
    }
}

struct QuizSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    let book: Book
    let onCreated: (Quiz) -> Void

    @State private var count = 10
    @State private var kind = "mixed"
    @State private var difficulty = "medium"
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
                    WorkingView(text: tr("الـAI يقرأ الكتاب ويكتب الأسئلة", "The AI is reading the book and writing questions"))
                } else {
                    Form {
                        if let errorText {
                            Section { ErrorBox(message: errorText) }
                        }
                        Section(tr("الأسئلة", "Questions")) {
                            Picker(tr("العدد", "Count"), selection: $count) {
                                ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0)").tag($0) }
                            }
                            Picker(tr("النوع", "Type"), selection: $kind) {
                                Text(tr("منوّع", "Mixed")).tag("mixed")
                                Text(tr("اختيار من متعدد", "Multiple choice")).tag("mcq")
                                Text(tr("صح وخطأ", "True / False")).tag("tf")
                            }
                            Picker(tr("الصعوبة", "Difficulty"), selection: $difficulty) {
                                Text(tr("سهل", "Easy")).tag("easy")
                                Text(tr("متوسط", "Medium")).tag("medium")
                                Text(tr("صعب", "Hard")).tag("hard")
                            }
                        }
                        ScopeFields(book: book, usePages: $usePages, fromPage: $fromPage, toPage: $toPage, focus: $focus)
                        Section {
                            Button(action: generate) {
                                Label(tr("سوّ الاختبار", "Generate quiz"), systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                                    .font(.headline)
                            }
                        }
                    }
                }
            }
            .navigationTitle(tr("اختبار جديد", "New quiz"))
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
        let from = usePages ? fromPage : 0
        let to = usePages ? toPage : 0
        Task {
            do {
                let payload = try await AI.makeQuiz(book: book, count: count, kind: kind, difficulty: difficulty,
                                                    from: from, to: to, focus: focus)
                let data = try JSONEncoder().encode(payload)
                let diffName = difficulty == "easy" ? tr("سهل", "Easy") : difficulty == "hard" ? tr("صعب", "Hard") : tr("متوسط", "Medium")
                var detail = tr("\(payload.questions.count) سؤال · \(diffName)", "\(payload.questions.count) questions · \(diffName)")
                if usePages { detail += tr(" · ص \(fromPage)–\(toPage)", " · p. \(fromPage)–\(toPage)") }
                let quiz = Quiz(title: payload.title, payload: data, detail: detail,
                                questionCount: payload.questions.count, book: book)
                ctx.insert(quiz)
                try? ctx.save()
                working = false
                onCreated(quiz)
                dismiss()
            } catch {
                working = false
                errorText = error.localizedDescription
            }
        }
    }
}

struct QuizTakeView: View {
    @Bindable var quiz: Quiz
    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var chosen: [Int?] = []
    @State private var revealed = false
    @State private var finished = false

    var body: some View {
        Group {
            if questions.isEmpty {
                ContentUnavailableView(tr("ما فيه أسئلة", "No questions"), systemImage: "questionmark.circle")
            } else if finished {
                resultView
            } else {
                questionView
            }
        }
        .navigationTitle(quiz.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        guard questions.isEmpty, let p = try? JSONDecoder().decode(QuizPayload.self, from: quiz.payload) else { return }
        questions = p.questions
        chosen = Array(repeating: nil, count: p.questions.count)
    }

    private var questionView: some View {
        let q = questions[index]
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("سؤال \(index + 1) من \(questions.count)", "Question \(index + 1) of \(questions.count)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(index + (revealed ? 1 : 0)), total: Double(questions.count))
                        .tint(Theme.accent)
                }

                Text(q.question)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textDirection(for: q.question)

                VStack(spacing: 10) {
                    ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                        OptionButton(text: option,
                                     state: optionState(i, q: q),
                                     letter: letter(i)) {
                            guard !revealed else { return }
                            chosen[index] = i
                        }
                    }
                }

                if revealed {
                    let right = chosen[index] == q.correctIndex
                    VStack(alignment: .leading, spacing: 8) {
                        Label(right ? tr("إجابة صحيحة!", "Correct!") : tr("إجابة خاطئة", "Not quite"),
                              systemImage: right ? "checkmark.seal.fill" : "xmark.octagon.fill")
                            .font(.headline)
                            .foregroundStyle(right ? .green : .red)
                        Text(q.explanation)
                            .font(.subheadline)
                            .textDirection(for: q.explanation)
                        if let page = q.page, !page.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(tr("📖 صفحة \(page)", "📖 Page \(page)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((right ? Color.green : Color.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }

                Button(action: next) {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(chosen.indices.contains(index) ? chosen[index] == nil : true)
            }
            .padding()
        }
    }

    private var buttonTitle: String {
        if !revealed { return tr("تحقق", "Check") }
        return index + 1 < questions.count ? tr("السؤال التالي", "Next question") : tr("شوف النتيجة", "See results")
    }

    private func next() {
        if !revealed {
            revealed = true
            return
        }
        if index + 1 < questions.count {
            index += 1
            revealed = false
        } else {
            let score = correctCount
            quiz.lastScore = score
            quiz.bestScore = max(quiz.bestScore, score)
            finished = true
        }
    }

    private var correctCount: Int {
        zip(questions, chosen).filter { $0.0.correctIndex == $0.1 }.count
    }

    private func optionState(_ i: Int, q: QuizQuestion) -> OptionButton.Look {
        let picked = chosen.indices.contains(index) && chosen[index] == i
        if !revealed { return picked ? .selected : .normal }
        if i == q.correctIndex { return .correct }
        if picked { return .wrong }
        return .dimmed
    }

    private func letter(_ i: Int) -> String {
        let ar = ["أ", "ب", "ج", "د", "هـ", "و"]
        let en = ["A", "B", "C", "D", "E", "F"]
        let list = Prefs.uiLang == "ar" ? ar : en
        return i < list.count ? list[i] : "\(i + 1)"
    }

    private var resultView: some View {
        let score = correctCount
        let pct = questions.isEmpty ? 0 : Double(score) / Double(questions.count)
        let wrong = questions.indices.filter { chosen[$0] != questions[$0].correctIndex }
        return ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(pct >= 0.7 ? Color.green : pct >= 0.5 ? Color.orange : Color.red,
                                style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack {
                        Text("\(score)/\(questions.count)").font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("\(Int((pct * 100).rounded()))%").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 180, height: 180)
                .padding(.top)

                Text(pct >= 0.9 ? tr("ممتاز! 🌟", "Excellent! 🌟")
                     : pct >= 0.7 ? tr("شغل حلو 👏", "Nice work 👏")
                     : pct >= 0.5 ? tr("قريب، راجع الأخطاء 💪", "Close, review your mistakes 💪")
                     : tr("تحتاج مراجعة، تقدر عليها 📚", "Needs review, you've got this 📚"))
                    .font(.title3.bold())

                if !wrong.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("راجع هالأسئلة", "Review these questions")).font(.headline)
                        ForEach(wrong, id: \.self) { i in
                            let q = questions[i]
                            VStack(alignment: .leading, spacing: 6) {
                                Text(q.question).font(.subheadline.weight(.semibold))
                                Text("✓ " + q.options[q.correctIndex]).font(.subheadline).foregroundStyle(.green)
                                if let c = chosen[i], q.options.indices.contains(c) {
                                    Text("✗ " + q.options[c]).font(.caption).foregroundStyle(.red)
                                }
                                Text(q.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                            .textDirection(for: q.question)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                Button {
                    index = 0
                    chosen = Array(repeating: nil, count: questions.count)
                    revealed = false
                    finished = false
                } label: {
                    Label(tr("أعد الاختبار", "Retake quiz"), systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    questions.shuffle()
                    index = 0
                    chosen = Array(repeating: nil, count: questions.count)
                    revealed = false
                    finished = false
                } label: {
                    Label(tr("أعده بترتيب مختلف", "Retake shuffled"), systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }
}

struct OptionButton: View {
    enum Look { case normal, selected, correct, wrong, dimmed }
    let text: String
    let state: Look
    let letter: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(letter)
                    .font(.subheadline.bold())
                    .frame(width: 30, height: 30)
                    .background(badgeColor.opacity(0.2), in: Circle())
                    .foregroundStyle(badgeColor)
                Text(text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.primary)
                if state == .correct { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                if state == .wrong { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
            }
            .padding(14)
            .background(background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 2))
            .opacity(state == .dimmed ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .textDirection(for: text)
    }

    private var badgeColor: Color {
        switch state {
        case .correct: return .green
        case .wrong: return .red
        case .selected: return Theme.accent
        default: return .secondary
        }
    }
    private var background: Color {
        switch state {
        case .correct: return Color.green.opacity(0.12)
        case .wrong: return Color.red.opacity(0.12)
        case .selected: return Theme.accent.opacity(0.12)
        default: return Theme.card
        }
    }
    private var border: Color {
        switch state {
        case .correct: return .green
        case .wrong: return .red
        case .selected: return Theme.accent
        default: return .clear
        }
    }
}
