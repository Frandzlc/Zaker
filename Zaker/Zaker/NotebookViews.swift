import SwiftUI
import SwiftData
import PhotosUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

// MARK: - قائمة الدفاتر

struct NotebookListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Notebook.updatedAt, order: .reverse) private var all: [Notebook]
    var book: Book?

    @State private var showNew = false
    @State private var open: Notebook?
    @State private var toDelete: Notebook?
    @State private var renaming: Notebook?
    @State private var newName = ""

    private var notebooks: [Notebook] {
        guard let book else { return all }
        return all.filter { $0.bookID == book.id }
    }

    var body: some View {
        ScrollView {
            if notebooks.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 60))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 50)
                    Text(tr("ما عندك دفاتر", "No notebooks yet")).font(.title2.bold())
                    Text(tr("سوّ دفتر واكتب بالقلم، أضف صور، وسجّل صوتك. فيه ورق مسطر عربي وإنجليزي ورياضيات وغيرها.",
                            "Create a notebook to write with pens, add images and record audio. Arabic, English and math papers included."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button {
                        showNew = true
                    } label: {
                        Label(tr("دفتر جديد", "New notebook"), systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                    ForEach(notebooks) { nb in
                        Button { open = nb } label: { NotebookCover(notebook: nb) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    newName = nb.title
                                    renaming = nb
                                } label: { Label(tr("إعادة تسمية", "Rename"), systemImage: "pencil") }
                                Menu {
                                    ForEach(NotebookCovers.colors, id: \.self) { hex in
                                        Button { nb.coverHex = hex } label: {
                                            Label(hex, systemImage: nb.coverHex == hex ? "checkmark.circle.fill" : "circle.fill")
                                        }
                                    }
                                } label: { Label(tr("لون الغلاف", "Cover color"), systemImage: "paintpalette") }
                                Button(role: .destructive) { toDelete = nb } label: {
                                    Label(tr("حذف الدفتر", "Delete notebook"), systemImage: "trash")
                                }
                            }
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(book == nil ? tr("دفاتري", "Notebooks") : tr("دفتري بالقلم", "Handwritten notes"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
            }
        }
        .sheet(isPresented: $showNew) {
            NewNotebookView(book: book) { nb in
                open = nb
            }
            .appLanguage()
        }
        .navigationDestination(item: $open) { NotebookEditorView(notebook: $0) }
        .confirmationDialog(tr("تحذف الدفتر وكل صفحاته وتسجيلاته؟", "Delete this notebook with all its pages and recordings?"),
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button(tr("حذف", "Delete"), role: .destructive) {
                if let nb = toDelete {
                    MediaFiles.cleanup(nb)
                    ctx.delete(nb)
                    try? ctx.save()
                }
                toDelete = nil
            }
        }
        .alert(tr("اسم الدفتر", "Notebook name"),
               isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(tr("الاسم", "Name"), text: $newName)
            Button(tr("حفظ", "Save")) {
                renaming?.title = newName
                renaming = nil
            }
            Button(tr("إلغاء", "Cancel"), role: .cancel) { renaming = nil }
        }
    }
}

enum NotebookCovers {
    static let colors = ["5B4DD9", "1D4ED8", "0F766E", "15803D", "B91C1C", "DB2777", "EA580C", "CA8A04", "6B4423", "374151", "111111", "7C3AED"]
}

struct NotebookCover: View {
    let notebook: Notebook
    @State private var thumb: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: notebook.coverHex).gradient)
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 22)
                        .frame(maxWidth: .infinity)
                        .shadow(radius: 2)
                }
                // حلقات الدفتر
                VStack(spacing: 14) {
                    ForEach(0..<7, id: \.self) { _ in
                        Capsule().fill(.white.opacity(0.85)).frame(width: 14, height: 5)
                    }
                }
                .padding(.leading, 4)
            }
            .frame(height: 200)
            .environment(\.layoutDirection, .leftToRight)
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(notebook.title.isEmpty ? tr("بدون عنوان", "Untitled") : notebook.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(tr("\(notebook.pages.count) صفحة", "\(notebook.pages.count) pages") +
                 (notebook.recordings.isEmpty ? "" : " · 🎙 \(notebook.recordings.count)"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: notebook.updatedAt) {
            if let first = notebook.sortedPages.first {
                thumb = PaperRenderer.render(page: first, size: CGSize(width: 120, height: 170), scale: 2)
            }
        }
    }
}

// MARK: - دفتر جديد

struct NewNotebookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    var book: Book?
    var onCreate: (Notebook) -> Void

    @State private var title = ""
    @State private var paper: PaperStyle = Prefs.uiLang == "ar" ? .linedAR : .linedEN
    @State private var color: PaperColor = .white
    @State private var cover = NotebookCovers.colors[0]
    @State private var fromBook = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("الاسم", "Name")) {
                    TextField(tr("مثال: رياضيات الفصل الأول", "e.g. Math term 1"), text: $title)
                }
                if let book, book.isPDF || book.isImage {
                    Section {
                        Toggle(tr("اكتب على صفحات الكتاب نفسه", "Write on the book's own pages"), isOn: $fromBook)
                    } footer: {
                        Text(tr("كل صفحة من الكتاب تصير صفحة في الدفتر وتقدر تكتب وترسم عليها.",
                                "Each page of the book becomes a notebook page you can write on."))
                    }
                }
                if !fromBook {
                    Section(tr("نوع الورق", "Paper")) {
                        PaperGrid(selection: $paper, color: color)
                    }
                    Section(tr("لون الورق", "Paper color")) {
                        PaperColorRow(selection: $color)
                    }
                }
                Section(tr("لون الغلاف", "Cover color")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(NotebookCovers.colors, id: \.self) { hex in
                                Circle().fill(Color(hex: hex))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: cover == hex ? 3 : 0).padding(-3))
                                    .padding(4)
                                    .onTapGesture { cover = hex }
                            }
                        }
                    }
                }
            }
            .disabled(working)
            .overlay { if working { ProgressView(tr("نجهز الصفحات…", "Preparing pages…")).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .navigationTitle(tr("دفتر جديد", "New notebook"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("إلغاء", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("إنشاء", "Create")) { create() }
                }
            }
        }
    }

    private func create() {
        let name = title.trimmingCharacters(in: .whitespaces)
        let nb = Notebook(title: name.isEmpty ? (book?.title ?? tr("دفتر جديد", "New notebook")) : name,
                          paper: paper.rawValue, paperColor: color.rawValue, coverHex: cover, bookID: book?.id)
        ctx.insert(nb)
        if fromBook, let book {
            working = true
            let url = book.fileURL
            Task {
                let files = await NotebookImport.renderPages(from: url)
                for (i, f) in files.enumerated() {
                    ctx.insert(NotePage(index: i, paper: PaperStyle.blank.rawValue, paperColor: PaperColor.white.rawValue, backgroundFile: f, notebook: nb))
                }
                if files.isEmpty {
                    ctx.insert(NotePage(index: 0, paper: paper.rawValue, paperColor: color.rawValue, notebook: nb))
                }
                try? ctx.save()
                working = false
                dismiss()
                onCreate(nb)
            }
        } else {
            ctx.insert(NotePage(index: 0, paper: paper.rawValue, paperColor: color.rawValue, notebook: nb))
            try? ctx.save()
            dismiss()
            onCreate(nb)
        }
    }
}

/// يحول PDF أو صورة لصور صفحات.
enum NotebookImport {
    static func renderPages(from url: URL, limit: Int = 400) async -> [String] {
        await Task.detached(priority: .userInitiated) { () -> [String] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let doc = PDFDocument(url: url), doc.pageCount > 0 {
                var out: [String] = []
                for i in 0..<min(doc.pageCount, limit) {
                    guard let page = doc.page(at: i) else { continue }
                    let b = page.bounds(for: .mediaBox)
                    let s = 1640 / max(b.width, 1)
                    let img = page.thumbnail(of: CGSize(width: b.width * s, height: b.height * s), for: .mediaBox)
                    if let n = MediaFiles.saveImage(img, maxSide: 2400, quality: 0.8) { out.append(n) }
                }
                return out
            }
            if let img = UIImage(contentsOfFile: url.path), let n = MediaFiles.saveImage(img) { return [n] }
            return []
        }.value
    }
}

// MARK: - اختيار الورق

struct PaperGrid: View {
    @Binding var selection: PaperStyle
    var color: PaperColor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(PaperStyle.Group.allCases) { g in
                Text(g.title).font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(PaperStyle.allCases.filter { $0.group == g }) { st in
                            PaperThumb(style: st, color: color, selected: selection == st)
                                .onTapGesture { selection = st }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct PaperThumb: View {
    let style: PaperStyle
    let color: PaperColor
    var selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(uiImage: PaperRenderer.image(style: style, color: color, size: CGSize(width: 82, height: 116)))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Theme.accent : Color.gray.opacity(0.3), lineWidth: selected ? 3 : 1))
                .environment(\.layoutDirection, .leftToRight)
            Text(style.title)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 90)
        }
    }
}

struct PaperColorRow: View {
    @Binding var selection: PaperColor

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PaperColor.allCases) { c in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(uiColor: c.background))
                            .frame(width: 40, height: 52)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selection == c ? Theme.accent : Color.gray.opacity(0.4), lineWidth: selection == c ? 3 : 1))
                        Text(c.title).font(.caption2)
                    }
                    .onTapGesture { selection = c }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct PaperPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var style: PaperStyle
    @State var color: PaperColor
    var onApply: (PaperStyle, PaperColor, Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("نوع الورق", "Paper")) { PaperGrid(selection: $style, color: color) }
                Section(tr("لون الورق", "Paper color")) { PaperColorRow(selection: $color) }
                Section {
                    Button(tr("طبّق على هذي الصفحة", "Apply to this page")) { onApply(style, color, false); dismiss() }
                    Button(tr("طبّق على كل الصفحات", "Apply to all pages")) { onApply(style, color, true); dismiss() }
                }
            }
            .navigationTitle(tr("الورق والتسطير", "Paper & ruling"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("إغلاق", "Close")) { dismiss() } }
            }
        }
    }
}

// MARK: - المحرر

struct NotebookEditorView: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var notebook: Notebook
    @StateObject private var tools = ToolState()
    @StateObject private var recorder = AudioRecorder()

    @State private var pageIndex = 0
    @State private var version = 0
    @State private var showLibrary = false
    @State private var showPages = false
    @State private var showPaper = false
    @State private var showRecordings = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showImportPages = false
    @State private var showTextAlert = false
    @State private var textDraft = ""
    @State private var editingItem: PageItem?
    @State private var shareURL: URL?
    @State private var busy: String?
    @State private var errorText: String?

    private var pages: [NotePage] { notebook.sortedPages }
    private var current: NotePage? {
        let p = pages
        guard !p.isEmpty else { return nil }
        return p[min(max(pageIndex, 0), p.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(tools: tools,
                          isRecording: recorder.isRecording,
                          onLibrary: { showLibrary = true },
                          onPhotos: { showPhotoPicker = true },
                          onCamera: { showCamera = true },
                          onText: { editingItem = nil; textDraft = ""; showTextAlert = true },
                          onMic: toggleRecording)
            Divider()
            ZStack(alignment: .top) {
                if let page = current {
                    PageCanvasView(page: page, tools: tools, version: version,
                                   onEditText: { item in
                                       editingItem = item
                                       textDraft = item.text
                                       showTextAlert = true
                                   },
                                   onChange: { notebook.updatedAt = .now })
                        .id(page.id)
                        .environment(\.layoutDirection, .leftToRight)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView()
                }
                VStack(spacing: 8) {
                    if recorder.isRecording { RecordingPill(recorder: recorder, onStop: toggleRecording) }
                    if let busy { Label(busy, systemImage: "hourglass").padding(10).background(.regularMaterial, in: Capsule()) }
                    if let errorText { ErrorBox(message: errorText).padding(.horizontal).onTapGesture { self.errorText = nil } }
                }
                .padding(.top, 10)
            }
            pageBar
        }
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showRecordings = true } label: {
                    Image(systemName: notebook.recordings.isEmpty ? "waveform" : "waveform.badge.mic")
                }
                Menu {
                    Button { showPaper = true } label: { Label(tr("الورق والتسطير", "Paper & ruling"), systemImage: "doc.richtext") }
                    Button { showPages = true } label: { Label(tr("كل الصفحات", "All pages"), systemImage: "square.grid.2x2") }
                    Button { showImportPages = true } label: { Label(tr("استيراد PDF أو صور كصفحات", "Import PDF/images as pages"), systemImage: "square.and.arrow.down") }
                    Divider()
                    Button { exportPDF() } label: { Label(tr("تصدير الدفتر PDF", "Export notebook as PDF"), systemImage: "square.and.arrow.up") }
                    Button { exportPageImage() } label: { Label(tr("مشاركة الصفحة كصورة", "Share page as image"), systemImage: "photo") }
                    Divider()
                    Toggle(isOn: $tools.fingerDraws) { Label(tr("الكتابة بالإصبع", "Draw with finger"), systemImage: "hand.draw") }
                    Button(role: .destructive) { clearPage() } label: { Label(tr("مسح كتابة الصفحة", "Clear page ink"), systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showLibrary) {
            PenLibraryView(tools: tools)
                .presentationDetents([.medium, .large])
                .appLanguage()
        }
        .sheet(isPresented: $showPaper) {
            PaperPickerSheet(style: PaperStyle(rawValue: current?.paper ?? "") ?? .blank,
                             color: PaperColor(rawValue: current?.paperColor ?? "") ?? .white) { st, c, all in
                applyPaper(st, c, all: all)
            }
            .appLanguage()
        }
        .sheet(isPresented: $showPages) {
            PagesGridView(notebook: notebook, current: $pageIndex,
                          onChange: { version += 1 })
                .appLanguage()
        }
        .sheet(isPresented: $showRecordings) {
            RecordingsView(notebook: notebook, recorder: recorder, onRecord: toggleRecording,
                           onGoToPage: { i in pageIndex = i; showRecordings = false })
                .presentationDetents([.medium, .large])
                .appLanguage()
        }
        .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { if $0 == nil { shareURL = nil } })) { s in
            ShareSheet(items: [s.url])
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in addImages([img]) }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var imgs: [UIImage] = []
                for it in items {
                    if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { imgs.append(img) }
                }
                photoItems = []
                addImages(imgs)
            }
        }
        .fileImporter(isPresented: $showImportPages, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importPages(urls) }
        }
        .alert(editingItem == nil ? tr("إضافة نص", "Add text") : tr("تعديل النص", "Edit text"), isPresented: $showTextAlert) {
            TextField(tr("اكتب هنا", "Type here"), text: $textDraft, axis: .vertical)
            Button(tr("حفظ", "Save")) { saveText() }
            Button(tr("إلغاء", "Cancel"), role: .cancel) {}
        }
        .onAppear {
            if notebook.pages.isEmpty {
                ctx.insert(NotePage(index: 0, paper: notebook.paper, paperColor: notebook.paperColor, notebook: notebook))
                try? ctx.save()
            }
            pageIndex = min(pageIndex, max(notebook.pages.count - 1, 0))
        }
        .onDisappear {
            if recorder.isRecording { toggleRecording() }
            try? ctx.save()
        }
        .onChange(of: recorder.error) { _, e in if let e { errorText = e } }
    }

    // MARK: شريط الصفحات

    private var pageBar: some View {
        HStack(spacing: 18) {
            Button { pageIndex = max(pageIndex - 1, 0) } label: { Image(systemName: "chevron.left.circle.fill").font(.title2) }
                .disabled(pageIndex == 0)
            Button { showPages = true } label: {
                Text(tr("صفحة \(pageIndex + 1) من \(pages.count)", "Page \(pageIndex + 1) of \(pages.count)"))
                    .font(.subheadline.monospacedDigit())
            }
            Button { pageIndex = min(pageIndex + 1, pages.count - 1) } label: { Image(systemName: "chevron.right.circle.fill").font(.title2) }
                .disabled(pageIndex >= pages.count - 1)
            Spacer()
            Menu {
                Button { addPage(paper: current?.paper, color: current?.paperColor) } label: {
                    Label(tr("صفحة بنفس الورق", "Same paper"), systemImage: "doc")
                }
                ForEach([PaperStyle.linedAR, .linedEN, .mathGrid, .handwritingAR, .handwritingEN, .coordinate, .blank]) { st in
                    Button { addPage(paper: st.rawValue, color: current?.paperColor) } label: { Text(st.title) }
                }
            } label: {
                Label(tr("صفحة", "Page"), systemImage: "plus.rectangle.portrait.fill")
            } primaryAction: {
                addPage(paper: current?.paper, color: current?.paperColor)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: الإجراءات

    private func addPage(paper: String?, color: String?) {
        let insertAt = (current?.index ?? -1) + 1
        for p in notebook.pages where p.index >= insertAt { p.index += 1 }
        ctx.insert(NotePage(index: insertAt, paper: paper ?? notebook.paper, paperColor: color ?? notebook.paperColor, notebook: notebook))
        notebook.updatedAt = .now
        try? ctx.save()
        pageIndex = min(insertAt, notebook.pages.count - 1)
    }

    private func applyPaper(_ st: PaperStyle, _ c: PaperColor, all: Bool) {
        let targets = all ? notebook.pages : (current.map { [$0] } ?? [])
        for p in targets {
            p.paper = st.rawValue
            p.paperColor = c.rawValue
        }
        if all {
            notebook.paper = st.rawValue
            notebook.paperColor = c.rawValue
        }
        // الورق الغامق يحتاج قلم فاتح
        if c.isDark && ["000000", "111111", "222222", "3A3A3C"].contains(tools.pen.colorHex) { tools.setColor("FFFFFF") }
        version += 1
    }

    private func addImages(_ images: [UIImage]) {
        guard let page = current, !images.isEmpty else { return }
        var items = page.items
        for (i, img) in images.enumerated() {
            guard let name = MediaFiles.saveImage(img) else { continue }
            let maxW: CGFloat = 420
            let w = min(maxW, img.size.width)
            let h = w * img.size.height / max(img.size.width, 1)
            let offset = CGFloat(i * 30 + items.count % 5 * 20)
            items.append(PageItem(kind: "image", file: name,
                                  x: (PageSize.width - w) / 2 + offset, y: 160 + offset, w: w, h: h))
        }
        page.items = items
        notebook.updatedAt = .now
        tools.mode = .select
        version += 1
    }

    private func saveText() {
        let text = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let page = current else { return }
        var items = page.items
        if let editing = editingItem, let i = items.firstIndex(where: { $0.id == editing.id }) {
            if text.isEmpty {
                items.remove(at: i)
            } else {
                items[i].text = text
                let size = Self.textSize(text, font: items[i].fontSize)
                items[i].w = max(items[i].w, size.width)
                items[i].h = size.height
            }
        } else if !text.isEmpty {
            let size = Self.textSize(text, font: 28)
            items.append(PageItem(kind: "text", text: text,
                                  x: (PageSize.width - size.width) / 2, y: 200, w: size.width, h: size.height,
                                  colorHex: tools.pen.colorHex, fontSize: 28))
            tools.mode = .select
        }
        page.items = items
        editingItem = nil
        notebook.updatedAt = .now
        version += 1
    }

    static func textSize(_ text: String, font: Double) -> CGSize {
        let r = (text as NSString).boundingRect(with: CGSize(width: 640, height: 4000),
                                                options: [.usesLineFragmentOrigin],
                                                attributes: [.font: UIFont.systemFont(ofSize: font)], context: nil)
        return CGSize(width: ceil(r.width) + 12, height: ceil(r.height) + 8)
    }

    private func clearPage() {
        guard let page = current else { return }
        page.drawing = Data()
        tools.canvas?.drawing = PKDrawing()
        version += 1
    }

    private func toggleRecording() {
        if recorder.isRecording {
            if let r = recorder.stop() {
                let n = notebook.recordings.count + 1
                ctx.insert(Recording(title: tr("تسجيل \(n)", "Recording \(n)"), fileName: r.fileName,
                                     duration: r.duration, pageIndex: pageIndex, notebook: notebook))
                notebook.updatedAt = .now
                try? ctx.save()
            }
        } else {
            Task { _ = await recorder.start() }
        }
    }

    private func importPages(_ urls: [URL]) {
        busy = tr("نستورد الصفحات…", "Importing pages…")
        Task {
            var files: [String] = []
            for u in urls { files += await NotebookImport.renderPages(from: u) }
            let start = notebook.pages.count
            for (i, f) in files.enumerated() {
                ctx.insert(NotePage(index: start + i, paper: PaperStyle.blank.rawValue, paperColor: PaperColor.white.rawValue,
                                    backgroundFile: f, notebook: notebook))
            }
            try? ctx.save()
            busy = nil
            if !files.isEmpty { pageIndex = start }
            else { errorText = tr("ما قدرت أقرأ الملف.", "Couldn't read the file.") }
        }
    }

    private func exportPDF() {
        busy = tr("نجهز ملف PDF…", "Preparing PDF…")
        tools.canvas.map { c in current?.drawing = c.drawing.dataRepresentation() }
        Task { @MainActor in
            await Task.yield()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName(notebook.title) + ".pdf")
            let bounds = CGRect(origin: .zero, size: PageSize.size)
            let renderer = UIGraphicsPDFRenderer(bounds: bounds)
            do {
                try renderer.writePDF(to: url) { ctx in
                    for p in pages {
                        ctx.beginPage()
                        PaperRenderer.render(page: p, size: PageSize.size, scale: 2).draw(in: bounds)
                    }
                }
                shareURL = url
            } catch {
                errorText = error.localizedDescription
            }
            busy = nil
        }
    }

    private func exportPageImage() {
        guard let page = current else { return }
        tools.canvas.map { c in page.drawing = c.drawing.dataRepresentation() }
        let img = PaperRenderer.render(page: page, size: PageSize.size, scale: 2)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName(notebook.title) + "-\(pageIndex + 1).png")
        if let d = img.pngData(), (try? d.write(to: url)) != nil { shareURL = url }
    }

    private func safeName(_ s: String) -> String {
        let t = s.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        return t.isEmpty ? "Zaker" : t
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - شريط الأدوات

struct EditorToolbar: View {
    @ObservedObject var tools: ToolState
    var isRecording: Bool
    var onLibrary: () -> Void
    var onPhotos: () -> Void
    var onCamera: () -> Void
    var onText: () -> Void
    var onMic: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                toolButton("arrow.uturn.backward", active: false) { tools.undo() }
                toolButton("arrow.uturn.forward", active: false) { tools.redo() }
                Divider().frame(height: 30)

                ForEach(tools.favorites) { p in
                    PenChip(pen: p, selected: tools.mode == .draw && tools.pen.id == p.id)
                        .onTapGesture {
                            if tools.mode == .draw && tools.pen.id == p.id { onLibrary() } else { tools.select(p) }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                tools.favorites.removeAll { $0.id == p.id }
                            } label: { Label(tr("شيل من المفضلة", "Remove from favorites"), systemImage: "minus.circle") }
                        }
                }
                toolButton("paintpalette.fill", active: false, tint: .pink) { onLibrary() }
                Divider().frame(height: 30)

                Menu {
                    Button { tools.bitmapEraser = false; tools.mode = .erase } label: {
                        Label(tr("ممحاة الخط كامل", "Stroke eraser"), systemImage: tools.bitmapEraser ? "circle" : "checkmark.circle.fill")
                    }
                    Button { tools.bitmapEraser = true; tools.mode = .erase } label: {
                        Label(tr("ممحاة نقطية", "Pixel eraser"), systemImage: tools.bitmapEraser ? "checkmark.circle.fill" : "circle")
                    }
                    Picker(tr("حجم الممحاة", "Eraser size"), selection: $tools.eraserWidth) {
                        ForEach([5.0, 10, 20, 40, 80], id: \.self) { Text("\(Int($0))").tag($0) }
                    }
                } label: {
                    toolIcon("eraser.fill", active: tools.mode == .erase)
                } primaryAction: {
                    tools.mode = .erase
                }
                toolButton("lasso", active: tools.mode == .lasso) { tools.mode = .lasso }
                toolButton("hand.point.up.left.fill", active: tools.mode == .select) { tools.mode = tools.mode == .select ? .draw : .select }
                toolButton("ruler", active: tools.ruler) { tools.ruler.toggle() }
                Divider().frame(height: 30)

                Menu {
                    Button(action: onPhotos) { Label(tr("من الصور", "From Photos"), systemImage: "photo.on.rectangle") }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(action: onCamera) { Label(tr("صوّر بالكاميرا", "Take a photo"), systemImage: "camera") }
                    }
                } label: {
                    toolIcon("photo.badge.plus", active: false)
                }
                toolButton("textformat", active: false, action: onText)
                toolButton(isRecording ? "stop.circle.fill" : "mic.fill", active: isRecording, tint: .red, action: onMic)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .environment(\.layoutDirection, .leftToRight)
        .background(.bar)
    }

    private func toolIcon(_ name: String, active: Bool, tint: Color = Theme.accent) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 38, height: 38)
            .foregroundStyle(active ? .white : tint)
            .background(active ? tint : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }

    private func toolButton(_ name: String, active: Bool, tint: Color = Theme.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolIcon(name, active: active, tint: tint) }
            .buttonStyle(.plain)
    }
}

struct PenChip: View {
    let pen: PenPreset
    var selected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: pen.ink.icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(pen.color)
                .shadow(color: .black.opacity(pen.colorHex == "FFFFFF" ? 0.6 : 0), radius: 1)
            Capsule().fill(pen.color)
                .frame(width: 22, height: max(2, min(CGFloat(pen.width) / 2, 8)))
                .opacity(pen.ink == .marker ? 0.6 : 1)
        }
        .frame(width: 40, height: 40)
        .background(selected ? Theme.accent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.accent : .clear, lineWidth: 2))
        .offset(y: selected ? -2 : 0)
    }
}

struct RecordingPill: View {
    @ObservedObject var recorder: AudioRecorder
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 10, height: 10)
                .opacity(Int(recorder.elapsed * 2) % 2 == 0 ? 1 : 0.3)
            Text(recorder.elapsed.clock).font(.subheadline.monospacedDigit().bold())
            Capsule().fill(.red.opacity(0.7))
                .frame(width: 8 + CGFloat(recorder.level) * 50, height: 6)
                .animation(.linear(duration: 0.1), value: recorder.level)
            Button(action: onStop) {
                Image(systemName: "stop.fill").foregroundStyle(.white).padding(6).background(.red, in: Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4)
    }
}

// MARK: - مكتبة الأقلام والألوان

struct PenLibraryView: View {
    @ObservedObject var tools: ToolState
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var recent: [String] = PenLibrary.loadRecentColors()
    @State private var custom: Color = .black

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                currentPen
                Picker("", selection: $tab) {
                    Text(tr("أقلام", "Pens")).tag(0)
                    Text(tr("ألوان (\(ColorLibrary.totalCount))", "Colors (\(ColorLibrary.totalCount))")).tag(1)
                    Text(tr("مجموعات", "Sets")).tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                ScrollView {
                    switch tab {
                    case 0: pensTab
                    case 1: colorsTab
                    default: setsTab
                    }
                }
            }
            .navigationTitle(tr("مكتبة الأقلام والألوان", "Pens & colors"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("تم", "Done")) { dismiss() } }
            }
        }
    }

    private var currentPen: some View {
        VStack(spacing: 10) {
            HStack {
                PenSample(pen: tools.pen)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))
                ColorPicker("", selection: Binding(
                    get: { tools.pen.color },
                    set: { tools.setColor(UIColor($0).hexString); recent = PenLibrary.loadRecentColors() }),
                            supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
            }
            HStack {
                Image(systemName: "lineweight")
                Slider(value: Binding(get: { tools.pen.width }, set: { tools.setWidth($0) }),
                       in: widthRange)
                Text(String(format: "%.1f", tools.pen.width)).font(.caption.monospacedDigit()).frame(width: 36)
                Button {
                    tools.addCurrentToFavorites()
                } label: {
                    Label(tr("للمفضلة", "Favorite"), systemImage: "star.fill").font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .disabled(tools.favorites.contains { $0.ink == tools.pen.ink && $0.colorHex == tools.pen.colorHex && $0.width == tools.pen.width })
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding()
    }

    private var widthRange: ClosedRange<Double> {
        let r = tools.pen.ink.pkType.validWidthRange
        return Double(r.lowerBound)...Double(min(r.upperBound, 120))
    }

    private var pensTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(InkKind.allCases) { ink in
                VStack(alignment: .leading, spacing: 8) {
                    Label(ink.title, systemImage: ink.icon).font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ink.widths, id: \.self) { w in
                                let p = PenPreset(ink: ink, colorHex: tools.pen.colorHex, width: w)
                                let sel = tools.pen.ink == ink && tools.pen.width == w
                                VStack(spacing: 4) {
                                    PenSample(pen: p).frame(width: 90, height: 40)
                                    Text(String(format: w < 1 ? "%.1f" : "%.0f", w)).font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? Theme.accent : Color.gray.opacity(0.25), lineWidth: sel ? 2.5 : 1))
                                .onTapGesture {
                                    var np = p
                                    np.id = UUID()
                                    tools.select(np)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding()
    }

    private var colorsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !recent.isEmpty {
                colorSection(tr("آخر الألوان", "Recent"), recent)
            }
            ForEach(ColorLibrary.groups) { g in
                colorSection(g.title, g.colors)
            }
        }
        .padding()
    }

    private func colorSection(_ title: String, _ colors: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 8)], spacing: 8) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.gray.opacity(0.35), lineWidth: 1))
                        .overlay {
                            if tools.pen.colorHex == hex {
                                Image(systemName: "checkmark").font(.caption.bold())
                                    .foregroundStyle(UIColor(hex: hex).isLight ? .black : .white)
                            }
                        }
                        .onTapGesture {
                            tools.setColor(hex)
                            recent = PenLibrary.loadRecentColors()
                        }
                }
            }
        }
    }

    private var setsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("مفضلتي", "My favorites")).font(.headline)
                    Spacer()
                    Button(tr("الافتراضي", "Reset")) { tools.favorites = PenLibrary.defaultFavorites }
                        .font(.caption)
                }
                penRow(tools.favorites)
                Text(tr("اضغط مطوّل على أي قلم في الشريط عشان تشيله.", "Long-press a pen in the toolbar to remove it."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(PenLibrary.sets) { set in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(set.title).font(.headline)
                        Spacer()
                        Button(tr("استخدمها", "Use set")) {
                            tools.favorites = set.pens.map { var p = $0; p.id = UUID(); return p }
                            if let f = tools.favorites.first { tools.select(f) }
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                    }
                    penRow(set.pens)
                }
                .padding()
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
    }

    private func penRow(_ pens: [PenPreset]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pens) { p in
                    PenChip(pen: p, selected: tools.pen.id == p.id)
                        .onTapGesture { tools.select(p) }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

extension UIColor {
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.7
    }
}

/// معاينة شكل خط القلم.
struct PenSample: View {
    let pen: PenPreset

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let mid = size.height / 2
            let amp = size.height * 0.22
            path.move(to: CGPoint(x: 8, y: mid))
            var x: CGFloat = 8
            while x <= size.width - 8 {
                path.addLine(to: CGPoint(x: x, y: mid + sin((x - 8) / 14) * amp))
                x += 2
            }
            let w = min(CGFloat(pen.width), size.height * 0.6)
            var style = StrokeStyle(lineWidth: max(w, 0.8), lineCap: .round, lineJoin: .round)
            var opacity = 1.0
            switch pen.ink {
            case .marker:
                style.lineCap = .butt
                opacity = 0.45
            case .pencil:
                opacity = 0.75
                style.dash = [2, 1]
            case .watercolor:
                opacity = 0.55
            case .crayon:
                style.dash = [3, 1.5]
            default:
                break
            }
            ctx.opacity = opacity
            ctx.stroke(path, with: .color(pen.color), style: style)
        }
    }
}

// MARK: - الصفحات

struct PagesGridView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Bindable var notebook: Notebook
    @Binding var current: Int
    var onChange: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16)], spacing: 18) {
                    ForEach(Array(notebook.sortedPages.enumerated()), id: \.element.id) { i, p in
                        VStack(spacing: 6) {
                            PageThumb(page: p)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(i == current ? Theme.accent : Color.gray.opacity(0.3), lineWidth: i == current ? 3 : 1))
                            Text("\(i + 1)").font(.caption.bold())
                        }
                        .onTapGesture {
                            current = i
                            dismiss()
                        }
                        .contextMenu {
                            Button { duplicate(p) } label: { Label(tr("تكرار الصفحة", "Duplicate"), systemImage: "plus.square.on.square") }
                            if i > 0 {
                                Button { move(p, by: -1) } label: { Label(tr("حركها قبل", "Move earlier"), systemImage: "arrow.left") }
                            }
                            if i < notebook.pages.count - 1 {
                                Button { move(p, by: 1) } label: { Label(tr("حركها بعد", "Move later"), systemImage: "arrow.right") }
                            }
                            Button(role: .destructive) { delete(p) } label: { Label(tr("حذف الصفحة", "Delete page"), systemImage: "trash") }
                        }
                    }
                }
                .padding()
                .environment(\.layoutDirection, .leftToRight)
            }
            .navigationTitle(tr("الصفحات (\(notebook.pages.count))", "Pages (\(notebook.pages.count))"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("تم", "Done")) { dismiss() } }
            }
        }
    }

    private func reindex(_ list: [NotePage]) {
        for (i, p) in list.enumerated() { p.index = i }
        notebook.updatedAt = .now
        try? ctx.save()
        onChange()
    }

    private func duplicate(_ p: NotePage) {
        var list = notebook.sortedPages
        guard let i = list.firstIndex(where: { $0.id == p.id }) else { return }
        let copy = NotePage(index: 0, paper: p.paper, paperColor: p.paperColor, notebook: notebook)
        if !p.backgroundFile.isEmpty,
           let img = UIImage(contentsOfFile: MediaFiles.imageURL(p.backgroundFile).path),
           let n = MediaFiles.saveImage(img, maxSide: 2400, quality: 0.8) {
            copy.backgroundFile = n
        }
        copy.drawing = p.drawing
        copy.items = p.items.map { it in
            var c = it
            c.id = UUID()
            if it.kind == "image", let img = UIImage(contentsOfFile: MediaFiles.imageURL(it.file).path), let n = MediaFiles.saveImage(img) {
                c.file = n
            }
            return c
        }
        ctx.insert(copy)
        list.insert(copy, at: i + 1)
        reindex(list)
    }

    private func move(_ p: NotePage, by d: Int) {
        var list = notebook.sortedPages
        guard let i = list.firstIndex(where: { $0.id == p.id }) else { return }
        let j = i + d
        guard j >= 0 && j < list.count else { return }
        list.swapAt(i, j)
        if current == i { current = j } else if current == j { current = i }
        reindex(list)
    }

    private func delete(_ p: NotePage) {
        var list = notebook.sortedPages
        if list.count <= 1 {
            p.drawing = Data()
            p.items = []
            onChange()
            return
        }
        MediaFiles.delete(image: p.backgroundFile)
        for it in p.items where it.kind == "image" { MediaFiles.delete(image: it.file) }
        list.removeAll { $0.id == p.id }
        ctx.delete(p)
        current = min(current, list.count - 1)
        reindex(list)
    }
}

struct PageThumb: View {
    let page: NotePage
    @State private var img: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let img { Image(uiImage: img).resizable().scaledToFit() } else { ProgressView() }
        }
        .aspectRatio(PageSize.width / PageSize.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
        .task(id: page.id) {
            img = PaperRenderer.render(page: page, size: CGSize(width: 164, height: 232), scale: 2)
        }
    }
}

// MARK: - التسجيلات

struct RecordingsView: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var notebook: Notebook
    @ObservedObject var recorder: AudioRecorder
    var onRecord: () -> Void
    var onGoToPage: (Int) -> Void
    @StateObject private var player = AudioPlayer()
    @State private var renaming: Recording?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onRecord) {
                        HStack {
                            Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.red)
                            VStack(alignment: .leading) {
                                Text(recorder.isRecording ? tr("إيقاف التسجيل", "Stop recording") : tr("تسجيل جديد", "New recording"))
                                    .font(.headline)
                                if recorder.isRecording {
                                    Text(recorder.elapsed.clock).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                } else {
                                    Text(tr("سجّل الشرح وأنت تكتب ملاحظاتك", "Record a lecture while you take notes"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let e = recorder.error { Text(e).font(.footnote).foregroundStyle(.red) }
                }
                if !notebook.recordings.isEmpty {
                    Section(tr("التسجيلات", "Recordings")) {
                        ForEach(notebook.sortedRecordings) { r in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Button { player.toggle(r.fileURL) } label: {
                                        Image(systemName: player.playingFile == r.fileName && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.title)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading) {
                                        Text(r.title).font(.headline)
                                        Text("\(r.duration.clock) · \(r.createdAt.shortLabel) · " + tr("صفحة \(r.pageIndex + 1)", "page \(r.pageIndex + 1)"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Menu {
                                        Button { onGoToPage(r.pageIndex) } label: { Label(tr("روح للصفحة", "Go to page"), systemImage: "doc") }
                                        Button { newName = r.title; renaming = r } label: { Label(tr("إعادة تسمية", "Rename"), systemImage: "pencil") }
                                        ShareLink(item: r.fileURL) { Label(tr("مشاركة", "Share"), systemImage: "square.and.arrow.up") }
                                        Button(role: .destructive) { delete(r) } label: { Label(tr("حذف", "Delete"), systemImage: "trash") }
                                    } label: {
                                        Image(systemName: "ellipsis.circle").font(.title3)
                                    }
                                }
                                if player.playingFile == r.fileName {
                                    Slider(value: Binding(get: { player.progress }, set: { player.seek($0) }))
                                }
                            }
                        }
                        .onDelete { idx in
                            let list = notebook.sortedRecordings
                            for i in idx { delete(list[i]) }
                        }
                    }
                }
            }
            .navigationTitle(tr("التسجيلات الصوتية", "Audio recordings"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(tr("اسم التسجيل", "Recording name"),
                   isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(tr("الاسم", "Name"), text: $newName)
                Button(tr("حفظ", "Save")) { renaming?.title = newName; renaming = nil }
                Button(tr("إلغاء", "Cancel"), role: .cancel) { renaming = nil }
            }
            .onDisappear { player.stop() }
        }
    }

    private func delete(_ r: Recording) {
        if player.playingFile == r.fileName { player.stop() }
        MediaFiles.delete(audio: r.fileName)
        ctx.delete(r)
        try? ctx.save()
    }
}

// MARK: - الكاميرا والمشاركة

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
