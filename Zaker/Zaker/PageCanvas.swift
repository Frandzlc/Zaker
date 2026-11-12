import SwiftUI
import PencilKit
import UIKit

enum ToolMode: String {
    case draw, erase, lasso, select
}

/// حالة الأدوات المشتركة بين شريط الأدوات والصفحة.
final class ToolState: ObservableObject {
    @Published var mode: ToolMode = .draw
    @Published var pen: PenPreset
    @Published var bitmapEraser = false
    @Published var eraserWidth: Double = 20
    @Published var ruler = false
    @Published var fingerDraws: Bool = UserDefaults.standard.object(forKey: "fingerDraws") as? Bool ?? true {
        didSet { UserDefaults.standard.set(fingerDraws, forKey: "fingerDraws") }
    }
    @Published var favorites: [PenPreset] {
        didSet { PenLibrary.saveFavorites(favorites) }
    }
    weak var canvas: PKCanvasView?

    init() {
        let f = PenLibrary.loadFavorites()
        favorites = f
        pen = f.first ?? PenLibrary.defaultFavorites[0]
    }

    func select(_ p: PenPreset) {
        pen = p
        mode = .draw
    }

    func setColor(_ hex: String) {
        pen.colorHex = hex
        PenLibrary.pushRecent(hex)
        if mode != .draw { mode = .draw }
        // حدّث القلم المفضل لو كان مختار
        if let i = favorites.firstIndex(where: { $0.id == pen.id }) { favorites[i] = pen }
    }

    func setWidth(_ w: Double) {
        pen.width = w
        if let i = favorites.firstIndex(where: { $0.id == pen.id }) { favorites[i] = pen }
    }

    func addCurrentToFavorites() {
        var p = pen
        p.id = UUID()
        favorites.append(p)
        pen = p
    }

    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }
}

// MARK: - SwiftUI wrapper

struct PageCanvasView: UIViewRepresentable {
    let page: NotePage
    @ObservedObject var tools: ToolState
    /// يزيد كل ما تغيرت عناصر الصفحة أو ورقها من SwiftUI
    let version: Int
    var onEditText: (PageItem) -> Void
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> PageScrollView {
        let v = PageScrollView()
        let c = context.coordinator
        v.canvas.delegate = c
        v.canvas.drawing = page.pkDrawing
        v.setPaper(page.paper, page.paperColor, page.backgroundFile)
        v.reloadItems(page.items)
        v.onItemsChanged = { [weak c] items in c?.itemsChanged(items) }
        v.onEditText = { [weak c] item in c?.parent.onEditText(item) }
        c.version = version
        tools.canvas = v.canvas
        v.apply(tools)
        return v
    }

    func updateUIView(_ v: PageScrollView, context: Context) {
        context.coordinator.parent = self
        tools.canvas = v.canvas
        if context.coordinator.version != version {
            context.coordinator.version = version
            v.setPaper(page.paper, page.paperColor, page.backgroundFile)
            v.reloadItems(page.items)
        }
        v.apply(tools)
    }

    static func dismantleUIView(_ uiView: PageScrollView, coordinator: Coordinator) {
        coordinator.flush(uiView.canvas)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PageCanvasView
        var version = 0
        private var saveWork: DispatchWorkItem?

        init(parent: PageCanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            saveWork?.cancel()
            let page = parent.page
            let onChange = parent.onChange
            let work = DispatchWorkItem { [weak canvasView] in
                guard let canvasView else { return }
                page.drawing = canvasView.drawing.dataRepresentation()
                onChange()
            }
            saveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }

        /// يحفظ الكتابة فورًا (عند تغيير الصفحة أو الخروج).
        func flush(_ canvas: PKCanvasView) {
            guard let work = saveWork, !work.isCancelled else { return }
            work.cancel()
            saveWork = nil
            parent.page.drawing = canvas.drawing.dataRepresentation()
            parent.onChange()
        }

        func itemsChanged(_ items: [PageItem]) {
            parent.page.items = items
            parent.onChange()
        }
    }
}

// MARK: - UIKit

/// صفحة بحجم ثابت داخل ScrollView قابل للتكبير.
final class PageScrollView: UIScrollView, UIScrollViewDelegate {
    let pageView = UIView(frame: CGRect(origin: .zero, size: PageSize.size))
    let paperView = PaperView(frame: CGRect(origin: .zero, size: PageSize.size))
    let itemsView = UIView(frame: CGRect(origin: .zero, size: PageSize.size))
    let canvas = PKCanvasView(frame: CGRect(origin: .zero, size: PageSize.size))

    var onItemsChanged: (([PageItem]) -> Void)?
    var onEditText: ((PageItem) -> Void)?
    private var items: [PageItem] = []
    private var lastWidth: CGFloat = 0
    private var selectMode = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = UIColor.systemGray5
        showsHorizontalScrollIndicator = false
        bouncesZoom = true
        delaysContentTouches = false

        pageView.backgroundColor = .white
        pageView.layer.shadowColor = UIColor.black.cgColor
        pageView.layer.shadowOpacity = 0.18
        pageView.layer.shadowRadius = 8
        pageView.layer.shadowOffset = CGSize(width: 0, height: 3)
        pageView.semanticContentAttribute = .forceLeftToRight

        itemsView.backgroundColor = .clear
        itemsView.clipsToBounds = true

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.contentSize = PageSize.size

        pageView.addSubview(paperView)
        pageView.addSubview(itemsView)
        pageView.addSubview(canvas)
        addSubview(pageView)
        contentSize = PageSize.size
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        if abs(bounds.width - lastWidth) > 1 {
            lastWidth = bounds.width
            let fit = (bounds.width - 16) / PageSize.width
            minimumZoomScale = fit
            maximumZoomScale = fit * 5
            zoomScale = fit
            updateRenderScale()
        }
        centerPage()
    }

    private func centerPage() {
        let w = pageView.frame.width, h = pageView.frame.height
        let x = max((bounds.width - w) / 2, 0)
        let y = max((bounds.height - h) / 2, 8)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: 8, right: x)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { pageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPage() }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        updateRenderScale()
    }

    /// يخلي الخط والورق واضحين وقت التكبير.
    private func updateRenderScale() {
        let s = min(max(UIScreen.main.scale * zoomScale, 1), 6)
        canvas.contentScaleFactor = s
        paperView.contentScaleFactor = min(s, 4)
        paperView.setNeedsDisplay()
    }

    func setPaper(_ style: String, _ color: String, _ bg: String) {
        paperView.configure(style: PaperStyle(rawValue: style) ?? .blank,
                            color: PaperColor(rawValue: color) ?? .white,
                            backgroundFile: bg)
    }

    func apply(_ t: ToolState) {
        switch t.mode {
        case .draw: canvas.tool = t.pen.tool
        case .erase: canvas.tool = t.bitmapEraser ? PKEraserTool(.bitmap, width: CGFloat(t.eraserWidth)) : PKEraserTool(.vector)
        case .lasso: canvas.tool = PKLassoTool()
        case .select: break
        }
        canvas.isRulerActive = t.ruler
        canvas.drawingPolicy = t.fingerDraws ? .anyInput : .pencilOnly

        let select = t.mode == .select
        canvas.isUserInteractionEnabled = !select
        itemsView.isUserInteractionEnabled = select
        // بالإصبع: إصبعين للتحريك. بالقلم فقط أو وضع التحديد: إصبع واحد.
        panGestureRecognizer.minimumNumberOfTouches = (t.fingerDraws && !select) ? 2 : 1
        if select != selectMode {
            selectMode = select
            itemsView.subviews.compactMap { $0 as? ItemView }.forEach { $0.setSelectable(select) }
        }
    }

    func reloadItems(_ newItems: [PageItem]) {
        items = newItems
        itemsView.subviews.forEach { $0.removeFromSuperview() }
        for it in newItems {
            let v = ItemView(item: it)
            v.setSelectable(selectMode)
            v.onMoved = { [weak self] item in self?.update(item) }
            v.onDelete = { [weak self] item in self?.remove(item) }
            v.onEdit = { [weak self] item in self?.onEditText?(item) }
            v.onDuplicate = { [weak self] item in self?.duplicate(item) }
            v.onFront = { [weak self] item in self?.bringFront(item) }
            itemsView.addSubview(v)
        }
    }

    private func update(_ item: PageItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
        onItemsChanged?(items)
    }

    private func remove(_ item: PageItem) {
        items.removeAll { $0.id == item.id }
        if item.kind == "image" { MediaFiles.delete(image: item.file) }
        reloadItems(items)
        onItemsChanged?(items)
    }

    private func duplicate(_ item: PageItem) {
        var c = item
        c.id = UUID()
        c.x += 30; c.y += 30
        if item.kind == "image",
           let img = UIImage(contentsOfFile: MediaFiles.imageURL(item.file).path),
           let name = MediaFiles.saveImage(img) {
            c.file = name
        }
        items.append(c)
        reloadItems(items)
        onItemsChanged?(items)
    }

    private func bringFront(_ item: PageItem) {
        items.removeAll { $0.id == item.id }
        items.append(item)
        reloadItems(items)
        onItemsChanged?(items)
    }
}

/// يرسم الورق والتسطير.
final class PaperView: UIView {
    private var style: PaperStyle = .blank
    private var color: PaperColor = .white
    private var bgFile = ""
    private var bgImage: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(style: PaperStyle, color: PaperColor, backgroundFile: String) {
        guard style != self.style || color != self.color || backgroundFile != bgFile || bgImage == nil && !backgroundFile.isEmpty else { return }
        self.style = style
        self.color = color
        if backgroundFile != bgFile || bgImage == nil {
            bgFile = backgroundFile
            bgImage = backgroundFile.isEmpty ? nil : UIImage(contentsOfFile: MediaFiles.imageURL(backgroundFile).path)
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        PaperRenderer.draw(style: style, color: color, background: bgImage, in: ctx, size: bounds.size)
    }
}

/// صورة أو نص فوق الصفحة، ينسحب ويتكبر في وضع التحديد.
final class ItemView: UIView, UIContextMenuInteractionDelegate {
    private(set) var item: PageItem
    var onMoved: ((PageItem) -> Void)?
    var onDelete: ((PageItem) -> Void)?
    var onEdit: ((PageItem) -> Void)?
    var onDuplicate: ((PageItem) -> Void)?
    var onFront: ((PageItem) -> Void)?

    private let border = CAShapeLayer()
    private var label: UILabel?
    private var startFrame: CGRect = .zero
    private var startFont: Double = 28

    init(item: PageItem) {
        self.item = item
        super.init(frame: item.frame)
        clipsToBounds = false
        if item.kind == "image" {
            let iv = UIImageView(image: UIImage(contentsOfFile: MediaFiles.imageURL(item.file).path))
            iv.contentMode = .scaleToFill
            iv.frame = bounds
            iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(iv)
        } else {
            let l = UILabel(frame: bounds)
            l.numberOfLines = 0
            l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(l)
            label = l
            styleLabel()
        }
        border.strokeColor = UIColor.systemBlue.cgColor
        border.fillColor = UIColor.clear.cgColor
        border.lineWidth = 2
        border.lineDashPattern = [6, 4]
        border.isHidden = true
        layer.addSublayer(border)

        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        let dbl = UITapGestureRecognizer(target: self, action: #selector(doubleTap))
        dbl.numberOfTapsRequired = 2
        addGestureRecognizer(dbl)
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    private func styleLabel() {
        guard let label else { return }
        label.text = item.text
        label.font = .systemFont(ofSize: item.fontSize)
        label.textColor = UIColor(hex: item.colorHex)
        label.textAlignment = item.text.isRTL ? .right : .left
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        border.path = UIBezierPath(rect: bounds.insetBy(dx: -3, dy: -3)).cgPath
    }

    func setSelectable(_ on: Bool) { border.isHidden = !on }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        guard let sv = superview else { return }
        let t = g.translation(in: sv)
        center = CGPoint(x: center.x + t.x, y: center.y + t.y)
        g.setTranslation(.zero, in: sv)
        if g.state == .ended || g.state == .cancelled { commit() }
    }

    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            startFrame = frame
            startFont = item.fontSize
        case .changed:
            let s = max(0.15, g.scale)
            let w = max(30, startFrame.width * s), h = max(20, startFrame.height * s)
            frame = CGRect(x: startFrame.midX - w / 2, y: startFrame.midY - h / 2, width: w, height: h)
            if label != nil {
                item.fontSize = min(max(startFont * Double(s), 8), 200)
                styleLabel()
            }
        default:
            commit()
        }
    }

    @objc private func doubleTap() {
        if item.kind == "text" { onEdit?(item) }
    }

    private func commit() {
        item.frame = frame
        onMoved?(item)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions: [UIMenuElement] = []
            if self.item.kind == "text" {
                actions.append(UIAction(title: tr("تعديل النص", "Edit text"), image: UIImage(systemName: "pencil")) { _ in
                    self.onEdit?(self.item)
                })
            }
            actions.append(UIAction(title: tr("تكرار", "Duplicate"), image: UIImage(systemName: "plus.square.on.square")) { _ in
                self.onDuplicate?(self.item)
            })
            actions.append(UIAction(title: tr("للأمام", "Bring to front"), image: UIImage(systemName: "square.3.layers.3d.top.filled")) { _ in
                self.onFront?(self.item)
            })
            actions.append(UIAction(title: tr("حذف", "Delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self.onDelete?(self.item)
            })
            return UIMenu(children: actions)
        }
    }
}
