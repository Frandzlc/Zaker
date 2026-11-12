import SwiftUI
import SwiftData
import PDFKit
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Book.lastOpened, order: .reverse) private var books: [Book]
    @State private var showImporter = false
    @State private var showPasteText = false
    @State private var importError: String?
    @State private var toDelete: Book?
    @State private var hasKey = !Keychain.get().isEmpty

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !hasKey {
                        NoKeyBanner()
                    }
                    if let importError {
                        ErrorBox(message: importError)
                    }
                    if books.isEmpty {
                        EmptyLibrary(onImport: { showImporter = true }, onPaste: { showPasteText = true })
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                            ForEach(books) { book in
                                NavigationLink {
                                    BookView(book: book)
                                } label: {
                                    BookCard(book: book)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { toDelete = book } label: {
                                        Label(tr("حذف الكتاب", "Delete book"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(tr("ذاكر", "Zaker"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showImporter = true } label: {
                            Label(tr("استيراد ملف (PDF، صور، Word…)", "Import a file (PDF, images, Word…)"), systemImage: "doc.richtext")
                        }
                        Button { showPasteText = true } label: {
                            Label(tr("لصق نص", "Paste text"), systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                importBooks(result)
            }
            .sheet(isPresented: $showPasteText) {
                PasteTextBookView().appLanguage()
            }
            .confirmationDialog(tr("تحذف الكتاب وكل اختباراته وملاحظاته؟", "Delete this book with all its quizzes and notes?"),
                                isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                                titleVisibility: .visible) {
                Button(tr("حذف", "Delete"), role: .destructive) {
                    if let b = toDelete {
                        BookFiles.delete(b.fileName)
                        ctx.delete(b)
                        try? ctx.save()
                    }
                    toDelete = nil
                }
            }
            .onAppear { hasKey = !Keychain.get().isEmpty }
        }
    }

    private func importBooks(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .failure(let e):
            importError = e.localizedDescription
        case .success(let urls):
            for url in urls {
                if let err = FileImport.importFile(url, into: ctx) { importError = err }
            }
        }
    }
}

struct NoKeyBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(tr("خطوة وحدة قبل تبدأ", "One step before you start"), systemImage: "key.fill")
                .font(.headline)
            Text(tr("أضف مفتاح Gemini المجاني من تبويب الإعدادات عشان يشتغل الـAI.",
                    "Add your free Gemini API key in the Settings tab to enable the AI."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct EmptyLibrary: View {
    let onImport: () -> Void
    let onPaste: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
                .padding(.top, 40)
            Text(tr("مكتبتك فاضية", "Your library is empty"))
                .font(.title2.bold())
            Text(tr("أضف أي ملف (PDF، صور، Word، PowerPoint…) أو الصق نص، والـAI يسوي لك منه اختبارات وملخصات وبطاقات مراجعة.",
                    "Add any file (PDF, images, Word, PowerPoint…) or paste text, and the AI will make quizzes, summaries and flashcards from it."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: onImport) {
                Label(tr("استيراد ملف (PDF، صور، Word…)", "Import a file (PDF, images, Word…)"), systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button(action: onPaste) {
                Label(tr("لصق نص", "Paste text"), systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal)
    }
}

struct BookCard: View {
    let book: Book
    @State private var thumb: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.85), Theme.accent.opacity(0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: book.kindIcon)
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(book.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text(book.kindLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: book.fileName) {
            guard thumb == nil else { return }
            thumb = PDFThumb.make(book: book)
        }
    }
}

enum PDFThumb {
    static func make(book: Book) -> UIImage? {
        if book.isPDF { return make(url: book.fileURL) }
        if book.isImage, let img = UIImage(contentsOfFile: book.fileURL.path) {
            return img.preparingThumbnail(of: CGSize(width: 320, height: 420)) ?? img
        }
        return nil
    }

    static func make(url: URL) -> UIImage? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        return page.thumbnail(of: CGSize(width: 320, height: 420), for: .cropBox)
    }
}

struct PasteTextBookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("العنوان", "Title")) {
                    TextField(tr("مثال: مذكرة الأحياء", "e.g. Biology notes"), text: $title)
                }
                Section(tr("النص", "Text")) {
                    TextEditor(text: $text)
                        .frame(minHeight: 260)
                    Button {
                        if let s = UIPasteboard.general.string { text = s }
                    } label: {
                        Label(tr("لصق من الحافظة", "Paste from clipboard"), systemImage: "doc.on.clipboard")
                    }
                }
            }
            .navigationTitle(tr("كتاب من نص", "Book from text"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("إلغاء", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("حفظ", "Save")) {
                        let t = title.trimmingCharacters(in: .whitespaces)
                        ctx.insert(Book(title: t.isEmpty ? tr("نص بدون عنوان", "Untitled text") : t,
                                        isPDF: false, textContent: text))
                        try? ctx.save()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
                }
            }
        }
    }
}
