// Overview: Direct saved media: local store of saved stickers and GIFs, plus the library and catalog screens.
import UIKit
import Security
import QuartzCore
import CoreText
import ImageIO
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import SystemConfiguration

final class MagnistraDirectProfileButton: UIButton {

    override func draw(_ rect: CGRect) {
        guard let symbol = UIImage(named: "MGDirectProfileInfo") else { return }
        let side: CGFloat = min(rect.width, rect.height) - 8.0
        symbol.draw(in: CGRect(x: (rect.width - side) / 2.0,
                               y: (rect.height - side) / 2.0,
                               width: side, height: side))
    }
}

enum MagnistraDirectSavedMediaStore {
    private static let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    static func directory(_ category: String) -> String {
        let roots = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let base = roots.first ?? NSTemporaryDirectory()
        let part = category == "Matrix" ? "Matrix" : "Web"
        let root = (base as NSString).appendingPathComponent("MagnistraSavedStickers")
        let path = (root as NSString).appendingPathComponent(part)
        try? FileManager.default.createDirectory(atPath: path,
            withIntermediateDirectories: true, attributes: nil)
        return path
    }

    static func items(_ category: String) -> [String] {
        let root = directory(category)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        let filtered = names.filter {
            $0.hasSuffix(".webp") || $0.hasSuffix(".gif") || $0.hasSuffix(".png")
        }
        return filtered.sorted().reversed().map { (root as NSString).appendingPathComponent($0) }
    }

    static func saveLocalMatrix(path: String, completion: @escaping (Bool) -> Void) {
        queue.addOperation {
            var didSave = false
            if let data = NSData(contentsOfFile: path),
               data.length >= 16 && data.length <= 8 * 1024 * 1024 {
                let bytes = [UInt8](Data(referencing: data).prefix(12))
                let ext: String
                if Array(bytes[0..<4]) == [82,73,70,70] &&
                   Array(bytes[8..<12]) == [87,69,66,80] { ext = "webp" }
                else if Array(bytes[0..<3]) == [71,73,70] { ext = "gif" }
                else if Array(bytes[0..<4]) == [137,80,78,71] { ext = "png" }
                else { ext = "" }
                if !ext.isEmpty {
                    let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                    let folder = directory("Matrix")
                    let target = (folder as NSString).appendingPathComponent(
                        "saved-\(timestamp)-\(arc4random()).\(ext)")
                    didSave = data.write(toFile: target, atomically: true)
                }
            }
            OperationQueue.main.addOperation { completion(didSave) }
        }
    }

    static func save(remote: String, key: String, category: String,
                     completion: @escaping (Bool) -> Void) {
        queue.addOperation {
            let path = MagnistraDirectMediaDiskCache.imagePath(remote: remote, key: "direct-preview:" + key)
            var didSave = false
            if let source = path, let data = NSData(contentsOfFile: source),
               data.length >= 16 && data.length <= 8 * 1024 * 1024 {
                let bytes = [UInt8](Data(referencing: data).prefix(12))
                let ext: String
                if Array(bytes[0..<4]) == [82,73,70,70] &&
                   Array(bytes[8..<12]) == [87,69,66,80] { ext = "webp" }
                else if Array(bytes[0..<3]) == [71,73,70] { ext = "gif" }
                else if Array(bytes[0..<4]) == [137,80,78,71] { ext = "png" }
                else { ext = "" }
                if !ext.isEmpty {
                    let folder = directory(category)
                    let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                    let filename = "saved-\(timestamp)-\(arc4random()).\(ext)"
                    let destination = (folder as NSString).appendingPathComponent(filename)
                    didSave = data.write(toFile: destination, atomically: true)
                }
            }
            OperationQueue.main.addOperation { completion(didSave) }
        }
    }
}

final class MagnistraIGCatalogVC: UIViewController, UIScrollViewDelegate, UITextFieldDelegate {
    private let types = UISegmentedControl(items: ["GIF", "Sticker"])
    private let field = UITextField()
    private let searchButton = UIButton(type: .custom)
    private let scroll = UIScrollView()
    private let status = UILabel()
    private var items: [MagnistraIGCatalogEntry] = []
    private var tiles: [Int: UIImageView] = [:]
    private var attempts: [Int: Int] = [:]
    private var videoPlayers: [Int: AVPlayer] = [:]
    private var videoLayers: [Int: AVPlayerLayer] = [:]
    private var videoFiles: [Int: String] = [:]
    private var loading = false
    private var generation = 0
    private var activeSend = false
    private let queryQueue: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 1; return q
    }()
    private let posterQueue: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 2; return q
    }()
    private let posters: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>(); c.totalCostLimit = 10*1024*1024; return c
    }()
    var onChoose: ((MagnistraIGCatalogEntry, @escaping (Bool, String?) -> Void) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sticker"
        view.backgroundColor = UIColor.white
        view.isOpaque = true
        scroll.backgroundColor = UIColor.white
        types.selectedSegmentIndex = 1
        types.addTarget(self, action: #selector(typeChanged), for: .valueChanged)
        view.addSubview(types)
        field.borderStyle = .roundedRect
        field.placeholder = "Search Stickers"
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.delegate = self
        view.addSubview(field)
        searchButton.setTitle("Search", for: .normal)

        searchButton.backgroundColor = MagnistraPostCell.magnistraBlue
        searchButton.setTitleColor(UIColor.white, for: .normal)
        searchButton.setTitleColor(UIColor(white: 0.87, alpha: 1), for: .highlighted)
        searchButton.layer.cornerRadius = 6.0
        searchButton.clipsToBounds = true
        searchButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 15.0)
        searchButton.addTarget(self, action: #selector(searchPressed), for: .touchUpInside)
        view.addSubview(searchButton)
        scroll.delegate = self
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = true
        view.addSubview(scroll)
        status.textAlignment = .center
        status.font = UIFont.boldSystemFont(ofSize: 12)
        status.numberOfLines = 2
        status.backgroundColor = UIColor(white: 0.20, alpha: 1.0)
        status.textColor = UIColor.white
        view.addSubview(status)
        fetchResults()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = max(1.0, view.bounds.width)
        let h = max(1.0, view.bounds.height)
        types.frame = CGRect(x: 10,y: 8,width: w-20,height: 30)
        field.frame = CGRect(x: 10,y: 45,width: max(1,w-95),height: 32)
        searchButton.frame = CGRect(x: w-82,y: 45,width: 72,height: 32)
        scroll.frame = CGRect(x: 0,y: 83,width: w,height: max(1,h-118))
        status.frame = CGRect(x: 0, y: h-34, width: w, height: 34)
        relayoutTiles()
    }
    private var tileSide: CGFloat {
        return max(50.0, floor((max(1.0,scroll.bounds.width)-32.0)/3.0))
    }
    private func frameFor(_ i: Int) -> CGRect {
        let size = tileSide
        return CGRect(x: 8 + CGFloat(i%3)*(size+8),
            y: 8 + CGFloat(i/3)*(size+8), width: size, height: size)
    }
    private func clearTiles() {
        for v in tiles.values { v.removeFromSuperview() }
        tiles.removeAll()
        for index in Array(videoFiles.keys) { stopVideo(index) }
        attempts.removeAll()
    }
    private func relayoutTiles() {
        let rows = (items.count+2)/3
        scroll.contentSize = CGSize(width: scroll.bounds.width,
            height: max(scroll.bounds.height+1,CGFloat(rows)*(tileSide+8)+8))
        for (i,layer) in videoLayers {
            if let tile = tiles[i] { layer.frame = tile.bounds }
        }
        updateVisible()
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if scrollView === scroll { field.resignFirstResponder() }
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateVisible() }
    private func updateVisible() {
        let top = max(0,scroll.contentOffset.y - tileSide)
        let bottom = scroll.contentOffset.y + scroll.bounds.height + tileSide
        for (i,v) in Array(tiles) where v.frame.maxY < top || v.frame.minY > bottom {
            stopVideo(i)
            attempts.removeValue(forKey: i)
            v.stopAnimating()
            v.image = nil
            v.removeFromSuperview(); tiles.removeValue(forKey:i)
        }
        if items.isEmpty { return }
        for i in 0..<items.count {
            let rect = frameFor(i)
            if rect.maxY < top || rect.minY > bottom || tiles[i] != nil { continue }
            let iv = UIImageView(frame: rect)
            iv.contentMode = .scaleAspectFit
            iv.backgroundColor = UIColor(white: 0.88,alpha: 1)
            iv.clipsToBounds = true

            iv.tag = i+1
            iv.isUserInteractionEnabled = true
            iv.addGestureRecognizer(UITapGestureRecognizer(target: self,
                action: #selector(picked(_:))))
            tiles[i] = iv
            scroll.addSubview(iv)
            loadPoster(i, view: iv)
        }
    }
    private func stopVideo(_ i: Int) {
        if let player = videoPlayers[i] {
            NotificationCenter.default.removeObserver(
                self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                object: player.currentItem)
            player.pause()
        }
        videoLayers[i]?.removeFromSuperlayer()
        videoPlayers.removeValue(forKey: i)
        videoLayers.removeValue(forKey: i)
        if let file = videoFiles.removeValue(forKey: i) {
            try? FileManager.default.removeItem(atPath: file)
        }
    }

    private func magnistraCatalogFallbackURL(_ id: String) -> String? {
        if id.isEmpty || id.count > 48 { return nil }
        let okay = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        if id.unicodeScalars.contains(where: { !okay.contains($0) }) { return nil }
        return "https://media.giphy.com/media/" + id + "/200.gif"
    }

    private func magnistraCatalogStill(_ bytes: Data) -> UIImage? {

        if bytes.count < 64 { return nil }
        let prefix = Array(bytes.prefix(8))
        let gif = prefix.count >= 6 &&
            (Array(prefix[0..<6]) == [71,73,70,56,55,97] ||
             Array(prefix[0..<6]) == [71,73,70,56,57,97])
        let jpeg = prefix.count >= 3 && Array(prefix[0..<3]) == [255,216,255]
        let png = prefix.count >= 8 &&
            prefix == [137,80,78,71,13,10,26,10]
        guard gif || jpeg || png else { return nil }
        return UIImage(data: bytes)
    }

    private func magnistraCatalogAnimatedGIF(_ bytes: Data) -> UIImage? {
        guard bytes.count > 10 else { return nil }
        let hdr = [UInt8](bytes.prefix(6))
        guard hdr == [71,73,70,56,55,97] || hdr == [71,73,70,56,57,97],
              let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        let step = max(1, (count + 19) / 20)

        let options: [String: Any] = [
            String(describing: kCGImageSourceCreateThumbnailFromImageAlways): true,
            String(describing: kCGImageSourceCreateThumbnailWithTransform): true,
            String(describing: kCGImageSourceThumbnailMaxPixelSize): 160
        ]
        var frames: [UIImage] = []
        var duration: Double = 0
        for index in stride(from: 0, to: count, by: step) {
            if frames.count == 20 { break }
            guard let cg = CGImageSourceCreateThumbnailAtIndex(
                source, index, options as CFDictionary) else { continue }
            frames.append(UIImage(cgImage: cg))
            var delay = 0.10
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [String: Any],
               let gif = properties[String(describing: kCGImagePropertyGIFDictionary)]
                as? [String: Any] {
                if let value = gif[String(describing: kCGImagePropertyGIFUnclampedDelayTime)]
                    as? NSNumber, value.doubleValue > 0.015 {
                    delay = value.doubleValue
                } else if let value = gif[String(describing: kCGImagePropertyGIFDelayTime)]
                    as? NSNumber, value.doubleValue > 0.015 {
                    delay = value.doubleValue
                }
            }
            duration += max(0.04, min(0.6, delay)) * Double(step)
        }
        if frames.isEmpty { return nil }
        if frames.count == 1 { return frames[0] }
        return UIImage.animatedImage(with: frames, duration: max(0.1, duration))
    }

    @objc private func magnistraCatalogReplay(_ note: Notification) {
        guard let item = note.object as? AVPlayerItem else { return }
        for player in videoPlayers.values where player.currentItem === item {
            player.seek(to: CMTimeMake(value: 0, timescale: 1))
            player.play()
            break
        }
    }

    private func loadPoster(_ i: Int, view: UIImageView) {
        let item = items[i]
        let key = (item.kind + ":" + item.id) as NSString
        if let cached = posters.object(forKey: key) {
            view.image = cached
            view.backgroundColor = UIColor.clear
            if cached.images != nil { view.startAnimating() }
            return
        }
        guard (attempts[i] ?? 0) < 2 else { return }
        attempts[i] = (attempts[i] ?? 0) + 1
        let token = generation
        posterQueue.addOperation { [weak self, weak view] in
            guard let owner = self else { return }
            var animation: UIImage? = nil
            var localVideo: String? = nil

            if let raw = item.previewURL,
               let bytes = MagnistraHomeService.magnistraIGCatalogPreview(raw) {
                let hdr = [UInt8](bytes.prefix(8))
                if hdr.count == 8 && Array(hdr[4..<8]) == [102,116,121,112] {
                    let path = NSTemporaryDirectory() + "magnistra-cat-" + UUID().uuidString + ".mp4"
                    if (try? bytes.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil {
                        let asset = AVURLAsset(url: URL(fileURLWithPath: path), options: nil)
                        if asset.isPlayable { localVideo = path }
                        else { try? FileManager.default.removeItem(atPath: path) }
                    }
                } else {
                    animation = owner.magnistraCatalogAnimatedGIF(bytes)

                    if animation == nil { animation = owner.magnistraCatalogStill(bytes) }
                }
            }

            if animation == nil && localVideo == nil,
               let fallback = owner.magnistraCatalogFallbackURL(item.id),
               let bytes = MagnistraHomeService.magnistraIGCatalogPreview(fallback) {
                animation = owner.magnistraCatalogAnimatedGIF(bytes)
                if animation == nil { animation = owner.magnistraCatalogStill(bytes) }
            }
            OperationQueue.main.addOperation { [weak self, weak view] in
                guard let self = self, let tile = view,
                      self.generation == token, self.tiles[i] === tile else {
                    if let video = localVideo { try? FileManager.default.removeItem(atPath: video) }
                    return
                }
                if let video = localVideo {
                    self.stopVideo(i)
                    tile.image = nil
                    let player = AVPlayer(url: URL(fileURLWithPath: video))
                    let layer = AVPlayerLayer(player: player)
                    layer.frame = tile.bounds
                    layer.videoGravity = .resizeAspect
                    layer.backgroundColor = UIColor.clear.cgColor
                    tile.layer.addSublayer(layer)
                    self.videoPlayers[i] = player
                    self.videoLayers[i] = layer
                    self.videoFiles[i] = video
                    NotificationCenter.default.addObserver(
                        self, selector: #selector(self.magnistraCatalogReplay(_:)),
                        name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                        object: player.currentItem)
                    player.play()

                    tile.backgroundColor = UIColor.clear
                } else if let animated = animation {
                    self.stopVideo(i)
                    tile.image = animated
                    tile.backgroundColor = UIColor.clear
                    if animated.images != nil { tile.startAnimating() }
                    let copies = max(1, animated.images?.count ?? 1)
                    self.posters.setObject(animated, forKey: key,
                        cost: Int(max(1, animated.size.width*animated.size.height*4)) * copies)
                }

            }
        }
    }

    @objc private func typeChanged() {
        field.placeholder = types.selectedSegmentIndex == 0
            ? "Search GIFs" : "Search Stickers"
        fetchResults()
    }
    @objc private func searchPressed() { fetchResults() }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        fetchResults(); return true
    }
    private func fetchResults() {
        field.resignFirstResponder()
        loading = true
        generation += 1
        let token = generation
        items.removeAll()
        clearTiles()
        status.text = "Loading..."
        let kind = types.selectedSegmentIndex == 0 ? "gif" : "sticker"
        let search = field.text ?? ""
        queryQueue.addOperation { [weak self] in
            let result = Result { try MagnistraHomeService.magnistraIGCatalog(kind: kind, search: search) }
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self, self.generation == token else { return }
                self.loading = false
                switch result {
                case .success(let items):
                    self.items = items
                    self.status.text = items.isEmpty ? "No results." : "Tap to send"
                    self.scroll.contentOffset = CGPoint.zero
                    self.relayoutTiles()
                case .failure(let error):
                    self.status.text = error.localizedDescription
                }
            }
        }
    }
    @objc private func picked(_ sender: UITapGestureRecognizer) {
        guard !activeSend, sender.state == .ended,
              let tile = sender.view else { return }
        let index = tile.tag-1
        guard index >= 0 && index < items.count else { return }
        activeSend = true
        status.text = "Sending…"
        onChoose?(items[index], { [weak self] success, message in
            OperationQueue.main.addOperation { [weak self] in
                guard let owner = self else { return }
                owner.activeSend = false
                if success { owner.navigationController?.popViewController(animated: true) }
                else { owner.status.text = message ?? "Instagram rejected this sticker." }
            }
        })
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
        for player in videoPlayers.values { player.pause() }
        for layer in videoLayers.values { layer.removeFromSuperlayer() }
        for file in videoFiles.values {
            try? FileManager.default.removeItem(atPath: file)
        }
    }
}

final class MagnistraDirectSavedMediaLibraryVC: UIViewController, UIScrollViewDelegate {
    private let grid = UIScrollView()
    private let emptyLabel = UILabel()
    private let sendHint = UILabel()
    private var sendingSelection = false
    private var category = "Web"
    private var paths: [String] = []
    private var visiblePreviews: [Int: UIImageView] = [:]
    private var visibleDeletes: [Int: UIButton] = [:]
    var onSelect: ((String, @escaping (Bool) -> Void) -> Void)?
    private var editMode = false
    private var generation = 0
    private let loader: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private var cellSide: CGFloat = 90.0
    private let margin: CGFloat = 9.0

    init(category: String) {
        self.category = category == "Matrix" ? "Matrix" : "Web"
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sticker"
        view.backgroundColor = UIColor.white
        grid.backgroundColor = UIColor.white
        grid.delegate = self
        grid.alwaysBounceVertical = true
        grid.showsVerticalScrollIndicator = true
        view.addSubview(grid)
        emptyLabel.textAlignment = .center
        emptyLabel.font = UIFont.systemFont(ofSize: 13)
        emptyLabel.textColor = UIColor.gray
        view.addSubview(emptyLabel)
        sendHint.backgroundColor = UIColor(white: 0.20, alpha: 1.0)
        sendHint.textColor = UIColor.white
        sendHint.textAlignment = .center
        sendHint.font = UIFont.boldSystemFont(ofSize: 12.0)
        sendHint.text = "Tap to send"
        sendHint.isUserInteractionEnabled = false
        view.addSubview(sendHint)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Edit", style: .plain, target: self, action: #selector(toggleEdit))
        reloadItems()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        grid.frame = CGRect(x: 0, y: 0, width: w,
                            height: max(1, view.bounds.height))
        emptyLabel.frame = CGRect(x: 10, y: 18, width: max(1, w-20), height: 40)
        if category == "Matrix" {
            var r = grid.frame
            r.size.height = max(1.0, r.height - 34.0)
            grid.frame = r
        }
        sendHint.frame = CGRect(x: 0, y: max(0, view.bounds.height - 34.0),
                                width: w, height: 34.0)
        sendHint.isHidden = category != "Matrix"
        updateLayout()
    }
    @objc private func toggleEdit() {
        editMode = !editMode
        navigationItem.rightBarButtonItem?.title = editMode ? "Done" : "Edit"
        updateVisible()
    }
    private func reloadItems() {
        generation += 1
        for iv in visiblePreviews.values { iv.removeFromSuperview() }
        for b in visibleDeletes.values { b.removeFromSuperview() }
        visiblePreviews.removeAll()
        visibleDeletes.removeAll()
        paths = MagnistraDirectSavedMediaStore.items(category)
        sendHint.text = paths.isEmpty ? "No saved stickers" : "Tap to send"
        sendHint.isHidden = category != "Matrix"
        view.setNeedsLayout()
        grid.contentOffset = CGPoint.zero
        emptyLabel.text = paths.isEmpty ? (category == "Matrix" ? ":(" : "No saved stickers in " + category) : ""
        emptyLabel.isHidden = !paths.isEmpty
        updateLayout()
    }
    private func updateLayout() {
        let w = max(1, grid.bounds.width)
        cellSide = max(48, floor((w - 4*margin)/3))
        let rows = (paths.count + 2)/3
        grid.contentSize = CGSize(width: w,
            height: max(grid.bounds.height+1, CGFloat(rows)*(cellSide+margin)+margin))
        updateVisible()
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateVisible() }
    private func cellFrame(_ index: Int) -> CGRect {
        let row = index / 3; let col = index % 3
        return CGRect(x: margin + CGFloat(col)*(cellSide+margin),
            y: margin + CGFloat(row)*(cellSide+margin),
            width: cellSide, height: cellSide)
    }
    private func updateVisible() {
        let pitch = max(1, cellSide + margin)
        let firstRow = max(0, Int(max(0, grid.contentOffset.y)/pitch)-1)
        let lastRow = max(firstRow, Int(max(0, grid.contentOffset.y + grid.bounds.height)/pitch)+2)
        let low = min(paths.count, firstRow*3)
        let high = min(paths.count, (lastRow+1)*3)
        for index in Array(visiblePreviews.keys) where index < low || index >= high {
            visiblePreviews[index]?.removeFromSuperview()
            visiblePreviews.removeValue(forKey: index)
        }
        for index in Array(visibleDeletes.keys) where index < low || index >= high || !editMode {
            visibleDeletes[index]?.removeFromSuperview()
            visibleDeletes.removeValue(forKey: index)
        }
        if low >= high { return }
        for i in low..<high {
            if visiblePreviews[i] == nil {
                let iv = UIImageView(frame: cellFrame(i))
                iv.contentMode = .scaleAspectFit
                iv.backgroundColor = UIColor(white: 0.93, alpha: 1.0)
                iv.tag = i + 1
                iv.isUserInteractionEnabled = true
                let tap = UITapGestureRecognizer(target: self,
                    action: #selector(stickerSelected(_:)))
                iv.addGestureRecognizer(tap)
                grid.addSubview(iv)
                visiblePreviews[i] = iv
                let source = paths[i]
                let token = generation
                loader.addOperation { [weak self, weak iv] in
                    let img = MagnistraDirectMessageCell.decodedPreviewImage(atPath: source)
                    OperationQueue.main.addOperation { [weak self, weak iv] in
                        guard let owner = self, token == owner.generation,
                              i < owner.paths.count, owner.paths[i] == source,
                              owner.visiblePreviews[i] === iv else { return }
                        iv?.image = img
                        iv?.backgroundColor = UIColor.clear
                    }
                }
            } else {
                visiblePreviews[i]?.frame = cellFrame(i)
            }
            if editMode {
                if visibleDeletes[i] == nil {
                    let button = UIButton(type: .custom)
                    button.tag = i + 1

                    button.backgroundColor = UIColor(red: 0.80, green: 0.14,
                                                     blue: 0.14, alpha: 0.95)
                    button.layer.cornerRadius = 12
                    let crossPath = UIBezierPath()
                    crossPath.move(to: CGPoint(x: 8, y: 8))
                    crossPath.addLine(to: CGPoint(x: 16, y: 16))
                    crossPath.move(to: CGPoint(x: 16, y: 8))
                    crossPath.addLine(to: CGPoint(x: 8, y: 16))
                    let cross = CAShapeLayer()
                    cross.path = crossPath.cgPath
                    cross.fillColor = UIColor.clear.cgColor
                    cross.strokeColor = UIColor.white.cgColor
                    cross.lineWidth = 2.5
                    cross.lineCap = .round
                    button.layer.addSublayer(cross)
                    button.addTarget(self, action: #selector(deleteSticker(_:)), for: .touchUpInside)
                    grid.addSubview(button)
                    visibleDeletes[i] = button
                }
                let r = cellFrame(i)
                visibleDeletes[i]?.frame = CGRect(x: r.maxX-22, y: r.minY, width: 24, height: 24)
                if let button = visibleDeletes[i] { grid.bringSubviewToFront(button) }
            }
        }
    }
    @objc private func deleteSticker(_ sender: UIButton) {
        let i = sender.tag-1
        guard i >= 0 && i < paths.count else { return }
        let root = MagnistraDirectSavedMediaStore.directory(category)
        let file = paths[i]

        guard file.hasPrefix(root + "/") else { return }
        do {
            try FileManager.default.removeItem(atPath: file)
            reloadItems()
        } catch {
            let alert = UIAlertView(title: "Sticker", message: "Could not delete sticker.",
                delegate: nil, cancelButtonTitle: "OK")
            alert.show()
        }
    }
    @objc private func stickerSelected(_ gesture: UITapGestureRecognizer) {
        guard !editMode, !sendingSelection, gesture.state == .ended,
              let tile = gesture.view else { return }
        let index = tile.tag - 1
        guard index >= 0 && index < paths.count,
              let select = onSelect else { return }
        sendingSelection = true
        sendHint.text = "Sending…"
        select(paths[index]) { [weak self] success in
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self else { return }
                self.sendingSelection = false
                if success {
                    self.navigationController?.popViewController(animated: true)
                } else {
                    self.sendHint.text = "Tap to send"
                }
            }
        }
    }
}

