// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Matrix media cache: thumbnails, WebP, and animated images.
import UIKit
import ImageIO

@_silgen_name("WebPGetInfo")
private func magnistraWebPGetInfo(_ data: UnsafePointer<UInt8>?, _ dataSize: Int,
                                   _ width: UnsafeMutablePointer<Int32>?,
                                   _ height: UnsafeMutablePointer<Int32>?) -> Int32

@_silgen_name("WebPDecodeRGBAInto")
private func magnistraWebPDecodeRGBAInto(_ data: UnsafePointer<UInt8>?, _ dataSize: Int,
                                          _ output: UnsafeMutablePointer<UInt8>?,
                                          _ outputSize: Int,
                                          _ outputStride: Int32) -> UnsafeMutablePointer<UInt8>?

private struct MagnistraWebPData {
    var bytes: UnsafePointer<UInt8>?
    var size: Int
}
private struct MagnistraWebPAnimInfo {
    var canvasWidth: UInt32
    var canvasHeight: UInt32
    var loopCount: UInt32
    var backgroundColor: UInt32
    var frameCount: UInt32
}
@_silgen_name("WebPAnimDecoderNewInternal")
private func magnistraWebPAnimDecoderNewInternal(
    _ data: UnsafePointer<MagnistraWebPData>?,
    _ options: UnsafeRawPointer?,
    _ abiVersion: Int32
) -> UnsafeMutableRawPointer?
@_silgen_name("WebPAnimDecoderGetInfo")
private func magnistraWebPAnimDecoderGetInfo(
    _ decoder: UnsafeMutableRawPointer?,
    _ info: UnsafeMutablePointer<MagnistraWebPAnimInfo>?
) -> Int32
@_silgen_name("WebPAnimDecoderHasMoreFrames")
private func magnistraWebPAnimDecoderHasMoreFrames(_ decoder: UnsafeMutableRawPointer?) -> Int32
@_silgen_name("WebPAnimDecoderGetNext")
private func magnistraWebPAnimDecoderGetNext(
    _ decoder: UnsafeMutableRawPointer?,
    _ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ timestamp: UnsafeMutablePointer<Int32>?
) -> Int32
@_silgen_name("WebPAnimDecoderDelete")
private func magnistraWebPAnimDecoderDelete(_ decoder: UnsafeMutableRawPointer?)

private let magnistraWebPDemuxABIVersion: Int32 = 263

@_silgen_name("magnistra_video_to_animated_webp")
private func magnistraVideoToAnimatedWebP(
    _ inputPath: UnsafePointer<CChar>?,
    _ outputPath: UnsafePointer<CChar>?,
    _ maxSide: Int32,
    _ fps: Int32,
    _ maxFrames: Int32
) -> Int32

@_silgen_name("magnistra_lottie_data_to_animated_webp")
private func magnistraLottieDataToAnimatedWebP(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ outputPath: UnsafePointer<CChar>?,
    _ maxSide: Int32,
    _ maxFrames: Int32
) -> Int32

@_silgen_name("magnistra_webp_vertical_flip_copy")
private func magnistraWebPVerticalFlipCopy(
    _ inputPath: UnsafePointer<CChar>?,
    _ outputPath: UnsafePointer<CChar>?
) -> Int32

@_silgen_name("magnistra_animated_webp_to_vp9_webm")
private func magnistraAnimatedWebPToVP9WebM(
    _ inputPath: UnsafePointer<CChar>?,
    _ outputPath: UnsafePointer<CChar>?,
    _ maxSide: Int32,
    _ maxDurationMs: Int32,
    _ maxFPS: Int32,
    _ maxBytes: Int32
) -> Int32

@_silgen_name("magnistra_lottie_create")
private func magnistraLottieCreate(_ json: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?

@_silgen_name("magnistra_lottie_create_data")
private func magnistraLottieCreateData(_ data: UnsafePointer<UInt8>?, _ length: Int) -> UnsafeMutableRawPointer?
@_silgen_name("magnistra_lottie_destroy")
private func magnistraLottieDestroy(_ animation: UnsafeMutableRawPointer?)
@_silgen_name("magnistra_lottie_total_frames")
private func magnistraLottieTotalFrames(_ animation: UnsafeMutableRawPointer?) -> Int
@_silgen_name("magnistra_lottie_duration")
private func magnistraLottieDuration(_ animation: UnsafeMutableRawPointer?) -> Double
@_silgen_name("magnistra_lottie_size")
private func magnistraLottieSize(_ animation: UnsafeMutableRawPointer?,
                                  _ width: UnsafeMutablePointer<Int>?,
                                  _ height: UnsafeMutablePointer<Int>?)
@_silgen_name("magnistra_lottie_render")
private func magnistraLottieRender(_ animation: UnsafeMutableRawPointer?,
                                    _ frame: Int,
                                    _ buffer: UnsafeMutablePointer<UInt32>?,
                                    _ width: Int, _ height: Int, _ stride: Int)

class MediaCache {
    static let shared = MediaCache()

    private static var recentLog: [String] = []
    private static let recentLogLimit = 24
    static var lastDiagnostic: String? {
        return recentLog.isEmpty ? nil : recentLog.joined(separator: "\n\n")
    }
    static func record(_ line: String) {
        recentLog.insert(line, at: 0)
        if recentLog.count > recentLogLimit { recentLog.removeLast(recentLog.count - recentLogLimit) }
    }

    private static func dims(_ image: UIImage) -> String {
        return "\(Int(image.size.width))x\(Int(image.size.height))"
    }

    private let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 80
        c.totalCostLimit = 20 * 1024 * 1024
        return c
    }()

    private var inFlight: [String: [(UIImage?) -> Void]] = [:]

    private let dir: String

    private let ioQueue = DispatchQueue(label: "com.magnistra.mediacache")

    private let videoWebPQueue = DispatchQueue(label: "com.magnistra.video-webp")
    private var videoWebPWaiters: [String: [(UIImage?, String?) -> Void]] = [:]

    private var videoWebPImageCache: [String: UIImage] = [:]
    private var videoWebPImageOrder: [String] = []
    private let videoWebPImageCacheLimit = 2

    private let videoBackedAnimatedInfoLock = NSLock()
    private var videoBackedAnimatedFilenameByMXC: [String: String] = [:]
    private var videoBackedAnimatedMimeByMXC: [String: String] = [:]

    // MARK: - Video-backed animated media

    func registerVideoBackedAnimated(
        mxc: String,
        filename: String,
        mimeType: String
    ) {
        videoBackedAnimatedInfoLock.lock()
        videoBackedAnimatedFilenameByMXC[mxc] = filename
        videoBackedAnimatedMimeByMXC[mxc] = mimeType
        videoBackedAnimatedInfoLock.unlock()
    }

    func videoBackedAnimatedInfo(
        for mxc: String
    ) -> (filename: String, mimeType: String)? {
        videoBackedAnimatedInfoLock.lock()
        let filename = videoBackedAnimatedFilenameByMXC[mxc]
        let mimeType = videoBackedAnimatedMimeByMXC[mxc]
        videoBackedAnimatedInfoLock.unlock()

        guard let filename = filename, let mimeType = mimeType else {
            return nil
        }
        return (filename: filename, mimeType: mimeType)
    }

    private let trimQueue = DispatchQueue(label: "com.magnistra.mediacache.trim")

    private let maxDiskBytes: UInt64 = 100 * 1024 * 1024

    private var trimScheduled = false

    private let filesDir: String

    private var fileWaiters: [String: [(progress: ((Float) -> Void)?, completion: (String?) -> Void)]] = [:]

    private var presentFileNames = Set<String>()

    private init() {
        let caches = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        dir = (caches as NSString).appendingPathComponent("magnistra-media")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        filesDir = (documents as NSString).appendingPathComponent("magnistra-files")
        try? FileManager.default.createDirectory(atPath: filesDir, withIntermediateDirectories: true, attributes: nil)

        presentFileNames = Set(((try? FileManager.default.contentsOfDirectory(atPath: filesDir)) ?? [])
            .filter { !$0.hasSuffix(".part") })

        trimQueue.async { [weak self] in self?.trimDiskCache() }
    }

    // MARK: - Thumbnails

    func loadThumbnail(mxc: String, width: Int, height: Int, completion: @escaping (UIImage?) -> Void) {
        guard let (server, mediaId) = parseMxc(mxc) else {
            MediaCache.record("bad mxc (thumbnail)")
            completion(nil)
            return
        }
        let key = cacheKey(server: server, mediaId: mediaId, width: width, height: height)
        if MatrixE2EEManager.encryptedMediaRecord(for: mxc) != nil {
            loadEncryptedImage(mxc: mxc, key: key, timeout: 60, animated: false, completion: completion)
            return
        }
        let path = "/_matrix/client/v1/media/thumbnail/\(server)/\(mediaId)?width=\(width)&height=\(height)&method=scale"
        load(key: key, urlPath: path, timeout: 30, completion: completion)
    }

    func loadCachedThumbnail(mxc: String, width: Int, height: Int,
                             completion: @escaping (UIImage?) -> Void) {
        guard let (server, mediaId) = parseMxc(mxc) else {
            completion(nil)
            return
        }
        let key = cacheKey(server: server, mediaId: mediaId, width: width, height: height)
        if let cached = memory.object(forKey: key as NSString) {
            completion(cached)
            return
        }
        let diskPath = (dir as NSString).appendingPathComponent(key)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let data = FileManager.default.contents(atPath: diskPath)
            let image = data.flatMap { MediaCache.decode($0, animated: false) }
            if let image = image {
                self.memory.setObject(
                    image,
                    forKey: key as NSString,
                    cost: MediaCache.memoryCost(image, dataCount: data?.count ?? 0)
                )
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    private let stickerDisplayWebPQueue = DispatchQueue(
        label: "com.magnistra.sticker-display-webp"
    )
    private var stickerDisplayWebPWaiters: [String: [(UIImage?) -> Void]] = [:]

    private let stickerInfoLock = NSLock()
    private var stickerFilenameByMXC: [String: String] = [:]
    private var stickerMimeByMXC: [String: String] = [:]
    private let stickerFilenameDefaultsPrefix = "MagnistraSticker.filename."
    private let stickerMimeDefaultsPrefix = "MagnistraSticker.mime."

    // MARK: - Sticker metadata and decoding

    func registerStickerInfo(mxc: String, filename: String, mimeType: String) {
        stickerInfoLock.lock()
        stickerFilenameByMXC[mxc] = filename
        stickerMimeByMXC[mxc] = mimeType
        stickerInfoLock.unlock()

        UserDefaults.standard.set(filename, forKey: stickerFilenameDefaultsPrefix + mxc)
        UserDefaults.standard.set(mimeType, forKey: stickerMimeDefaultsPrefix + mxc)
        UserDefaults.standard.synchronize()
    }

    func stickerInfo(for mxc: String) -> (filename: String, mimeType: String)? {
        stickerInfoLock.lock()
        let memoryFilename = stickerFilenameByMXC[mxc]
        let memoryMime = stickerMimeByMXC[mxc]
        stickerInfoLock.unlock()

        if let filename = memoryFilename, let mimeType = memoryMime {
            return (filename: filename, mimeType: mimeType)
        }

        let defaults = UserDefaults.standard
        guard let filename = defaults.string(forKey: stickerFilenameDefaultsPrefix + mxc),
              let mimeType = defaults.string(forKey: stickerMimeDefaultsPrefix + mxc) else {
            return nil
        }

        stickerInfoLock.lock()
        stickerFilenameByMXC[mxc] = filename
        stickerMimeByMXC[mxc] = mimeType
        stickerInfoLock.unlock()
        return (filename: filename, mimeType: mimeType)
    }

    private func stickerExpectedAnimated(filename: String, mimeType: String) -> Bool {
        let lowerMime = mimeType.lowercased()
        let ext = (filename.lowercased() as NSString).pathExtension
        return lowerMime.contains("tgsticker")
            || lowerMime.contains("lottie")
            || lowerMime == "application/json"
            || ext == "tgs"
            || ext == "json"
    }

    private func stickerAnimatedCacheIdentity(
        mxc: String
    ) -> (server: String, mediaId: String, key: String, path: String)? {
        guard let (server, mediaId) = parseMxc(mxc) else { return nil }

        let key = sanitize("\(server)_\(mediaId)_sticker_anim_g4r20")
        let path = (dir as NSString).appendingPathComponent(key)
        return (server: server, mediaId: mediaId, key: key, path: path)
    }

    func loadStickerAnimatedImage(
        mxc: String,
        completion: @escaping (UIImage?) -> Void
    ) {
        let info = stickerInfo(for: mxc)
        let expectedAnimated = info.map {
            stickerExpectedAnimated(filename: $0.filename, mimeType: $0.mimeType)
        } ?? false

        if expectedAnimated {

            loadTelegramStickerDisplayWebP(
                mxc: mxc,
                completion: completion
            )
            return
        }

        loadStickerAnimatedImagePass(
            mxc: mxc,
            expectedAnimated: false,
            allowRepair: true,
            completion: completion
        )
    }

    private func stickerDisplayWebPIdentity(
        mxc: String
    ) -> (server: String, mediaId: String, key: String, path: String)? {
        guard let (server, mediaId) = parseMxc(mxc) else { return nil }
        let key = sanitize("\(server)_\(mediaId)_sticker_display_g4r20r4.webp")
        let path = (dir as NSString).appendingPathComponent(key)
        return (server: server, mediaId: mediaId, key: key, path: path)
    }

    private func ensureStickerOriginalSource(
        mxc: String,
        completion: @escaping (String?) -> Void
    ) {
        guard let identity = stickerAnimatedCacheIdentity(mxc: mxc) else {
            completion(nil)
            return
        }

        if FileManager.default.fileExists(atPath: identity.path) {
            completion(identity.path)
            return
        }

        let legacyKey = sanitize(
            "\(identity.server)_\(identity.mediaId)_full_anim_g4r13"
        )
        let legacyPath = (dir as NSString).appendingPathComponent(legacyKey)
        if let data = FileManager.default.contents(atPath: legacyPath) {
            let kind = MediaCache.mediaKind(data)
            if kind == "json" || kind == "gzip" {
                (data as NSData).write(toFile: identity.path, atomically: true)
                scheduleTrim()
                completion(identity.path)
                return
            }
        }

        loadStickerAnimatedImagePass(
            mxc: mxc,
            expectedAnimated: true,
            allowRepair: false
        ) { [weak self] _ in
            guard self != nil else {
                completion(nil)
                return
            }
            completion(
                FileManager.default.fileExists(atPath: identity.path)
                    ? identity.path
                    : nil
            )
        }
    }

    private func encodeTelegramDisplayWebP(
        sourcePath: String,
        destinationPath: String
    ) -> Int32 {
        guard let data = FileManager.default.contents(atPath: sourcePath) else {
            return -1
        }
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return -2 }
        return bytes.withUnsafeBufferPointer { raw in
            destinationPath.withCString { outputC in
                magnistraLottieDataToAnimatedWebP(
                    raw.baseAddress,
                    bytes.count,
                    outputC,
                    112,
                    48
                )
            }
        }
    }

    private func loadTelegramStickerDisplayWebP(
        mxc: String,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard let display = stickerDisplayWebPIdentity(mxc: mxc) else {
            completion(nil)
            return
        }

        if let cached = memory.object(forKey: display.key as NSString) {
            completion(cached)
            return
        }

        if stickerDisplayWebPWaiters[display.key] != nil {
            stickerDisplayWebPWaiters[display.key]?.append(completion)
            return
        }
        stickerDisplayWebPWaiters[display.key] = [completion]

        func finish(_ image: UIImage?) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let waiters = self.stickerDisplayWebPWaiters.removeValue(
                    forKey: display.key
                ) ?? []
                for waiter in waiters { waiter(image) }
            }
        }

        stickerDisplayWebPQueue.async { [weak self] in
            guard let self = self else { return }

            if let data = FileManager.default.contents(atPath: display.path),
               let image = MediaCache.decode(data, animated: true),
               (image.images?.count ?? 0) > 1 {
                self.memory.setObject(
                    image,
                    forKey: display.key as NSString,
                    cost: MediaCache.memoryCost(image, dataCount: data.count)
                )
                finish(image)
                return
            }

            try? FileManager.default.removeItem(atPath: display.path)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.ensureStickerOriginalSource(mxc: mxc) { [weak self] sourcePath in
                    guard let self = self, let sourcePath = sourcePath else {
                        finish(nil)
                        return
                    }

                    self.stickerDisplayWebPQueue.async {
                        let rc = self.encodeTelegramDisplayWebP(
                            sourcePath: sourcePath,
                            destinationPath: display.path
                        )
                        if rc >= 2,
                           let data = FileManager.default.contents(atPath: display.path),
                           let image = MediaCache.decode(data, animated: true),
                           (image.images?.count ?? 0) > 1 {
                            self.scheduleTrim()
                            self.memory.setObject(
                                image,
                                forKey: display.key as NSString,
                                cost: MediaCache.memoryCost(image, dataCount: data.count)
                            )
                            finish(image)
                            return
                        }

                        try? FileManager.default.removeItem(atPath: display.path)

                        if let raw = FileManager.default.contents(atPath: sourcePath),
                           let fallback = MediaCache.decode(raw, animated: true) {
                            finish(fallback)
                        } else {
                            finish(nil)
                        }
                    }
                }
            }
        }
    }

    private func loadStickerAnimatedImagePass(
        mxc: String,
        expectedAnimated: Bool,
        allowRepair: Bool,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard let identity = stickerAnimatedCacheIdentity(mxc: mxc) else {
            completion(nil)
            return
        }

        if !FileManager.default.fileExists(atPath: identity.path) {
            let legacyKey = sanitize(
                "\(identity.server)_\(identity.mediaId)_full_anim_g4r13"
            )
            let legacyPath = (dir as NSString).appendingPathComponent(legacyKey)
            if let legacyData = FileManager.default.contents(atPath: legacyPath),
               let legacyImage = MediaCache.decode(legacyData, animated: true),
               (legacyImage.images?.count ?? 0) > 1 {
                (legacyData as NSData).write(toFile: identity.path, atomically: true)
                scheduleTrim()
                memory.setObject(
                    legacyImage,
                    forKey: identity.key as NSString,
                    cost: MediaCache.memoryCost(legacyImage, dataCount: legacyData.count)
                )
                completion(legacyImage)
                return
            }
        }

        let finish: (UIImage?) -> Void = { [weak self] image in
            guard let self = self else {
                completion(image)
                return
            }

            let frameCount = image?.images?.count ?? 0
            if allowRepair && expectedAnimated && frameCount <= 1 {

                self.memory.removeObject(forKey: identity.key as NSString)
                self.ioQueue.async {
                    try? FileManager.default.removeItem(atPath: identity.path)
                    DispatchQueue.main.async {
                        self.loadStickerAnimatedImagePass(
                            mxc: mxc,
                            expectedAnimated: expectedAnimated,
                            allowRepair: false,
                            completion: completion
                        )
                    }
                }
                return
            }

            completion(image)
        }

        if MatrixE2EEManager.encryptedMediaRecord(for: mxc) != nil {
            loadEncryptedImage(
                mxc: mxc,
                key: identity.key,
                timeout: 60,
                animated: true,
                completion: finish
            )
            return
        }

        let path = "/_matrix/client/v1/media/download/\(identity.server)/\(identity.mediaId)"
        load(
            key: identity.key,
            urlPath: path,
            timeout: 60,
            animated: true,
            completion: finish
        )
    }

    // MARK: - Sticker and media export

    func exportStickerOriginal(
        mxc: String,
        destinationPath: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard let identity = stickerAnimatedCacheIdentity(mxc: mxc) else {
            completion(false)
            return
        }

        func copyCachedSource() {
            self.ioQueue.async {
                let fm = FileManager.default
                guard fm.fileExists(atPath: identity.path) else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                try? fm.removeItem(atPath: destinationPath)
                var ok = true
                do {
                    try fm.copyItem(atPath: identity.path, toPath: destinationPath)
                } catch {
                    ok = false
                }
                DispatchQueue.main.async { completion(ok) }
            }
        }

        if FileManager.default.fileExists(atPath: identity.path) {
            copyCachedSource()
            return
        }

        loadStickerAnimatedImage(mxc: mxc) { [weak self] _ in
            guard self != nil else {
                completion(false)
                return
            }
            copyCachedSource()
        }
    }

    private func videoBackedAnimatedWebPPath(for mxc: String) -> String? {
        guard let (server, mediaId) = parseMxc(mxc) else { return nil }
        let key = sanitize("\(server)_\(mediaId)_video_webp_g4r18.webp")
        return (dir as NSString).appendingPathComponent(key)
    }

    func exportVideoBackedAnimatedWebPAsSticker(
        mxc: String,
        destinationPath: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard let sourcePath = videoBackedAnimatedWebPPath(for: mxc) else {
            completion(false)
            return
        }

        func normalizeExistingSource() {
            self.videoWebPQueue.async {
                guard FileManager.default.fileExists(atPath: sourcePath) else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }

                let rc: Int32 = sourcePath.withCString { inputC in
                    destinationPath.withCString { outputC in
                        magnistraWebPVerticalFlipCopy(inputC, outputC)
                    }
                }

                var ok = false
                if rc >= 2,
                   let data = FileManager.default.contents(atPath: destinationPath),
                   let image = MediaCache.decode(data, animated: true),
                   (image.images?.count ?? 0) > 1 {
                    ok = true
                } else {
                    try? FileManager.default.removeItem(atPath: destinationPath)
                }
                DispatchQueue.main.async { completion(ok) }
            }
        }

        if FileManager.default.fileExists(atPath: sourcePath) {
            normalizeExistingSource()
            return
        }

        guard let info = videoBackedAnimatedInfo(for: mxc) else {
            completion(false)
            return
        }

        loadVideoBackedAnimatedWebP(
            mxc: mxc,
            filename: info.filename,
            mimeType: info.mimeType
        ) { image, _ in
            guard image != nil else {
                completion(false)
                return
            }
            normalizeExistingSource()
        }
    }

    func exportAnimatedWebPAsTelegramWebM(
        webpPath: String,
        destinationPath: String,
        completion: @escaping (Bool) -> Void
    ) {
        videoWebPQueue.async {
            try? FileManager.default.removeItem(atPath: destinationPath)

            let rc: Int32 = webpPath.withCString { inputC in
                destinationPath.withCString { outputC in
                    magnistraAnimatedWebPToVP9WebM(
                        inputC,
                        outputC,
                        512,
                        3000,
                        30,
                        262144
                    )
                }
            }

            let attrs = try? FileManager.default.attributesOfItem(
                atPath: destinationPath
            )
            let bytes = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let ok = rc >= 2 && bytes > 0 && bytes <= 262144
            if !ok {
                try? FileManager.default.removeItem(atPath: destinationPath)
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    static func stickerLibraryPreview(path: String) -> UIImage? {
        guard let data = FileManager.default.contents(atPath: path),
              let image = decode(data, animated: true) else { return nil }
        return image.images?.first ?? image
    }

    func loadStickerLibraryAnimatedImage(
        path: String,
        completion: @escaping (UIImage?) -> Void
    ) {
        ioQueue.async {
            guard let data = FileManager.default.contents(atPath: path),
                  let image = MediaCache.decode(data, animated: true) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            DispatchQueue.main.async { completion(image) }
        }
    }

    func loadFullAnimatedImage(
        mxc: String,
        trueSticker: Bool,
        completion: @escaping (UIImage?) -> Void
    ) {
        if trueSticker {
            loadStickerAnimatedImage(mxc: mxc, completion: completion)
            return
        }
        loadFullAnimatedImage(mxc: mxc, completion: completion)
    }

    // MARK: - Full images

    func loadFullImage(mxc: String, completion: @escaping (UIImage?) -> Void) {

        if let transport = videoBackedAnimatedInfo(for: mxc) {
            loadVideoBackedAnimatedWebP(
                mxc: mxc,
                filename: transport.filename,
                mimeType: transport.mimeType
            ) { image, _ in
                completion(image)
            }
            return
        }

        guard let (server, mediaId) = parseMxc(mxc) else {
            MediaCache.record("bad mxc (full)")
            completion(nil)
            return
        }
        let key = sanitize("\(server)_\(mediaId)_full")
        if MatrixE2EEManager.encryptedMediaRecord(for: mxc) != nil {
            loadEncryptedImage(mxc: mxc, key: key, timeout: 60, animated: true, completion: completion)
            return
        }
        let path = "/_matrix/client/v1/media/download/\(server)/\(mediaId)"

        load(key: key, urlPath: path, timeout: 60, animated: true, completion: completion)
    }

    func loadFullAnimatedImage(mxc: String, completion: @escaping (UIImage?) -> Void) {

        if stickerInfo(for: mxc) != nil {
            loadStickerAnimatedImage(mxc: mxc, completion: completion)
            return
        }

        if let transport = videoBackedAnimatedInfo(for: mxc) {
            loadVideoBackedAnimatedWebP(
                mxc: mxc,
                filename: transport.filename,
                mimeType: transport.mimeType
            ) { image, _ in
                completion(image)
            }
            return
        }

        guard let (server, mediaId) = parseMxc(mxc) else {
            MediaCache.record("bad mxc (animated full)")
            completion(nil)
            return
        }
        let key = sanitize("\(server)_\(mediaId)_full_anim_g4r13")
        if MatrixE2EEManager.encryptedMediaRecord(for: mxc) != nil {
            loadEncryptedImage(mxc: mxc, key: key, timeout: 60,
                               animated: true, completion: completion)
            return
        }
        let path = "/_matrix/client/v1/media/download/\(server)/\(mediaId)"
        load(key: key, urlPath: path, timeout: 60, animated: true, completion: completion)
    }

    // MARK: - Encrypted media

    private func loadEncryptedImage(mxc: String, key: String, timeout: Int, animated: Bool,
                                    completion: @escaping (UIImage?) -> Void) {
        if let cached = memory.object(forKey: key as NSString) {
            completion(cached)
            return
        }
        let diskPath = (dir as NSString).appendingPathComponent(key)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            if let data = FileManager.default.contents(atPath: diskPath),
               let img = MediaCache.decode(data, animated: animated) {
                self.memory.setObject(img, forKey: key as NSString,
                                      cost: MediaCache.memoryCost(img, dataCount: data.count))
                DispatchQueue.main.async { completion(img) }
                return
            }
            DispatchQueue.main.async {
                guard let base = MatrixSession.homeserverURL,
                      let token = MatrixSession.accessToken,
                      let (server, mediaId) = self.parseMxc(mxc) else {
                    completion(nil); return
                }
                let headers = ["Authorization": "Bearer \(token)"]
                let url = base + "/_matrix/client/v1/media/download/\(server)/\(mediaId)"
                CurlFetcher.fetchData(url: url, headers: headers, timeout: timeout) { [weak self] data in
                    guard let self = self, let data = data, data.count > 0 else {
                        completion(nil); return
                    }
                    self.ioQueue.async {
                        guard let plain = self.decryptEncryptedMediaData(data, mxc: mxc,
                                                                         scratchBase: diskPath),
                              let img = MediaCache.decode(plain, animated: animated) else {
                            DispatchQueue.main.async {
                                MediaCache.record("encrypted image decrypt/decode failed")
                                completion(nil)
                            }
                            return
                        }
                        (plain as NSData).write(toFile: diskPath, atomically: true)
                        self.scheduleTrim()
                        self.memory.setObject(img, forKey: key as NSString,
                                              cost: MediaCache.memoryCost(img, dataCount: plain.count))
                        DispatchQueue.main.async {
                            MediaCache.record("encrypted image ok (\(plain.count)B)")
                            completion(img)
                        }
                    }
                }
            }
        }
    }

    private func decryptEncryptedMediaData(_ data: Data, mxc: String,
                                           scratchBase: String) -> Data? {
        guard let record = MatrixE2EEManager.encryptedMediaRecord(for: mxc) else { return data }
        let fm = FileManager.default
        let encryptedPath = scratchBase + ".media.enc"
        let decryptedPath = scratchBase + ".media.dec"
        try? fm.removeItem(atPath: encryptedPath)
        try? fm.removeItem(atPath: decryptedPath)
        guard (data as NSData).write(toFile: encryptedPath, atomically: true) else { return nil }
        defer {
            try? fm.removeItem(atPath: encryptedPath)
            try? fm.removeItem(atPath: decryptedPath)
        }
        guard decryptEncryptedMediaFile(inputPath: encryptedPath, outputPath: decryptedPath,
                                        record: record) else { return nil }
        return fm.contents(atPath: decryptedPath)
    }

    private func decryptEncryptedMediaFile(inputPath: String, outputPath: String,
                                           record: MagnistraEncryptedMediaRecord) -> Bool {
        return record.key.withUnsafeBufferPointer { key in
            record.iv.withUnsafeBufferPointer { iv in
                record.sha256.withUnsafeBufferPointer { sha in
                    inputPath.withCString { src in
                        outputPath.withCString { dst in
                            magnistra_crypto_aes256_ctr_decrypt_file(
                                src, dst, key.baseAddress, iv.baseAddress, sha.baseAddress) == 1
                        }
                    }
                }
            }
        }
    }

    private func load(key: String, urlPath: String, timeout: Int, animated: Bool = false,
                      completion: @escaping (UIImage?) -> Void) {

        if let cached = memory.object(forKey: key as NSString) {
            completion(cached)
            return
        }
        let diskPath = (dir as NSString).appendingPathComponent(key)
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            if let data = FileManager.default.contents(atPath: diskPath),
               let img = MediaCache.decode(data, animated: animated) {
                self.memory.setObject(img, forKey: key as NSString,
                                      cost: MediaCache.memoryCost(img, dataCount: data.count))
                DispatchQueue.main.async {
                    MediaCache.record("disk hit (\(data.count)B \(MediaCache.dims(img)))")
                    completion(img)
                }
                return
            }

            DispatchQueue.main.async {
                guard let base = MatrixSession.homeserverURL, let token = MatrixSession.accessToken else {
                    MediaCache.record("no session (no base/token)")
                    completion(nil)
                    return
                }

                if self.inFlight[key] != nil {
                    self.inFlight[key]?.append(completion)
                    MediaCache.record("coalesced media request")
                    return
                }
                self.inFlight[key] = [completion]
                let headers = ["Authorization": "Bearer \(token)"]
                let fullURL = base + urlPath
                CurlFetcher.fetchData(url: fullURL, headers: headers, timeout: timeout) { [weak self] data in
                    guard let self = self else { return }

                    let waiters = self.inFlight.removeValue(forKey: key) ?? []
                    guard let data = data, let img = MediaCache.decode(data, animated: animated) else {

                        if let data = data {
                            MediaCache.record("not an image (\(data.count)B)")
                        } else {
                            MediaCache.record("no data (connect/TLS/timeout)")
                        }
                        waiters.forEach { $0(nil) }
                        return
                    }
                    MediaCache.record("ok (\(data.count)B \(MediaCache.dims(img)))")
                    self.memory.setObject(img, forKey: key as NSString,
                                          cost: MediaCache.memoryCost(img, dataCount: data.count))
                    self.ioQueue.async {

                        (data as NSData).write(toFile: diskPath, atomically: true)
                        self.scheduleTrim()
                    }
                    waiters.forEach { $0(img) }
                }
            }
        }
    }

    private static let maxGifFrames = 120

    private static let maxGifPixels = 3 * 1024 * 1024

    // MARK: - Image decoding

    private static func decode(_ data: Data, animated: Bool) -> UIImage? {
        let result: UIImage?
        if animated, isGIF(data), let gif = animatedGIF(data) {
            result = gif
        } else if animated, isWebP(data), let webp = animatedWebP(data) {
            result = webp
        } else if isWebP(data), let webp = decodeWebP(data) {
            result = webp
        } else if animated,
                  (mediaKind(data) == "json" || mediaKind(data) == "gzip"),
                  let lottie = animatedLottieData(data) {

            result = lottie
        } else {
            result = UIImage(data: data)
        }

        if animated {
            let kind = mediaKind(data)
            let frames = result?.images?.count ?? 0
            magnistraMediaTrace(
                "IMAGE_DECODE animated=YES kind=\(kind) bytes=\(data.count) result=\(result == nil ? "NO" : "YES") frames=\(frames)"
            )
        }
        return result
    }

    private static func animatedLottieData(_ data: Data) -> UIImage? {

        let encoded = [UInt8](data)
        guard !encoded.isEmpty else { return nil }

        var result: UIImage?
        encoded.withUnsafeBufferPointer { bytes in
            guard let animation = magnistraLottieCreateData(bytes.baseAddress, encoded.count) else { return }
            defer { magnistraLottieDestroy(animation) }

            var sourceW = 0
            var sourceH = 0
            magnistraLottieSize(animation, &sourceW, &sourceH)
            guard sourceW > 0, sourceH > 0 else { return }

            let maxSide = 80
            let scale = min(1.0, Double(maxSide) / Double(max(sourceW, sourceH)))
            let renderW = max(1, Int(floor(Double(sourceW) * scale)))
            let renderH = max(1, Int(floor(Double(sourceH) * scale)))

            let total = magnistraLottieTotalFrames(animation)
            guard total > 0 else { return }

            let frameLimit = 48
            let outputCount = min(total, frameLimit)

            var frames: [UIImage] = []
            frames.reserveCapacity(outputCount)

            for sampleIndex in 0..<outputCount {
                let frameIndex: Int
                if outputCount <= 1 || total <= 1 {
                    frameIndex = 0
                } else {
                    frameIndex = Int(round(
                        Double(sampleIndex) * Double(total - 1) / Double(outputCount - 1)
                    ))
                }

                var pixels = [UInt32](repeating: 0, count: renderW * renderH)
                pixels.withUnsafeMutableBufferPointer { buffer in
                    magnistraLottieRender(animation, frameIndex, buffer.baseAddress,
                                           renderW, renderH, renderW * 4)
                }

                let pixelData: Data = pixels.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return Data() }
                    return Data(bytes: base, count: buffer.count * MemoryLayout<UInt32>.size)
                }
                guard let provider = CGDataProvider(data: pixelData as CFData) else { break }
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                )
                guard let cg = CGImage(
                    width: renderW, height: renderH,
                    bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: renderW * 4,
                    space: colorSpace, bitmapInfo: bitmapInfo,
                    provider: provider, decode: nil,
                    shouldInterpolate: true, intent: .defaultIntent
                ) else { break }

                frames.append(UIImage(cgImage: cg))
            }

            guard !frames.isEmpty else { return }
            if frames.count == 1 {
                result = frames[0]
                return
            }

            var duration = magnistraLottieDuration(animation)
            if !duration.isFinite || duration <= 0 {
                duration = max(1.0 / 30.0, Double(total) / 30.0)
            }
            result = UIImage.animatedImage(with: frames, duration: duration)
        }
        return result
    }

    // MARK: - Video-backed animated image loading

    func loadVideoBackedAnimatedWebP(
        mxc: String,
        filename: String,
        mimeType: String,
        completion: @escaping (UIImage?, String?) -> Void
    ) {
        guard let (server, mediaId) = parseMxc(mxc) else {
            completion(nil, "mxc")
            return
        }

        let key = sanitize("\(server)_\(mediaId)_video_webp_g4r18.webp")
        let webpPath = (dir as NSString).appendingPathComponent(key)

        if let cached = videoWebPImageCache[key] {
            videoWebPImageOrder = videoWebPImageOrder.filter { $0 != key }
            videoWebPImageOrder.append(key)
            completion(cached, nil)
            return
        }

        if videoWebPWaiters[key] != nil {
            videoWebPWaiters[key]?.append(completion)
            return
        }
        videoWebPWaiters[key] = [completion]

        func finish(_ image: UIImage?, _ error: String? = nil) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if let image = image {
                    self.videoWebPImageCache[key] = image
                    self.videoWebPImageOrder =
                        self.videoWebPImageOrder.filter { $0 != key }
                    self.videoWebPImageOrder.append(key)

                    while self.videoWebPImageOrder.count >
                            self.videoWebPImageCacheLimit {
                        let victim = self.videoWebPImageOrder.removeFirst()
                        self.videoWebPImageCache.removeValue(forKey: victim)
                    }
                }

                let waiters = self.videoWebPWaiters.removeValue(forKey: key) ?? []
                for waiter in waiters { waiter(image, error) }
            }
        }

        videoWebPQueue.async { [weak self] in
            guard let self = self else { return }

            if let data = FileManager.default.contents(atPath: webpPath),
               let image = MediaCache.decodeVideoBackedAnimatedWebP(data),
               (image.images?.count ?? 0) > 1 {
                magnistraMediaTrace(
                    "VIDEO_WEBP_CACHE hit=YES frames=\(image.images?.count ?? 0) duration=\(image.duration)"
                )
                finish(image, nil)
                return
            }

            try? FileManager.default.removeItem(atPath: webpPath)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.downloadFile(
                    mxc: mxc,
                    filename: filename,
                    mimeType: mimeType,
                    progress: nil
                ) { [weak self] sourcePath in
                    guard let self = self, let sourcePath = sourcePath else {
                        finish(nil, "download")
                        return
                    }

                    self.videoWebPQueue.async {
                        let rc: Int32 = sourcePath.withCString { inputC in
                            webpPath.withCString { outputC in
                                magnistraVideoToAnimatedWebP(
                                    inputC, outputC, 224, 8, 36
                                )
                            }
                        }

                        guard rc >= 2 else {
                            try? FileManager.default.removeItem(atPath: webpPath)
                            magnistraMediaTrace(
                                "VIDEO_WEBP_CONVERT result=FAIL stage=bridge rc=\(rc)"
                            )
                            finish(nil, "bridge \(rc)")
                            return
                        }

                        guard let data = FileManager.default.contents(atPath: webpPath) else {
                            finish(nil, "output")
                            return
                        }
                        guard let image = MediaCache.decodeVideoBackedAnimatedWebP(data) else {
                            try? FileManager.default.removeItem(atPath: webpPath)
                            finish(nil, "decode")
                            return
                        }
                        let decodedFrames = image.images?.count ?? 0
                        guard decodedFrames > 1 else {
                            try? FileManager.default.removeItem(atPath: webpPath)
                            magnistraMediaTrace(
                                "VIDEO_WEBP_CONVERT result=FAIL stage=single_frame encoded=\(rc) decoded=\(decodedFrames)"
                            )
                            finish(nil, "single frame \(rc)/\(decodedFrames)")
                            return
                        }

                        self.scheduleTrim()
                        magnistraMediaTrace(
                            "VIDEO_WEBP_CONVERT result=PASS encodedFrames=\(rc) decodedFrames=\(decodedFrames) duration=\(image.duration) bytes=\(data.count)"
                        )
                        finish(image, nil)
                    }
                }
            }
        }
    }

    static func mediaKindAtPath(path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path) else { return "other" }
        return mediaKind(data)
    }

    static func animatedImageAtPath(path: String) -> UIImage? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return decode(data, animated: true)
    }

    private static func mediaKind(_ data: Data) -> String {
        let b = [UInt8](data.prefix(12))
        if b.count >= 6,
           b[0] == 0x47, b[1] == 0x49, b[2] == 0x46,
           b[3] == 0x38, (b[4] == 0x37 || b[4] == 0x39), b[5] == 0x61 { return "gif" }
        if b.count >= 12,
           b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46,
           b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return "webp" }
        if b.count >= 2, b[0] == 0x1f, b[1] == 0x8b { return "gzip" }
        if b.count >= 4, b[0] == 0x1a, b[1] == 0x45, b[2] == 0xdf, b[3] == 0xa3 { return "webm" }
        if b.count >= 8, b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 { return "iso-bmff" }
        if let first = b.first, first == 0x7b || first == 0x5b { return "json" }
        return "other"
    }

    // MARK: - Legacy video playback conversion

    static func legacyVideoPlaybackPath(path: String, mimeType: String, animated: Bool) -> String {
        let fm = FileManager.default
        let lowerMime = mimeType.lowercased()
        var playbackPath = path

        func stableSuffix(_ text: String) -> String {
            var h: UInt32 = 5381
            for b in text.utf8 { h = ((h << 5) &+ h) &+ UInt32(b) }
            return String(format: "%08x", h)
        }

        if lowerMime == "video/mp4" &&
           (path as NSString).pathExtension.lowercased() != "mp4" {
            let canonical = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("magnistra-video-" + stableSuffix(path) + ".mp4")
            let srcAttrs = try? fm.attributesOfItem(atPath: path)
            let dstAttrs = try? fm.attributesOfItem(atPath: canonical)
            let srcSize = (srcAttrs?[.size] as? NSNumber)?.uint64Value ?? 0
            let dstSize = (dstAttrs?[.size] as? NSNumber)?.uint64Value ?? 0
            if srcSize == 0 || srcSize != dstSize {
                try? fm.removeItem(atPath: canonical)
                do { try fm.copyItem(atPath: path, toPath: canonical) }
                catch { return path }
            }
            playbackPath = canonical
        }

        guard animated, lowerMime == "video/mp4" else { return playbackPath }
        guard let attrs = try? fm.attributesOfItem(atPath: playbackPath),
              let size = attrs[.size] as? NSNumber,
              size.intValue > 0, size.intValue <= 32 * 1024 * 1024,
              let original = fm.contents(atPath: playbackPath) else {
            return playbackPath
        }

        var bytes = [UInt8](original)
        guard bytes.count >= 16 else { return playbackPath }
        var patched = false
        var i = 0

        while i + 12 < bytes.count {
            if bytes[i] == 0x61, bytes[i + 1] == 0x76,
               bytes[i + 2] == 0x63, bytes[i + 3] == 0x43 {
                let record = i + 4
                if record + 6 < bytes.count {
                    let declaredLevel = bytes[record + 3]
                    if declaredLevel > 41 {
                        bytes[record + 3] = 41
                        patched = true
                    }

                    let spsCount = Int(bytes[record + 5] & 0x1f)
                    var p = record + 6
                    for _ in 0..<spsCount {
                        guard p + 2 <= bytes.count else { break }
                        let n = (Int(bytes[p]) << 8) | Int(bytes[p + 1])
                        p += 2
                        guard n > 0, p + n <= bytes.count else { break }
                        if n >= 4, (bytes[p] & 0x1f) == 7, bytes[p + 3] > 41 {
                            bytes[p + 3] = 41
                            patched = true
                        }
                        p += n
                    }
                }
            }
            i += 1
        }

        guard patched else { return playbackPath }
        let fixed = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("magnistra-video-" + stableSuffix(playbackPath) + "-level41.mp4")
        let data = Data(bytes)
        do {
            try data.write(to: URL(fileURLWithPath: fixed), options: .atomic)
            return fixed
        } catch {
            return playbackPath
        }
    }

    private static let maxWebPPixels = 4 * 1024 * 1024
    private static let maxAnimatedWebPFrames = 60
    private static let maxAnimatedWebPStoredPixels = 3 * 1024 * 1024
    private static let animatedWebPMaxSide: CGFloat = 224

    // MARK: - Animated WebP decoding

    private static func animatedWebP(
        _ data: Data,
        verticalFlip: Bool = false
    ) -> UIImage? {
        let encoded = [UInt8](data)
        var result: UIImage?

        encoded.withUnsafeBufferPointer { src in
            var webpData = MagnistraWebPData(bytes: src.baseAddress, size: encoded.count)
            let decoder = withUnsafePointer(to: &webpData) { ptr in
                magnistraWebPAnimDecoderNewInternal(ptr, nil, magnistraWebPDemuxABIVersion)
            }
            guard let decoder = decoder else { return }
            defer { magnistraWebPAnimDecoderDelete(decoder) }

            var info = MagnistraWebPAnimInfo(
                canvasWidth: 0, canvasHeight: 0, loopCount: 0,
                backgroundColor: 0, frameCount: 0
            )
            guard magnistraWebPAnimDecoderGetInfo(decoder, &info) != 0,
                  info.frameCount > 1,
                  info.canvasWidth > 0,
                  info.canvasHeight > 0 else { return }

            let fullW = Int(info.canvasWidth)
            let fullH = Int(info.canvasHeight)
            guard fullW <= maxWebPPixels / max(1, fullH),
                  fullW * fullH <= maxWebPPixels else { return }

            var frames: [UIImage] = []
            var storedPixels = 0
            var lastTimestamp: Int32 = 0

            while magnistraWebPAnimDecoderHasMoreFrames(decoder) != 0,
                  frames.count < maxAnimatedWebPFrames {
                var rgbaPtr: UnsafeMutablePointer<UInt8>?
                var timestamp: Int32 = 0
                guard magnistraWebPAnimDecoderGetNext(decoder, &rgbaPtr, &timestamp) != 0,
                      let rgbaPtr = rgbaPtr else { break }

                let bytes = Data(bytes: rgbaPtr, count: fullW * fullH * 4)
                guard let provider = CGDataProvider(data: bytes as CFData) else { break }
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
                guard let cg = CGImage(
                    width: fullW, height: fullH,
                    bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: fullW * 4,
                    space: colorSpace, bitmapInfo: bitmapInfo,
                    provider: provider, decode: nil,
                    shouldInterpolate: true, intent: .defaultIntent
                ) else { break }

                let orientation: UIImage.Orientation =
                    verticalFlip ? .downMirrored : .up
                let decodedFrame = UIImage(
                    cgImage: cg,
                    scale: 1.0,
                    orientation: orientation
                )
                let frame = downscaleAnimatedWebPFrame(
                    decodedFrame,
                    forceRasterize: verticalFlip
                )
                let framePixels = max(1, Int(frame.size.width)) * max(1, Int(frame.size.height))
                if storedPixels + framePixels > maxAnimatedWebPStoredPixels && !frames.isEmpty { break }
                storedPixels += framePixels
                frames.append(frame)
                lastTimestamp = timestamp
            }

            guard frames.count > 1 else { return }
            var duration = Double(lastTimestamp) / 1000.0
            if duration <= 0 { duration = Double(frames.count) * 0.1 }
            result = UIImage.animatedImage(with: frames, duration: duration)
        }
        return result
    }

    private static func downscaleAnimatedWebPFrame(
        _ image: UIImage,
        forceRasterize: Bool = false
    ) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        if !forceRasterize && longest <= animatedWebPMaxSide {
            return image
        }

        let scale = longest > animatedWebPMaxSide
            ? animatedWebPMaxSide / longest
            : 1.0
        let size = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return result
    }

    private static func decodeVideoBackedAnimatedWebP(_ data: Data) -> UIImage? {
        guard isWebP(data) else { return nil }
        return animatedWebP(data, verticalFlip: true)
    }

    private static func isWebP(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let b = [UInt8](data.prefix(12))
        return b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46
            && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50
    }

    private static func decodeWebP(_ data: Data) -> UIImage? {
        let encoded = [UInt8](data)
        var width: Int32 = 0
        var height: Int32 = 0

        let infoOK: Int32 = encoded.withUnsafeBufferPointer { src in
            magnistraWebPGetInfo(src.baseAddress, encoded.count, &width, &height)
        }
        guard infoOK != 0, width > 0, height > 0 else { return nil }

        let w = Int(width)
        let h = Int(height)
        guard w <= maxWebPPixels / max(1, h),
              w * h <= maxWebPPixels else { return nil }

        let byteCount = w * h * 4
        var rgba = [UInt8](repeating: 0, count: byteCount)

        let decoded = encoded.withUnsafeBufferPointer { src in
            rgba.withUnsafeMutableBufferPointer { dst in
                magnistraWebPDecodeRGBAInto(
                    src.baseAddress,
                    encoded.count,
                    dst.baseAddress,
                    byteCount,
                    Int32(w * 4)
                )
            }
        }
        guard decoded != nil else { return nil }

        let pixels = Data(rgba)
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)

        guard let cg = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }

        return UIImage(cgImage: cg)
    }

    private static func isGIF(_ data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        let magic = [UInt8](data.prefix(3))
        return magic == [0x47, 0x49, 0x46]
    }

    private static func animatedGIF(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)

        guard count > 1 else { return nil }

        var frames: [UIImage] = []
        var duration: Double = 0
        var pixels = 0
        for i in 0..<min(count, maxGifFrames) {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            pixels += cg.width * cg.height
            if pixels > maxGifPixels && !frames.isEmpty { break }
            frames.append(UIImage(cgImage: cg))
            duration += frameDelay(source: source, index: i)
        }
        guard frames.count > 1 else { return nil }

        if duration <= 0 { duration = Double(frames.count) * 0.1 }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private static func frameDelay(source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gif = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
            return 0.1
        }
        var delay = (gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber)?.doubleValue ?? 0
        if delay <= 0 {
            delay = (gif[kCGImagePropertyGIFDelayTime as String] as? NSNumber)?.doubleValue ?? 0
        }

        return delay < 0.02 ? 0.1 : delay
    }

    private static func memoryCost(_ image: UIImage, dataCount: Int) -> Int {
        guard let frames = image.images, !frames.isEmpty else { return dataCount }
        let scale = image.scale
        let perFrame = Int(image.size.width * scale * image.size.height * scale) * 4
        return max(dataCount, perFrame * frames.count)
    }

    // MARK: - Audio cache

    func loadAudioPath(mxc: String, completion: @escaping (String?) -> Void) {
        guard let (server, mediaId) = parseMxc(mxc) else {
            MediaCache.record("bad mxc (audio)")
            completion(nil)
            return
        }

        let encryptedSuffix = MatrixE2EEManager.encryptedMediaRecord(for: mxc) == nil ? "" : "_encdec"
        let key = sanitize("\(server)_\(mediaId)_audio") + encryptedSuffix + ".m4a"
        let diskPath = (dir as NSString).appendingPathComponent(key)
        let urlPath = "/_matrix/client/v1/media/download/\(server)/\(mediaId)"
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            if FileManager.default.fileExists(atPath: diskPath) {
                let playable = self.playablePath(diskPath, server: server, mediaId: mediaId)
                DispatchQueue.main.async {
                    MediaCache.record("audio disk hit")
                    completion(playable)
                }
                return
            }
            DispatchQueue.main.async {
                guard let base = MatrixSession.homeserverURL, let token = MatrixSession.accessToken else {
                    MediaCache.record("no session (audio)")
                    completion(nil)
                    return
                }
                let headers = ["Authorization": "Bearer \(token)"]
                CurlFetcher.fetchData(url: base + urlPath, headers: headers, timeout: 60) { [weak self] data in
                    guard let self = self else { return }
                    guard let data = data, data.count > 0 else {
                        MediaCache.record("no data (audio)")
                        completion(nil)
                        return
                    }
                    self.ioQueue.async {

                        guard let finalData = self.decryptEncryptedMediaData(data, mxc: mxc,
                                                                              scratchBase: diskPath) else {
                            DispatchQueue.main.async {
                                MediaCache.record("encrypted audio decrypt failed")
                                completion(nil)
                            }
                            return
                        }
                        (finalData as NSData).write(toFile: diskPath, atomically: true)
                        self.scheduleTrim()
                        let playable = self.playablePath(diskPath, server: server, mediaId: mediaId)
                        DispatchQueue.main.async {
                            MediaCache.record("audio ok (\(finalData.count)B)")
                            completion(playable)
                        }
                    }
                }
            }
        }
    }

    func storeAudioFile(fromPath src: String, mxc: String) {
        guard let (server, mediaId) = parseMxc(mxc) else { return }
        let encryptedSuffix = MatrixE2EEManager.encryptedMediaRecord(for: mxc) == nil ? "" : "_encdec"
        let key = sanitize("\(server)_\(mediaId)_audio") + encryptedSuffix + ".m4a"
        let diskPath = (dir as NSString).appendingPathComponent(key)
        ioQueue.async { [weak self] in
            guard let self = self, let data = FileManager.default.contents(atPath: src) else { return }
            (data as NSData).write(toFile: diskPath, atomically: true)
            self.scheduleTrim()
        }
    }

    private func playablePath(_ rawPath: String, server: String, mediaId: String) -> String {
        let wavPath = (dir as NSString).appendingPathComponent(sanitize("\(server)_\(mediaId)_audio") + ".wav")
        if FileManager.default.fileExists(atPath: wavPath) { return wavPath }
        guard let data = FileManager.default.contents(atPath: rawPath), data.count >= 4 else { return rawPath }
        let isOgg = data[0] == 0x4F && data[1] == 0x67 && data[2] == 0x67 && data[3] == 0x53
        guard isOgg else { return rawPath }
        let rc = opus_ogg_to_wav(rawPath, wavPath)
        if rc == 0 {
            MediaCache.record("opus->wav ok")
            return wavPath
        }
        MediaCache.record("opus->wav fail (\(rc))")
        return rawPath
    }

    func storeThumbnail(_ image: UIImage, mxc: String, width: Int, height: Int) {
        guard let (server, mediaId) = parseMxc(mxc) else { return }
        store(image, key: cacheKey(server: server, mediaId: mediaId, width: width, height: height))
    }

    func storeFull(_ image: UIImage, mxc: String) {
        guard let (server, mediaId) = parseMxc(mxc) else { return }
        store(image, key: sanitize("\(server)_\(mediaId)_full"))
    }

    private func store(_ image: UIImage, key: String) {

        memory.setObject(image, forKey: key as NSString)
        let diskPath = (dir as NSString).appendingPathComponent(key)
        ioQueue.async { [weak self] in
            guard let self = self, let data = image.jpegData(compressionQuality: 0.9) else { return }

            (data as NSData).write(toFile: diskPath, atomically: true)
            self.scheduleTrim()
        }
    }

    func downloadedFilePath(mxc: String, filename: String, mimeType: String) -> String? {
        guard let name = fileName(mxc: mxc, filename: filename, mimeType: mimeType),
              presentFileNames.contains(name) else { return nil }
        return (filesDir as NSString).appendingPathComponent(name)
    }

    // MARK: - Downloaded files

    func downloadFile(mxc: String, filename: String, mimeType: String,
                      progress: ((Float) -> Void)?,
                      completion: @escaping (String?) -> Void) {
        guard let (server, mediaId) = parseMxc(mxc),
              let name = fileName(mxc: mxc, filename: filename, mimeType: mimeType) else {
            MediaCache.record("bad mxc (file)")
            completion(nil)
            return
        }
        let path = (filesDir as NSString).appendingPathComponent(name)

        if FileManager.default.fileExists(atPath: path) {
            presentFileNames.insert(name)
            completion(path)
            return
        }
        presentFileNames.remove(name)
        if fileWaiters[path] != nil {
            fileWaiters[path]?.append((progress, completion))
            return
        }
        guard let base = MatrixSession.homeserverURL, let token = MatrixSession.accessToken else {
            MediaCache.record("no session (file)")
            completion(nil)
            return
        }
        fileWaiters[path] = [(progress, completion)]

        let partPath = path + ".part"
        let url = base + "/_matrix/client/v1/media/download/\(server)/\(mediaId)"
        CurlFetcher.downloadToFile(url: url,
                                   headers: ["Authorization": "Bearer \(token)"],
                                   outputPath: partPath,
                                   progress: { [weak self] fraction in
                                       for waiter in self?.fileWaiters[path] ?? [] {
                                           waiter.progress?(fraction)
                                       }
                                   }) { [weak self] ok in
            guard let self = self else { return }
            let fm = FileManager.default
            var succeeded = ok
            if ok {
                try? fm.removeItem(atPath: path)
                if let record = MatrixE2EEManager.encryptedMediaRecord(for: mxc) {
                    succeeded = self.decryptEncryptedMediaFile(inputPath: partPath,
                                                               outputPath: path,
                                                               record: record)
                    try? fm.removeItem(atPath: partPath)
                    if !succeeded { try? fm.removeItem(atPath: path) }
                } else {
                    do { try fm.moveItem(atPath: partPath, toPath: path) } catch { succeeded = false }
                }
            } else {
                try? fm.removeItem(atPath: partPath)
            }
            MediaCache.record(succeeded ? "file ok" : "file failed")
            if succeeded { self.presentFileNames.insert(name) }
            let waiters = self.fileWaiters.removeValue(forKey: path) ?? []
            for waiter in waiters { waiter.completion(succeeded ? path : nil) }
        }
    }

    private func fileName(mxc: String, filename: String, mimeType: String) -> String? {
        guard let (server, mediaId) = parseMxc(mxc) else { return nil }
        let ext = fileExtension(filename: filename, mimeType: mimeType)
        let encryptedSuffix = MatrixE2EEManager.encryptedMediaRecord(for: mxc) == nil ? "" : "_encdec"
        return sanitize("\(server)_\(mediaId)" + encryptedSuffix) + "." + ext
    }

    private static let mimeExtensions: [String: String] = [
        "text/plain": "txt",
        "text/markdown": "md",
        "text/csv": "csv",
        "text/html": "html",
        "application/json": "json",
        "application/xml": "xml",
        "text/xml": "xml",
        "image/jpeg": "jpg",
        "image/svg+xml": "svg",
        "audio/mpeg": "mp3",
        "audio/mp4": "m4a",
        "video/quicktime": "mov",
        "application/msword": "doc",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
        "application/vnd.ms-excel": "xls",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
        "application/zip": "zip",
    ]

    private func fileExtension(filename: String, mimeType: String) -> String {
        if let dot = filename.lastIndex(of: "."), dot < filename.index(before: filename.endIndex) {
            let candidate = String(filename[filename.index(after: dot)...])
            return sanitize(String(candidate.prefix(8)))
        }
        if let mapped = MediaCache.mimeExtensions[mimeType.lowercased()] { return mapped }
        if let slash = mimeType.lastIndex(of: "/"), slash < mimeType.index(before: mimeType.endIndex) {
            let subtype = String(mimeType[mimeType.index(after: slash)...])
            let isPlain = subtype.count <= 8 && subtype.allSatisfy { $0.isLetter || $0.isNumber }
            if isPlain { return sanitize(subtype) }
        }
        return "bin"
    }

    // MARK: - Cache storage management

    func filesUsage(completion: @escaping (_ bytes: UInt64, _ files: Int) -> Void) {
        trimQueue.async {
            let fm = FileManager.default
            var total: UInt64 = 0
            var count = 0
            if let names = try? fm.contentsOfDirectory(atPath: self.filesDir) {
                for name in names {
                    let path = (self.filesDir as NSString).appendingPathComponent(name)
                    guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
                    total += (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                    count += 1
                }
            }
            DispatchQueue.main.async { completion(total, count) }
        }
    }

    func clearFiles(completion: @escaping () -> Void) {
        trimQueue.async {
            let fm = FileManager.default
            if let names = try? fm.contentsOfDirectory(atPath: self.filesDir) {
                for name in names {
                    try? fm.removeItem(atPath: (self.filesDir as NSString).appendingPathComponent(name))
                }
            }
            DispatchQueue.main.async {
                self.presentFileNames.removeAll()
                completion()
            }
        }
    }

    func diskUsage(completion: @escaping (_ bytes: UInt64, _ files: Int) -> Void) {
        trimQueue.async {
            let fm = FileManager.default
            var total: UInt64 = 0
            var count = 0
            if let names = try? fm.contentsOfDirectory(atPath: self.dir) {
                for name in names {
                    let path = (self.dir as NSString).appendingPathComponent(name)
                    guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
                    total += (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                    count += 1
                }
            }
            DispatchQueue.main.async { completion(total, count) }
        }
    }

    func clear(completion: @escaping () -> Void) {
        memory.removeAllObjects()
        trimQueue.async {
            let fm = FileManager.default
            if let names = try? fm.contentsOfDirectory(atPath: self.dir) {
                for name in names {
                    try? fm.removeItem(atPath: (self.dir as NSString).appendingPathComponent(name))
                }
            }
            DispatchQueue.main.async { completion() }
        }
    }

    // MARK: - Eviction

    private func scheduleTrim() {
        trimQueue.async { [weak self] in
            guard let self = self, !self.trimScheduled else { return }
            self.trimScheduled = true
            self.trimQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self else { return }
                self.trimScheduled = false
                self.trimDiskCache()
            }
        }
    }

    private func trimDiskCache() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }

        var entries: [(path: String, size: UInt64, date: Date)] = []
        var total: UInt64 = 0
        for name in names {
            let path = (dir as NSString).appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            let date = (attrs[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
            entries.append((path, size, date))
            total += size
        }
        if total <= maxDiskBytes { return }

        let target = maxDiskBytes * 8 / 10
        entries.sort { $0.date < $1.date }
        for entry in entries {
            if total <= target { break }
            try? fm.removeItem(atPath: entry.path)
            total = total > entry.size ? total - entry.size : 0
        }
    }

    private func parseMxc(_ mxc: String) -> (server: String, mediaId: String)? {
        guard mxc.hasPrefix("mxc://") else { return nil }
        let rest = String(mxc.dropFirst("mxc://".count))
        let parts = rest.components(separatedBy: "/")
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    private func cacheKey(server: String, mediaId: String, width: Int, height: Int) -> String {
        return sanitize("\(server)_\(mediaId)_\(width)x\(height)")
    }

    private func sanitize(_ s: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        return String(s.map { allowed.contains($0) ? $0 : "_" })
    }
}
