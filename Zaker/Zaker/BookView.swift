import SwiftUI
import SwiftData
import PDFKit
import QuickLook

struct BookView: View {
    @Bindable var book: Book
    @State private var thumb: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    NavigationLink { QuizListView(book: book) } label: {
                        ActionTile(icon: "checklist", title: tr("اختبارات", "Quizzes"),
                                   subtitle: countLabel(book.quizzes.count), color: Theme.accent)
                    }
                    NavigationLink { SummaryListView(book: book) } label: {
                        ActionTile(icon: "text.badge.star", title: tr("ملخصات", "Summaries"),
                                   subtitle: countLabel(book.summaries.count), color: .orange)
                    }
                    NavigationLink { DeckListView(book: book) } label: {
                        ActionTile(icon: "rectangle.on.rectangle.angled", title: tr("بطاقات مراجعة", "Flashcards"),
                                   subtitle: countLabel(book.decks.count), color: .teal)
                    }
                    NavigationLink { ChatView(book: book) } label: {
                        ActionTile(icon: "bubble.left.and.text.bubble.right.fill", title: tr("اسأل الكتاب", "Ask the book"),
                                   subtitle: tr("محادثة مع AI", "Chat with AI"), color: .pink)
                    }
                    NavigationLink { NotesListView(book: book) } label: {
                        ActionTile(icon: "note.text", title: tr("ملاحظاتي", "My notes"),
                                   subtitle: countLabel(book.notes.count), color: .yellow)
                    }
                    NavigationLink { NotebookListView(book: book) } label: {
                        ActionTile(icon: "pencil.tip.crop.circle.fill", title: tr("دفتري بالقلم", "Handwritten notes"),
                                   subtitle: tr("أقلام، صور، تسجيل صوت", "Pens, images, audio"), color: .indigo)
                    }
                    NavigationLink { ReaderView(book: book) } label: {
                        ActionTile(icon: "book.fill", title: tr("اقرأ", "Read"),
                                   subtitle: book.kindLabel,
                                   color: .green)
                    }
                }
                .buttonStyle(.plain)

                if let best = book.quizzes.filter({ $0.bestScore >= 0 }).max(by: { $0.createdAt < $1.createdAt }) {
                    HStack {
                        Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                        Text(tr("آخر نتيجة: \(best.lastScore)/\(best.questionCount) في «\(best.title)»",
                                "Last score: \(best.lastScore)/\(best.questionCount) in “\(best.title)”"))
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding()
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { book.lastOpened = .now }
        .task {
            if thumb == nil { thumb = PDFThumb.make(book: book) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.7))
                if let thumb {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    Image(systemName: book.kindIcon).font(.largeTitle).foregroundStyle(.white)
                }
            }
            .frame(width: 90, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.title3.bold())
                    .lineLimit(3)
                Text(book.isPDF ? tr("كتاب PDF · \(book.pageCount) صفحة", "PDF · \(book.pageCount) pages")
                                : (book.hasFile ? book.kindLabel
                                   : tr("نص · \(book.textContent.count) حرف", "Text · \(book.textContent.count) characters")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(tr("أُضيف ", "Added ") + book.addedAt.shortLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func countLabel(_ n: Int) -> String {
        n == 0 ? tr("جديد", "New") : tr("\(n) محفوظ", "\(n) saved")
    }
}

struct ActionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 12))
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - القراءة

struct ReaderView: View {
    let book: Book

    var body: some View {
        Group {
            if book.isPDF {
                PDFKitView(url: book.fileURL)
                    .ignoresSafeArea(edges: .bottom)
                    .environment(\.layoutDirection, .leftToRight)
            } else if book.hasFile {
                QuickLookView(url: book.fileURL)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ScrollView {
                    Text(book.textContent)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textDirection(for: book.textContent)
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.document = PDFDocument(url: url)
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

/// يعرض أي ملف (Word، PowerPoint، Excel، صور، صوت، فيديو…) بعارض iOS.
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
