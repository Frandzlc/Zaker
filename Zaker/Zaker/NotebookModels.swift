import SwiftUI
import SwiftData
import PencilKit
import UIKit

// MARK: - الدفاتر (SwiftData)

@Model
final class Notebook {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var coverHex: String = "5B4DD9"
    var paper: String = "linedAR"
    var paperColor: String = "white"
    /// إذا الدفتر مربوط بكتاب من المكتبة
    var bookID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \NotePage.notebook) var pages: [NotePage] = []
    @Relationship(deleteRule: .cascade, inverse: \Recording.notebook) var recordings: [Recording] = []

    init(title: String, paper: String, paperColor: String, coverHex: String, bookID: UUID? = nil) {
        self.id = UUID()
        self.title = title
        self.paper = paper
        self.paperColor = paperColor
        self.coverHex = coverHex
        self.bookID = bookID
        self.createdAt = .now
        self.updatedAt = .now
    }

    var sortedPages: [NotePage] { pages.sorted { $0.index < $1.index } }
    var sortedRecordings: [Recording] { recordings.sorted { $0.createdAt > $1.createdAt } }
}

@Model
final class NotePage {
    var id: UUID = UUID()
    var index: Int = 0
    var paper: String = "blank"
    var paperColor: String = "white"
    @Attribute(.externalStorage) var drawing: Data = Data()
    var itemsData: Data = Data()
    /// صورة خلفية (مثل صفحة من PDF)
    var backgroundFile: String = ""
    var notebook: Notebook?

    init(index: Int, paper: String, paperColor: String, backgroundFile: String = "", notebook: Notebook?) {
        self.id = UUID()
        self.index = index
        self.paper = paper
        self.paperColor = paperColor
        self.backgroundFile = backgroundFile
        self.notebook = notebook
    }

    var items: [PageItem] {
        get { (try? JSONDecoder().decode([PageItem].self, from: itemsData)) ?? [] }
        set { itemsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var pkDrawing: PKDrawing { (try? PKDrawing(data: drawing)) ?? PKDrawing() }
}

@Model
final class Recording {
    var title: String = ""
    var fileName: String = ""
    var duration: Double = 0
    var createdAt: Date = Date.now
    var pageIndex: Int = 0
    var notebook: Notebook?

    init(title: String, fileName: String, duration: Double, pageIndex: Int, notebook: Notebook?) {
        self.title = title
        self.fileName = fileName
        self.duration = duration
        self.pageIndex = pageIndex
        self.notebook = notebook
        self.createdAt = .now
    }

    var fileURL: URL { MediaFiles.audioDir.appendingPathComponent(fileName) }
}

/// عنصر فوق الصفحة: صورة أو نص.
struct PageItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: String          // "image" | "text"
    var file: String = ""
    var text: String = ""
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    var colorHex: String = "000000"
    var fontSize: Double = 28

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: w, height: h) }
        set { x = newValue.minX; y = newValue.minY; w = newValue.width; h = newValue.height }
    }
}

// MARK: - ملفات الوسائط

enum MediaFiles {
    private static func dir(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }
    static var imageDir: URL { dir("NoteImages") }
    static var audioDir: URL { dir("NoteAudio") }

    static func imageURL(_ name: String) -> URL { imageDir.appendingPathComponent(name) }

    /// يحفظ صورة JPEG ويرجع اسمها.
    static func saveImage(_ image: UIImage, maxSide: CGFloat = 2000, quality: CGFloat = 0.85) -> String? {
        let scaled = image.scaledDown(maxSide: maxSide)
        guard let data = scaled.jpegData(compressionQuality: quality) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: imageURL(name))
            return name
        } catch { return nil }
    }

    static func delete(image name: String) {
        guard !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: imageURL(name))
    }

    static func delete(audio name: String) {
        guard !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(name))
    }

    /// يحذف كل ملفات الدفتر (صور الصفحات والتسجيلات).
    static func cleanup(_ nb: Notebook) {
        for p in nb.pages {
            delete(image: p.backgroundFile)
            for it in p.items where it.kind == "image" { delete(image: it.file) }
        }
        for r in nb.recordings { delete(audio: r.fileName) }
    }
}

extension UIImage {
    func scaledDown(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return self }
        let s = maxSide / longest
        let newSize = CGSize(width: (size.width * s).rounded(), height: (size.height * s).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - الألوان

extension UIColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if h.count == 6 { h += "FF" }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 24) & 0xFF) / 255,
                  green: CGFloat((v >> 16) & 0xFF) / 255,
                  blue: CGFloat((v >> 8) & 0xFF) / 255,
                  alpha: CGFloat(v & 0xFF) / 255)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", c(r), c(g), c(b))
    }
}

extension Color {
    init(hex: String) { self.init(uiColor: UIColor(hex: hex)) }
}

struct ColorGroup: Identifiable {
    let id: String
    let ar: String
    let en: String
    let colors: [String]
    var title: String { tr(ar, en) }
}

/// مكتبة ألوان ضخمة (+٣٠٠ لون).
enum ColorLibrary {
    static let groups: [ColorGroup] = {
        var g: [ColorGroup] = [
            ColorGroup(id: "basic", ar: "أساسية", en: "Basic", colors: [
                "000000", "3A3A3C", "8E8E93", "FFFFFF", "1E3A8A", "2563EB", "0EA5E9", "DC2626",
                "EA580C", "F59E0B", "FACC15", "16A34A", "059669", "7C3AED", "DB2777", "92400E"]),
            ColorGroup(id: "study", ar: "مذاكرة", en: "Study", colors: [
                "0B1F5C", "1D4ED8", "B91C1C", "15803D", "6D28D9", "C2410C", "0F766E", "374151",
                "BE185D", "854D0E", "1E40AF", "991B1B"]),
            ColorGroup(id: "highlight", ar: "هايلايتر فسفوري", en: "Neon highlighters", colors: [
                "FFF200", "FFE135", "CCFF00", "39FF14", "00FF9F", "00FFFF", "00BFFF", "FF6EC7",
                "FF1493", "FF9933", "FF5F1F", "BF00FF", "E0B0FF", "FDFF6B", "B2FF59", "7DF9FF"]),
            ColorGroup(id: "pastel", ar: "باستيل", en: "Pastel", colors: [
                "FFD1DC", "FFB7B2", "FFDAC1", "FFF1B5", "E2F0CB", "B5EAD7", "C7CEEA", "A0C4FF",
                "BDB2FF", "FFC6FF", "CDB4DB", "BDE0FE", "A2D2FF", "FFAFCC", "D8F3DC", "FDE2E4"]),
            ColorGroup(id: "earth", ar: "ألوان ترابية", en: "Earth", colors: [
                "6B4423", "8B5A2B", "A0522D", "C19A6B", "D2B48C", "E1C699", "8A9A5B", "556B2F",
                "6B8E23", "BC8A5F", "7F5539", "B08968", "DDB892", "9C6644", "606C38", "283618"]),
            ColorGroup(id: "ocean", ar: "بحر", en: "Ocean", colors: [
                "03045E", "023E8A", "0077B6", "0096C7", "00B4D8", "48CAE4", "90E0EF", "ADE8F4",
                "006D77", "83C5BE", "2A9D8F", "264653", "1B4965", "5FA8D3", "62B6CB", "CAE9FF"]),
            ColorGroup(id: "forest", ar: "غابة", en: "Forest", colors: [
                "081C15", "1B4332", "2D6A4F", "40916C", "52B788", "74C69D", "95D5B2", "B7E4C7",
                "386641", "6A994E", "A7C957", "3A5A40", "588157", "A3B18A", "344E41", "DAD7CD"]),
            ColorGroup(id: "sunset", ar: "غروب", en: "Sunset", colors: [
                "F72585", "B5179E", "7209B7", "560BAD", "480CA8", "3A0CA3", "FF6D00", "FF7900",
                "FF8500", "FF9100", "FF9E00", "F94144", "F3722C", "F8961E", "F9C74F", "E76F51"]),
            ColorGroup(id: "skin", ar: "درجات البشرة", en: "Skin tones", colors: [
                "FFDBAC", "F1C27D", "E0AC69", "C68642", "8D5524", "5C3A21", "FFE0BD", "FFCD94",
                "EAC086", "D4A373", "A47551", "3D2314"]),
            ColorGroup(id: "metal", ar: "معدني ورمادي", en: "Grays & metals", colors: [
                "111111", "222222", "333333", "444444", "555555", "666666", "777777", "888888",
                "999999", "AAAAAA", "BBBBBB", "CCCCCC", "DDDDDD", "EEEEEE", "D4AF37", "C0C0C0",
                "B87333", "CD7F32", "E5E4E2", "71797E"]),
            ColorGroup(id: "candy", ar: "حلويات", en: "Candy", colors: [
                "FF4D6D", "FF758F", "FF8FA3", "FFB3C1", "C9184A", "A4133C", "FFBE0B", "FB5607",
                "FF006E", "8338EC", "3A86FF", "06D6A0", "EF476F", "FFD166", "118AB2", "073B4C"]),
            ColorGroup(id: "vintage", ar: "كلاسيكي", en: "Vintage", colors: [
                "8D99AE", "2B2D42", "EDF2F4", "EF233C", "D90429", "6D597A", "B56576", "E56B6F",
                "EAAC8B", "355070", "9A8C98", "C9ADA7", "4A4E69", "22223B", "F2E9E4", "A68A64"]),
        ]
        // طيف كامل: ٢٤ درجة لون × ٨ مستويات = ١٩٢ لون
        var spectrum: [String] = []
        let levels: [(s: CGFloat, b: CGFloat)] = [
            (0.25, 1.0), (0.45, 1.0), (0.65, 1.0), (0.85, 1.0),
            (1.0, 0.9), (1.0, 0.72), (1.0, 0.52), (1.0, 0.35)]
        for lv in levels {
            for hue in 0..<24 {
                let h = CGFloat(hue) / 24
                spectrum.append(UIColor(hue: h, saturation: lv.s, brightness: lv.b, alpha: 1).hexString)
            }
        }
        g.append(ColorGroup(id: "spectrum", ar: "الطيف الكامل", en: "Full spectrum", colors: spectrum))
        return g
    }()

    static var totalCount: Int { groups.reduce(0) { $0 + $1.colors.count } }
}

// MARK: - الأقلام

enum InkKind: String, CaseIterable, Codable, Identifiable {
    case pen, pencil, marker, monoline, fountainPen, watercolor, crayon
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return tr("قلم حبر", "Pen")
        case .pencil: return tr("قلم رصاص", "Pencil")
        case .marker: return tr("هايلايتر", "Highlighter")
        case .monoline: return tr("قلم فاين لاينر", "Fineliner")
        case .fountainPen: return tr("قلم خط عربي / ريشة", "Calligraphy / fountain")
        case .watercolor: return tr("ألوان مائية", "Watercolor")
        case .crayon: return tr("ألوان شمعية", "Crayon")
        }
    }

    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .monoline: return "pencil.line"
        case .fountainPen: return "signature"
        case .watercolor: return "paintbrush.pointed.fill"
        case .crayon: return "paintbrush.fill"
        }
    }

    var pkType: PKInkingTool.InkType {
        switch self {
        case .pen: return .pen
        case .pencil: return .pencil
        case .marker: return .marker
        case .monoline: return .monoline
        case .fountainPen: return .fountainPen
        case .watercolor: return .watercolor
        case .crayon: return .crayon
        }
    }

    /// المقاسات المقترحة في المكتبة
    var widths: [Double] {
        switch self {
        case .pen: return [1, 2, 3, 4, 6, 9, 14]
        case .pencil: return [2, 4, 6, 10, 16]
        case .marker: return [10, 15, 20, 30, 40]
        case .monoline: return [0.5, 1, 1.5, 2, 3, 5]
        case .fountainPen: return [2, 4, 6, 10, 16, 24]
        case .watercolor: return [8, 15, 25, 40, 60]
        case .crayon: return [5, 10, 15, 25, 40]
        }
    }
}

struct PenPreset: Codable, Hashable, Identifiable {
    var id = UUID()
    var ink: InkKind
    var colorHex: String
    var width: Double

    var tool: PKInkingTool {
        let range = ink.pkType.validWidthRange
        let w = min(max(CGFloat(width), range.lowerBound), range.upperBound)
        return PKInkingTool(ink.pkType, color: UIColor(hex: colorHex), width: w)
    }

    var color: Color { Color(hex: colorHex) }
}

/// مجموعات أقلام جاهزة.
struct PenSet: Identifiable {
    let id: String
    let ar: String
    let en: String
    let pens: [PenPreset]
    var title: String { tr(ar, en) }
}

enum PenLibrary {
    static func p(_ ink: InkKind, _ hex: String, _ w: Double) -> PenPreset { PenPreset(ink: ink, colorHex: hex, width: w) }

    static let defaultFavorites: [PenPreset] = [
        p(.pen, "000000", 3), p(.pen, "1D4ED8", 3), p(.pen, "B91C1C", 3), p(.pen, "15803D", 3),
        p(.pencil, "3A3A3C", 4), p(.marker, "FFF200", 20), p(.marker, "39FF14", 20), p(.fountainPen, "000000", 6),
    ]

    static let sets: [PenSet] = [
        PenSet(id: "school", ar: "شنطة المدرسة", en: "School bag", pens: [
            p(.pen, "000000", 3), p(.pen, "1D4ED8", 3), p(.pen, "B91C1C", 3), p(.pen, "15803D", 3),
            p(.pencil, "3A3A3C", 4), p(.marker, "FFF200", 20), p(.marker, "FF6EC7", 20), p(.marker, "00BFFF", 20)]),
        PenSet(id: "math", ar: "رياضيات", en: "Math", pens: [
            p(.monoline, "000000", 1.5), p(.monoline, "1D4ED8", 1.5), p(.monoline, "DC2626", 1.5),
            p(.pencil, "3A3A3C", 2), p(.pen, "16A34A", 2), p(.marker, "FFF200", 15), p(.monoline, "7C3AED", 1)]),
        PenSet(id: "arabic", ar: "خط عربي", en: "Arabic calligraphy", pens: [
            p(.fountainPen, "000000", 6), p(.fountainPen, "000000", 12), p(.fountainPen, "000000", 20),
            p(.fountainPen, "92400E", 10), p(.fountainPen, "B91C1C", 10), p(.fountainPen, "1E3A8A", 10), p(.fountainPen, "D4AF37", 14)]),
        PenSet(id: "english", ar: "إنجليزي", en: "English writing", pens: [
            p(.pen, "000000", 2), p(.pen, "1E40AF", 2), p(.fountainPen, "0B1F5C", 4), p(.pen, "DC2626", 2),
            p(.pencil, "374151", 3), p(.marker, "CCFF00", 18)]),
        PenSet(id: "neon", ar: "هايلايتر فسفوري", en: "Neon highlighters", pens: [
            p(.marker, "FFF200", 22), p(.marker, "39FF14", 22), p(.marker, "00FFFF", 22), p(.marker, "FF6EC7", 22),
            p(.marker, "FF9933", 22), p(.marker, "BF00FF", 22), p(.marker, "FF1493", 22), p(.marker, "00BFFF", 22)]),
        PenSet(id: "pastel", ar: "أقلام باستيل", en: "Pastel pens", pens: [
            p(.monoline, "FFB7B2", 3), p(.monoline, "B5EAD7", 3), p(.monoline, "C7CEEA", 3), p(.monoline, "FFDAC1", 3),
            p(.monoline, "BDB2FF", 3), p(.monoline, "A0C4FF", 3), p(.marker, "FFD1DC", 18), p(.marker, "E2F0CB", 18)]),
        PenSet(id: "art", ar: "رسم وتلوين", en: "Art", pens: [
            p(.watercolor, "0077B6", 30), p(.watercolor, "F72585", 30), p(.watercolor, "FFBE0B", 30),
            p(.crayon, "D90429", 15), p(.crayon, "2D6A4F", 15), p(.crayon, "7209B7", 15), p(.pencil, "000000", 6), p(.pen, "000000", 1)]),
        PenSet(id: "chalk", ar: "سبورة (ورق غامق)", en: "Chalkboard (dark paper)", pens: [
            p(.crayon, "FFFFFF", 10), p(.crayon, "FFF1B5", 10), p(.crayon, "A0C4FF", 10), p(.crayon, "FFB7B2", 10),
            p(.pen, "FFFFFF", 3), p(.marker, "39FF14", 20)]),
    ]

    private static let favKey = "penFavorites"

    static func loadFavorites() -> [PenPreset] {
        guard let d = UserDefaults.standard.data(forKey: favKey),
              let f = try? JSONDecoder().decode([PenPreset].self, from: d), !f.isEmpty else { return defaultFavorites }
        return f
    }

    static func saveFavorites(_ f: [PenPreset]) {
        if let d = try? JSONEncoder().encode(f) { UserDefaults.standard.set(d, forKey: favKey) }
    }

    private static let recentKey = "recentColors"
    static func loadRecentColors() -> [String] { UserDefaults.standard.stringArray(forKey: recentKey) ?? [] }
    static func pushRecent(_ hex: String) {
        var r = loadRecentColors().filter { $0 != hex }
        r.insert(hex, at: 0)
        UserDefaults.standard.set(Array(r.prefix(16)), forKey: recentKey)
    }
}

// MARK: - أنواع الورق (التسطير)

enum PaperStyle: String, CaseIterable, Identifiable {
    case blank
    case linedAR, linedEN, college, wide
    case handwritingEN, handwritingAR, arabicCalligraphy
    case mathGrid, bigGrid, graph, dots, coordinate, mathMargin, isometric, numberLine
    case cornell, twoColumn, todo, music, storyboard

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case general, languages, math, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return tr("عام", "General")
            case .languages: return tr("لغات (عربي وإنجليزي)", "Languages (Arabic & English)")
            case .math: return tr("رياضيات وعلوم", "Math & science")
            case .other: return tr("تنظيم ومذاكرة", "Study & planning")
            }
        }
    }

    var group: Group {
        switch self {
        case .blank, .linedAR, .linedEN, .college, .wide: return .general
        case .handwritingEN, .handwritingAR, .arabicCalligraphy: return .languages
        case .mathGrid, .bigGrid, .graph, .dots, .coordinate, .mathMargin, .isometric, .numberLine: return .math
        case .cornell, .twoColumn, .todo, .music, .storyboard: return .other
        }
    }

    var title: String {
        switch self {
        case .blank: return tr("سادة", "Blank")
        case .linedAR: return tr("مسطر عربي (الهامش يمين)", "Arabic lined (right margin)")
        case .linedEN: return tr("مسطر إنجليزي (الهامش يسار)", "English lined (left margin)")
        case .college: return tr("مسطر ضيق", "College ruled")
        case .wide: return tr("مسطر عريض", "Wide ruled")
        case .handwritingEN: return tr("تحسين خط إنجليزي (٤ أسطر)", "English handwriting (4 lines)")
        case .handwritingAR: return tr("تحسين خط عربي", "Arabic handwriting")
        case .arabicCalligraphy: return tr("خط عربي (نقاط القياس)", "Arabic calligraphy guides")
        case .mathGrid: return tr("رياضيات مربعات صغيرة", "Math small squares")
        case .bigGrid: return tr("مربعات كبيرة", "Large squares")
        case .graph: return tr("ورق رسم بياني (ملم)", "Graph paper (mm)")
        case .dots: return tr("نقاط", "Dot grid")
        case .coordinate: return tr("مستوى إحداثي (محاور)", "Coordinate plane")
        case .mathMargin: return tr("رياضيات مع هامش", "Math with margin")
        case .isometric: return tr("ورق متساوي القياس", "Isometric")
        case .numberLine: return tr("خطوط الأعداد", "Number lines")
        case .cornell: return tr("كورنيل للملاحظات", "Cornell notes")
        case .twoColumn: return tr("عمودين", "Two columns")
        case .todo: return tr("قائمة مهام", "To-do list")
        case .music: return tr("نوتة موسيقية", "Music staff")
        case .storyboard: return tr("مربعات قصة", "Storyboard")
        }
    }
}

enum PaperColor: String, CaseIterable, Identifiable {
    case white, cream, yellow, blue, green, pink, gray, dark, chalkboard
    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: return tr("أبيض", "White")
        case .cream: return tr("كريمي", "Cream")
        case .yellow: return tr("أصفر", "Yellow")
        case .blue: return tr("أزرق فاتح", "Light blue")
        case .green: return tr("أخضر فاتح", "Light green")
        case .pink: return tr("وردي", "Pink")
        case .gray: return tr("رمادي", "Gray")
        case .dark: return tr("أسود", "Dark")
        case .chalkboard: return tr("سبورة خضراء", "Chalkboard")
        }
    }

    var background: UIColor {
        switch self {
        case .white: return UIColor(hex: "FFFFFF")
        case .cream: return UIColor(hex: "FBF6E9")
        case .yellow: return UIColor(hex: "FFF8C4")
        case .blue: return UIColor(hex: "EAF3FF")
        case .green: return UIColor(hex: "EAF7EC")
        case .pink: return UIColor(hex: "FDEDF2")
        case .gray: return UIColor(hex: "EFEFF1")
        case .dark: return UIColor(hex: "1C1C1E")
        case .chalkboard: return UIColor(hex: "1F3B2D")
        }
    }

    var isDark: Bool { self == .dark || self == .chalkboard }
    var line: UIColor { isDark ? UIColor.white.withAlphaComponent(0.22) : UIColor(hex: "9DB7D5") }
    var lineStrong: UIColor { isDark ? UIColor.white.withAlphaComponent(0.45) : UIColor(hex: "5E86B3") }
    var margin: UIColor { isDark ? UIColor(hex: "FF8A8A").withAlphaComponent(0.6) : UIColor(hex: "E57373") }
}

enum PageSize {
    static let width: CGFloat = 820
    static let height: CGFloat = 1160
    static var size: CGSize { CGSize(width: width, height: height) }
}

/// يرسم الورق (اللون والتسطير) بـ Core Graphics.
enum PaperRenderer {
    static func draw(style: PaperStyle, color: PaperColor, background: UIImage?, in ctx: CGContext, size: CGSize) {
        let W = size.width, H = size.height
        ctx.setFillColor(color.background.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        if let background {
            let s = min(W / background.size.width, H / background.size.height)
            let w = background.size.width * s, h = background.size.height * s
            background.draw(in: CGRect(x: (W - w) / 2, y: (H - h) / 2, width: w, height: h))
            return
        }

        let k = W / PageSize.width   // نسبة التصغير (للمصغرات)
        let line = color.line.cgColor, strong = color.lineStrong.cgColor, margin = color.margin.cgColor

        func hLine(_ y: CGFloat, _ c: CGColor, _ w: CGFloat = 1, from x0: CGFloat = 0, to x1: CGFloat? = nil, dash: [CGFloat]? = nil) {
            ctx.saveGState()
            ctx.setStrokeColor(c)
            ctx.setLineWidth(w * k)
            if let dash { ctx.setLineDash(phase: 0, lengths: dash.map { $0 * k }) }
            ctx.move(to: CGPoint(x: x0, y: y))
            ctx.addLine(to: CGPoint(x: x1 ?? W, y: y))
            ctx.strokePath()
            ctx.restoreGState()
        }
        func vLine(_ x: CGFloat, _ c: CGColor, _ w: CGFloat = 1, from y0: CGFloat = 0, to y1: CGFloat? = nil) {
            ctx.setStrokeColor(c)
            ctx.setLineWidth(w * k)
            ctx.move(to: CGPoint(x: x, y: y0))
            ctx.addLine(to: CGPoint(x: x, y: y1 ?? H))
            ctx.strokePath()
        }
        func grid(_ step: CGFloat, _ c: CGColor, _ w: CGFloat = 1, boldEvery: Int = 0, bold: CGColor? = nil) {
            let s = step * k
            var i = 0
            var x: CGFloat = 0
            while x <= W { vLine(x, (boldEvery > 0 && i % boldEvery == 0) ? (bold ?? c) : c, w); x += s; i += 1 }
            i = 0
            var y: CGFloat = 0
            while y <= H { hLine(y, (boldEvery > 0 && i % boldEvery == 0) ? (bold ?? c) : c, w); y += s; i += 1 }
        }
        func ruled(spacing: CGFloat, top: CGFloat = 110) {
            var y = top * k
            while y < H - 30 * k { hLine(y, line); y += spacing * k }
        }

        switch style {
        case .blank:
            break
        case .linedAR:
            ruled(spacing: 36)
            hLine(80 * k, margin, 1.2)
            vLine(W - 80 * k, margin, 1.5)
        case .linedEN:
            ruled(spacing: 36)
            hLine(80 * k, margin, 1.2)
            vLine(80 * k, margin, 1.5)
        case .college:
            ruled(spacing: 28, top: 90)
            vLine(70 * k, margin, 1.2)
            vLine(W - 70 * k, margin, 1.2)
        case .wide:
            ruled(spacing: 46)
            vLine(80 * k, margin, 1.2)
        case .handwritingEN:
            // ٤ أسطر: أعلى، منتصف متقطع، سطر الكتابة، سطر النزول
            var y: CGFloat = 90 * k
            let unit: CGFloat = 26 * k
            while y + unit * 3 < H - 30 * k {
                hLine(y, strong, 1.2)
                hLine(y + unit, line, 1, dash: [8, 6])
                hLine(y + unit * 2, margin, 1.6)
                hLine(y + unit * 3, line, 0.8, dash: [3, 5])
                y += unit * 3 + 34 * k
            }
        case .handwritingAR:
            // سطر أساسي واضح + خطوط لارتفاع السن والألف + خط للنزول
            var y: CGFloat = 100 * k
            let unit: CGFloat = 20 * k
            while y + unit * 4 < H - 30 * k {
                hLine(y, line, 0.8, dash: [3, 5])               // ارتفاع الألف
                hLine(y + unit * 2, line, 1, dash: [8, 6])      // ارتفاع السن
                hLine(y + unit * 3, margin, 1.8)                // السطر
                hLine(y + unit * 4.5, line, 0.8, dash: [3, 5])  // النزول
                y += unit * 4.5 + 34 * k
            }
            vLine(W - 60 * k, margin, 1.2)
        case .arabicCalligraphy:
            // سطر مع مربعات نقاط القياس (نقطة الخط)
            var y: CGFloat = 120 * k
            let dot: CGFloat = 12 * k
            while y < H - 60 * k {
                hLine(y, strong, 1.4)
                hLine(y - dot * 5, line, 0.8, dash: [3, 5])
                hLine(y - dot * 3, line, 0.8, dash: [3, 5])
                hLine(y + dot * 3, line, 0.8, dash: [3, 5])
                // عمود نقاط القياس على اليمين
                ctx.setFillColor(color.lineStrong.cgColor)
                for i in 0..<5 {
                    let r = CGRect(x: W - 50 * k - (i % 2 == 0 ? 0 : dot * 0.6), y: y - dot * CGFloat(i + 1), width: dot, height: dot)
                    ctx.fill(r.insetBy(dx: dot * 0.15, dy: dot * 0.15))
                }
                y += dot * 10
            }
        case .mathGrid:
            grid(20, line, 0.6, boldEvery: 5, bold: strong)
        case .bigGrid:
            grid(40, line, 0.9)
        case .graph:
            grid(8, color.line.withAlphaComponent(0.45).cgColor, 0.4, boldEvery: 5, bold: line)
            grid(40, strong, 0.9)
        case .dots:
            ctx.setFillColor(color.lineStrong.cgColor)
            let s = 28 * k
            var y = s
            while y < H { var x = s; while x < W { ctx.fillEllipse(in: CGRect(x: x - 1.6 * k, y: y - 1.6 * k, width: 3.2 * k, height: 3.2 * k)); x += s }; y += s }
        case .coordinate:
            grid(20, line, 0.5, boldEvery: 5, bold: color.lineStrong.withAlphaComponent(0.6).cgColor)
            let cx = (W / 2 / (20 * k)).rounded() * 20 * k
            let cy = (H / 2 / (20 * k)).rounded() * 20 * k
            let axis = (color.isDark ? UIColor.white : UIColor.black).cgColor
            hLine(cy, axis, 2)
            vLine(cx, axis, 2)
            // أسهم
            ctx.setFillColor(axis)
            let a = 10 * k
            ctx.move(to: CGPoint(x: W - 4 * k, y: cy)); ctx.addLine(to: CGPoint(x: W - 4 * k - a, y: cy - a / 2)); ctx.addLine(to: CGPoint(x: W - 4 * k - a, y: cy + a / 2)); ctx.fillPath()
            ctx.move(to: CGPoint(x: cx, y: 4 * k)); ctx.addLine(to: CGPoint(x: cx - a / 2, y: 4 * k + a)); ctx.addLine(to: CGPoint(x: cx + a / 2, y: 4 * k + a)); ctx.fillPath()
            // ترقيم المحاور
            let font = UIFont.systemFont(ofSize: 10 * k)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color.isDark ? UIColor.white : UIColor.darkGray]
            UIGraphicsPushContext(ctx)
            var n = -20
            while n <= 20 {
                if n != 0 {
                    let x = cx + CGFloat(n) * 20 * k
                    if x > 10 * k && x < W - 16 * k { ("\(n)" as NSString).draw(at: CGPoint(x: x - 4 * k, y: cy + 3 * k), withAttributes: attrs) }
                    let y = cy - CGFloat(n) * 20 * k
                    if y > 16 * k && y < H - 10 * k { ("\(n)" as NSString).draw(at: CGPoint(x: cx + 4 * k, y: y - 6 * k), withAttributes: attrs) }
                }
                n += 2
            }
            ("0" as NSString).draw(at: CGPoint(x: cx + 3 * k, y: cy + 3 * k), withAttributes: attrs)
            UIGraphicsPopContext()
        case .mathMargin:
            grid(20, line, 0.6)
            ctx.setFillColor(color.background.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: 70 * k))
            hLine(70 * k, margin, 1.4)
            vLine(W - 90 * k, margin, 1.4)
        case .isometric:
            ctx.setStrokeColor(line)
            ctx.setLineWidth(0.6 * k)
            let s = 30 * k
            let dx = s * sqrt(3)
            var x: CGFloat = -H * 2
            while x < W + H * 2 {
                ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x + H * sqrt(3), y: H))
                ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x - H * sqrt(3), y: H))
                x += dx
            }
            ctx.strokePath()
            var vx: CGFloat = 0
            while vx <= W { vLine(vx, line, 0.6); vx += dx / 2 }
        case .numberLine:
            var y: CGFloat = 120 * k
            let font = UIFont.systemFont(ofSize: 11 * k)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color.isDark ? UIColor.white : UIColor.darkGray]
            UIGraphicsPushContext(ctx)
            while y < H - 60 * k {
                hLine(y, strong, 1.6, from: 40 * k, to: W - 40 * k)
                let step = (W - 100 * k) / 20
                for i in 0...20 {
                    let x = 50 * k + CGFloat(i) * step
                    ctx.setStrokeColor(strong)
                    ctx.setLineWidth(1.2 * k)
                    let t: CGFloat = (i % 5 == 0 ? 10 : 6) * k
                    ctx.move(to: CGPoint(x: x, y: y - t)); ctx.addLine(to: CGPoint(x: x, y: y + t)); ctx.strokePath()
                    if i % 5 == 0 { ("\(i - 10)" as NSString).draw(at: CGPoint(x: x - 6 * k, y: y + 12 * k), withAttributes: attrs) }
                }
                y += 150 * k
            }
            UIGraphicsPopContext()
        case .cornell:
            ruled(spacing: 34, top: 140)
            hLine(110 * k, margin, 1.6)
            vLine(W - 230 * k, margin, 1.6, from: 110 * k, to: H - 230 * k)
            ctx.setFillColor(color.background.cgColor)
            ctx.fill(CGRect(x: 0, y: H - 230 * k, width: W, height: 230 * k))
            hLine(H - 230 * k, margin, 1.6)
        case .twoColumn:
            ruled(spacing: 36)
            vLine(W / 2, margin, 1.4, from: 80 * k)
            hLine(80 * k, margin, 1.2)
        case .todo:
            var y: CGFloat = 130 * k
            hLine(90 * k, margin, 1.4)
            while y < H - 40 * k {
                hLine(y, line)
                ctx.setStrokeColor(strong)
                ctx.setLineWidth(1.4 * k)
                ctx.stroke(CGRect(x: W - 70 * k, y: y - 30 * k, width: 22 * k, height: 22 * k))
                ctx.stroke(CGRect(x: 48 * k, y: y - 30 * k, width: 22 * k, height: 22 * k))
                y += 46 * k
            }
        case .music:
            var y: CGFloat = 110 * k
            while y < H - 80 * k {
                for i in 0..<5 { hLine(y + CGFloat(i) * 12 * k, strong, 1, from: 50 * k, to: W - 50 * k) }
                vLine(50 * k, strong, 1.2, from: y, to: y + 48 * k)
                vLine(W - 50 * k, strong, 1.2, from: y, to: y + 48 * k)
                y += 110 * k
            }
        case .storyboard:
            let cols = 2, rows = 3
            let pad = 40 * k
            let cw = (W - pad * CGFloat(cols + 1)) / CGFloat(cols)
            let ch = (H - pad * CGFloat(rows + 1)) / CGFloat(rows) - 70 * k
            ctx.setStrokeColor(strong)
            ctx.setLineWidth(1.6 * k)
            for r in 0..<rows {
                for c in 0..<cols {
                    let x = pad + CGFloat(c) * (cw + pad)
                    let y = pad + CGFloat(r) * (ch + 70 * k + pad)
                    ctx.stroke(CGRect(x: x, y: y, width: cw, height: ch))
                    hLine(y + ch + 30 * k, line, 1, from: x, to: x + cw)
                    hLine(y + ch + 60 * k, line, 1, from: x, to: x + cw)
                }
            }
        }
    }

    static func image(style: PaperStyle, color: PaperColor, background: UIImage? = nil, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { r in
            draw(style: style, color: color, background: background, in: r.cgContext, size: size)
        }
    }

    /// صورة كاملة للصفحة: الورق + الصور والنصوص + الكتابة بالقلم.
    static func render(page: NotePage, size: CGSize, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let style = PaperStyle(rawValue: page.paper) ?? .blank
        let color = PaperColor(rawValue: page.paperColor) ?? .white
        let bg = page.backgroundFile.isEmpty ? nil : UIImage(contentsOfFile: MediaFiles.imageURL(page.backgroundFile).path)
        let k = size.width / PageSize.width
        return UIGraphicsImageRenderer(size: size, format: format).image { r in
            let ctx = r.cgContext
            draw(style: style, color: color, background: bg, in: ctx, size: size)
            for it in page.items {
                let f = CGRect(x: it.x * k, y: it.y * k, width: it.w * k, height: it.h * k)
                if it.kind == "image", let img = UIImage(contentsOfFile: MediaFiles.imageURL(it.file).path) {
                    img.draw(in: f)
                } else if it.kind == "text" {
                    let p = NSMutableParagraphStyle()
                    p.alignment = it.text.isRTL ? .right : .left
                    p.baseWritingDirection = it.text.isRTL ? .rightToLeft : .leftToRight
                    (it.text as NSString).draw(in: f, withAttributes: [
                        .font: UIFont.systemFont(ofSize: it.fontSize * k),
                        .foregroundColor: UIColor(hex: it.colorHex),
                        .paragraphStyle: p])
                }
            }
            let drawing = page.pkDrawing
            if !drawing.strokes.isEmpty {
                var img = UIImage()
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                    img = drawing.image(from: CGRect(origin: .zero, size: PageSize.size), scale: k * max(scale, 1))
                }
                img.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }
}
