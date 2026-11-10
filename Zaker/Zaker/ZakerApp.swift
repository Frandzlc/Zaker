import SwiftUI
import SwiftData

@main
struct ZakerApp: App {
    private let store = AppStore.make()

    var body: some Scene {
        WindowGroup {
            switch store {
            case .ready(let container):
                RootView()
                    .modelContainer(container)
            case .failed(let message):
                StartupErrorView(message: message)
            }
        }
    }
}

/// ينشئ قاعدة البيانات بأمان: إذا فشلت ما يطيح التطبيق،
/// يحاول يصلحها، وإذا ما قدر يشتغل بذاكرة مؤقتة أو يعرض الخطأ.
enum AppStore {
    case ready(ModelContainer)
    case failed(String)

    static let schema = Schema([Book.self, Note.self, Quiz.self, Deck.self, Summary.self, ChatMsg.self])

    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Zaker.store")
    }

    static func make() -> AppStore {
        let url = storeURL
        do {
            return .ready(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url)))
        } catch {
            print("ModelContainer failed: \(error)")
        }
        // القاعدة تالفة أو غير متوافقة: نحذفها ونبدأ من جديد (ملفات الكتب نفسها تبقى).
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
        do {
            return .ready(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url)))
        } catch {
            print("ModelContainer retry failed: \(error)")
        }
        do {
            return .ready(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        } catch {
            return .failed(String(describing: error))
        }
    }
}

struct StartupErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(tr("صار خطأ وقت تشغيل التطبيق", "The app failed to start"))
                .font(.title3.bold())
            ScrollView {
                Text(message)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 300)
        }
        .padding()
    }
}

struct RootView: View {
    @AppStorage(Prefs.uiLangKey) private var uiLang = "ar"

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label(tr("مكتبتي", "Library"), systemImage: "books.vertical.fill") }
            SettingsView()
                .tabItem { Label(tr("الإعدادات", "Settings"), systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
        .appLanguage()
        .id(uiLang) // يعيد بناء الواجهة لما تتغير اللغة
    }
}

enum Theme {
    static let accent = Color(red: 0.36, green: 0.30, blue: 0.85)
    static let card = Color(.secondarySystemGroupedBackground)
}

extension View {
    /// اتجاه الواجهة حسب اللغة المختارة.
    func appLanguage() -> some View {
        let ar = Prefs.uiLang == "ar"
        return self
            .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
            .environment(\.locale, Locale(identifier: ar ? "ar@numbers=latn" : "en"))
    }

    /// اتجاه النص حسب محتواه (عربي أو إنجليزي).
    func textDirection(for text: String) -> some View {
        environment(\.layoutDirection, text.isRTL ? .rightToLeft : .leftToRight)
    }
}

// MARK: - مكونات مشتركة

struct ScopeFields: View {
    let book: Book
    @Binding var usePages: Bool
    @Binding var fromPage: Int
    @Binding var toPage: Int
    @Binding var focus: String

    var body: some View {
        Section {
            if book.isPDF {
                Toggle(tr("صفحات محددة", "Specific pages"), isOn: $usePages)
                if usePages {
                    Stepper(value: $fromPage, in: 1...max(1, book.pageCount)) {
                        HStack {
                            Text(tr("من صفحة", "From page"))
                            Spacer()
                            Text("\(fromPage)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $toPage, in: fromPage...max(fromPage, book.pageCount)) {
                        HStack {
                            Text(tr("إلى صفحة", "To page"))
                            Spacer()
                            Text("\(toPage)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            TextField(tr("ركّز على… (اختياري) مثل: الفصل الثالث", "Focus on… (optional) e.g. chapter 3"), text: $focus, axis: .vertical)
        } header: {
            Text(tr("وش يغطي", "Scope"))
        } footer: {
            if book.isPDF && !usePages {
                Text(tr("بيغطي الكتاب كامل (\(book.pageCount) صفحة).", "Covers the whole book (\(book.pageCount) pages)."))
            }
        }
        .onChange(of: fromPage) { _, v in if toPage < v { toPage = v } }
    }
}

struct WorkingView: View {
    let text: String
    @State private var dots = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text(text + String(repeating: ".", count: dots))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(tr("الكتب الكبيرة ممكن تاخذ دقيقة أو أكثر.", "Large books may take a minute or more."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in dots = (dots + 1) % 4 }
    }
}

struct ErrorBox: View {
    let message: String
    var body: some View {
        Label {
            Text(message).font(.subheadline)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MarkdownText: View {
    let text: String
    var body: some View {
        if let attr = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attr)
        } else {
            Text(text)
        }
    }
}

extension Date {
    var shortLabel: String {
        formatted(.dateTime.day().month(.abbreviated).hour().minute()
            .locale(Locale(identifier: Prefs.uiLang == "ar" ? "ar@numbers=latn" : "en")))
    }
}
