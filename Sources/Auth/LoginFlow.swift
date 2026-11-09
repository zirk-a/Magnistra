// Overview: Login screen and session unlock: encrypted V2 session archive/cache and Keychain access.
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

enum MagnistraGridFastDecode {

    private static func ownedImage(_ raw: UnsafeMutableRawPointer?) -> UIImage? {
        guard let ptr = raw else { return nil }
        return Unmanaged<UIImage>.fromOpaque(ptr).takeRetainedValue()
    }
    static func image(data: Data) -> UIImage? {
        let raw: UnsafeMutableRawPointer? = data.withUnsafeBytes { bytes in
            guard let start = bytes.baseAddress, bytes.count > 0 else { return nil }
            return MagnistraGridDecodeBytes(start, bytes.count)
        }
        return ownedImage(raw) ?? UIImage(data: data)
    }
    static func image(contentsOfFile path: String) -> UIImage? {
        let raw: UnsafeMutableRawPointer? = path.withCString { ptr in
            return MagnistraGridDecodePath(ptr)
        }
        return ownedImage(raw) ?? UIImage(contentsOfFile: path)
    }
}

private final class MagnistraLoginPointer: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func draw(_ rect: CGRect) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.close()
        UIColor.white.setFill()
        path.fill()
    }
}

@_silgen_name("magnistra_v2_open")
private func magnistraV2NativeOpen(_ bytes: UnsafePointer<UInt8>?, _ count: Int,
                                    _ user: UnsafePointer<CChar>?, _ password: UnsafePointer<CChar>?,
                                    _ output: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
                                    _ outputLength: UnsafeMutablePointer<Int>?) -> Int32
@_silgen_name("magnistra_v2_release")
private func magnistraV2NativeRelease(_ buffer: UnsafeMutableRawPointer?, _ count: Int)

private struct MagnistraV2UnlockedArchive {
    let cookies: [HTTPCookie]
    let payload: Data
}

@_silgen_name("crypto_hash_sha256")
private func magnistraV2Sha256(_ output: UnsafeMutablePointer<UInt8>?,
                                _ input: UnsafePointer<UInt8>?,
                                _ length: UInt64) -> Int32

enum MagnistraV2SessionCache {
    private static let lock = NSLock()
    private static var sessionPayload: Data? = nil
    private static let service = "com.zirka.magnistra.verified-v2-session"
    private static let account = "current-session"
    private static let prefix: [UInt8] = [77, 71, 75, 67, 65, 67, 72, 69, 1]

    private static func archiveFingerprint() -> [UInt8]? {
        guard let folder = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { return nil }
        let path = (folder as NSString).appendingPathComponent("MagnistraSession.mgsession")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              data.count >= 84, data.count <= 8 * 1024 * 1024,
              data.starts(with: [77, 71, 83, 69, 83, 83, 73, 79, 78, 50, 0, 0]) else { return nil }
        var digest = [UInt8](repeating: 0, count: 32)
        let result = digest.withUnsafeMutableBufferPointer { dst in
            data.withUnsafeBytes { src -> Int32 in
                return magnistraV2Sha256(dst.baseAddress,
                         src.bindMemory(to: UInt8.self).baseAddress,
                         UInt64(data.count))
            }
        }
        return result == 0 ? digest : nil
    }

    private static func keychainQuery() -> [String: Any] {
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account]
    }

    static func remember(_ payload: Data) -> Bool {
        guard !payload.isEmpty, payload.count <= 8 * 1024 * 1024,
              let digest = archiveFingerprint() else { return false }
        var value = Data(prefix)
        value.append(contentsOf: digest)
        value.append(payload)
        var update: [String: Any] = [kSecValueData as String: value]
        let query = keychainQuery()
        var result = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if result == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = value
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            result = SecItemAdd(add as CFDictionary, nil)
        }
        update.removeAll()
        return result == errSecSuccess
    }

    static func restoreIfAvailable() -> Bool {
        guard let currentDigest = archiveFingerprint() else { return false }
        var query = keychainQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef? = nil
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let stored = item as? Data,
              stored.count > prefix.count + 32,
              stored.count <= prefix.count + 32 + 8 * 1024 * 1024,
              stored.starts(with: prefix),
              Array(stored[prefix.count..<(prefix.count + 32)]) == currentDigest
        else { return false }
        let payload = stored.subdata(in: (prefix.count + 32)..<stored.count)

        guard let object = try? JSONSerialization.jsonObject(with: payload, options: []),
              let archive = object as? [String: Any],
              archive["format"] as? String == "magnistra-session-v1",
              let profile = archive["profile"] as? [String: Any],
              let agent = profile["userAgent"] as? String, !agent.isEmpty,
              let items = archive["cookies"] as? [[String: Any]],
              items.count > 0, items.count <= 5000 else { return false }
        var cookies: [HTTPCookie] = []
        var hasSession = false
        var hasCSRF = false
        let now = Date().timeIntervalSince1970
        for entry in items {
            guard let name = entry["name"] as? String, !name.isEmpty,
                  let value = entry["value"] as? String,
                  let domain = entry["domain"] as? String else { return false }
            let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard host == "instagram.com" || host.hasSuffix(".instagram.com") else { return false }
            if let expiry = entry["expires"] as? NSNumber,
               expiry.doubleValue > 0 && expiry.doubleValue <= now { continue }
            if name == "sessionid" && !value.isEmpty { hasSession = true }
            if name == "csrftoken" && !value.isEmpty { hasCSRF = true }
            let path = (entry["path"] as? String) ?? "/"
            guard path.hasPrefix("/") else { return false }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path
            ]
            if entry["secure"] as? Bool == true { properties[.secure] = "TRUE" }
            if entry["httpOnly"] as? Bool == true {
                properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
            }
            if let expiry = entry["expires"] as? NSNumber, expiry.doubleValue > 0 {
                properties[.expires] = Date(timeIntervalSince1970: expiry.doubleValue)
            }
            guard let cookie = HTTPCookie(properties: properties) else { return false }
            cookies.append(cookie)
        }
        guard hasSession, hasCSRF, !cookies.isEmpty else { return false }
        let store = HTTPCookieStorage.shared
        for cookie in cookies { store.setCookie(cookie) }
        install(payload)
        return true
    }
    static func install(_ payload: Data) {
        lock.lock()
        sessionPayload = payload
        lock.unlock()
    }
    static func snapshot() -> Data? {
        lock.lock()
        let payload = sessionPayload
        lock.unlock()
        return payload
    }
}

private enum MagnistraV2LoginBridge {

    private static func readBE32(_ bytes: Data, _ index: Int) -> Int {
        let a = [UInt8](bytes[index..<(index + 4)])
        return (Int(a[0]) << 24) | (Int(a[1]) << 16) | (Int(a[2]) << 8) | Int(a[3])
    }
    private static func validInstagramDomain(_ domain: String) -> Bool {
        let d = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return d == "instagram.com" || d.hasSuffix(".instagram.com")
    }
    static func decryptSession(username: String, password: String) -> MagnistraV2UnlockedArchive? {
        let normalizedUser = username.precomposedStringWithCanonicalMapping
        let normalizedPassword = password.precomposedStringWithCanonicalMapping
        if normalizedUser.isEmpty || normalizedPassword.isEmpty { return nil }
        guard let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { return nil }
        let file = (docs as NSString).appendingPathComponent("MagnistraSession.mgsession")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file),
              let size = attrs[FileAttributeKey.size] as? NSNumber,
              size.intValue > 84 && size.intValue <= 8 * 1024 * 1024,
              let encrypted = try? Data(contentsOf: URL(fileURLWithPath: file)) else { return nil }
        var decrypted: UnsafeMutablePointer<UInt8>? = nil
        var decryptedLength: Int = 0
        let status = encrypted.withUnsafeBytes { raw -> Int32 in
            let buffer = raw.bindMemory(to: UInt8.self)
            return normalizedUser.withCString { u in
                normalizedPassword.withCString { p in
                    magnistraV2NativeOpen(buffer.baseAddress, encrypted.count, u, p,
                                         &decrypted, &decryptedLength)
                }
            }
        }
        guard status == 0, let decoded = decrypted, decryptedLength >= 17,
              decryptedLength <= 8 * 1024 * 1024 else {
            if let buffer = decrypted { magnistraV2NativeRelease(UnsafeMutableRawPointer(buffer), decryptedLength) }
            return nil
        }
        let unwrapped = Data(bytes: decoded, count: decryptedLength)
        magnistraV2NativeRelease(UnsafeMutableRawPointer(decoded), decryptedLength)
        guard unwrapped.starts(with: [77, 71, 83, 80, 65, 89, 50, 0]),
              unwrapped[8] == 1 else { return nil }
        let metaSize = readBE32(unwrapped, 9)
        let payloadSize = readBE32(unwrapped, 13)
        guard metaSize >= 2, metaSize <= 65536, payloadSize > 0,
              metaSize + payloadSize + 17 == unwrapped.count else { return nil }
        let metadataBytes = unwrapped.subdata(in: 17..<(17 + metaSize))
        let payloadBytes = unwrapped.subdata(in: (17 + metaSize)..<unwrapped.count)
        guard let metadata = (try? JSONSerialization.jsonObject(with: metadataBytes, options: [])) as? [String: Any],
              let payload = (try? JSONSerialization.jsonObject(with: payloadBytes, options: [])) as? [String: Any],
              payload["format"] as? String == "magnistra-session-v1",
              let profile = payload["profile"] as? [String: Any],
              let agent = profile["userAgent"] as? String,
              !agent.isEmpty,
              let rawCookies = payload["cookies"] as? [[String: Any]],
              !rawCookies.isEmpty, rawCookies.count <= 5000 else { return nil }
        if let origin = metadata["origin"] as? String,
           let url = URL(string: origin), let host = url.host {
            if !validInstagramDomain(host) || url.scheme?.lowercased() != "https" { return nil }
        } else if metadata["origin"] != nil { return nil }
        if let provider = metadata["provider"] as? String,
           provider.lowercased() != "instagram" { return nil }
        if let kind = metadata["schema"] as? String,
           kind != "magnistra-session-v1" { return nil }
        var cookies: [HTTPCookie] = []
        var hasSessionID = false
        var hasCSRF = false
        let now = Date().timeIntervalSince1970
        for item in rawCookies {
            guard let name = item["name"] as? String, !name.isEmpty,
                  let value = item["value"] as? String,
                  let domain = item["domain"] as? String,
                  validInstagramDomain(domain) else { return nil }
            if let expires = item["expires"] as? NSNumber,
               expires.doubleValue > 0, expires.doubleValue <= now { continue }
            if name == "sessionid" && !value.isEmpty { hasSessionID = true }
            if name == "csrftoken" && !value.isEmpty { hasCSRF = true }
            let path = (item["path"] as? String) ?? "/"
            guard path.hasPrefix("/") else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path
            ]
            if item["secure"] as? Bool == true { properties[.secure] = "TRUE" }
            if item["httpOnly"] as? Bool == true { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let expiry = item["expires"] as? Double, expiry > 0 {
                properties[.expires] = Date(timeIntervalSince1970: expiry)
            }
            guard let cookie = HTTPCookie(properties: properties) else { return nil }
            cookies.append(cookie)
        }
        guard hasSessionID, hasCSRF, !cookies.isEmpty else { return nil }
        return MagnistraV2UnlockedArchive(cookies: cookies, payload: payloadBytes)
    }
}

final class MagnistraInitialAuthViewController: UIViewController, UITextFieldDelegate, UIGestureRecognizerDelegate {
    private let gradientHeader = UIView(frame: .zero)
    private let gradientBase = CAGradientLayer()
    private let gradientAccent = CAGradientLayer()
    private let wordmark = UIImageView(frame: .zero)
    private let intro = UILabel(frame: .zero)
    private let importTab = UIButton(type: .custom)
    private let loginTab = UIButton(type: .custom)
    private let pointer = MagnistraLoginPointer(frame: .zero)

    private let whiteFooter = UIView(frame: .zero)
    private let formScroll = UIScrollView(frame: .zero)
    private let loginForm = UIView(frame: .zero)
    private let importForm = UIView(frame: .zero)
    private let mgxTransferLanding = MagnistraTransferLanding(frame: CGRect.zero)
    private let username = UITextField(frame: .zero)
    private let password = UITextField(frame: .zero)
    private let usernameRule = UIView(frame: .zero)
    private let passwordRule = UIView(frame: .zero)
    private let forgotButton = UIButton(type: .custom)
    private let loginButton = UIButton(type: .custom)
    private var selectedTab = 1
    private var keyboardTop: CGFloat? = nil
    private var previousStatusHidden: Bool? = nil
    private var hasPreparedUI = false

    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if previousStatusHidden == nil { previousStatusHidden = UIApplication.shared.isStatusBarHidden }
        UIApplication.shared.setStatusBarHidden(false, with: .none)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let major = (UIDevice.current.systemVersion as NSString).integerValue
        if major == 5 || major == 6 {
            MagnistraLegacyClearStatusBarRenderer.shared.apply(on: view)
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let value = previousStatusHidden {
            UIApplication.shared.setStatusBarHidden(value, with: .none)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let statusMajor = (UIDevice.current.systemVersion as NSString).integerValue
        if statusMajor == 5 || statusMajor == 6 {
            let setter = NSSelectorFromString("setWantsFullScreenLayout:")
            if responds(to:setter) {
                setValue(NSNumber(value:true),forKey:"wantsFullScreenLayout")
            }
        }
        view.backgroundColor = .white
        gradientHeader.backgroundColor = .clear
        gradientHeader.clipsToBounds = true
        view.addSubview(gradientHeader)

        let magnistraBlue = UIColor(red: 10.0 / 255.0,
                                   green: 93.0 / 255.0,
                                   blue: 144.0 / 255.0, alpha: 1)
        gradientHeader.backgroundColor = magnistraBlue
        gradientBase.colors = [magnistraBlue.cgColor, magnistraBlue.cgColor]
        gradientBase.locations = [0.0, 1.0]
        gradientBase.startPoint = CGPoint(x: 0, y: 0)
        gradientBase.endPoint = CGPoint(x: 1, y: 1)
        gradientHeader.layer.addSublayer(gradientBase)
        gradientAccent.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor]
        gradientAccent.locations = [0.0, 1.0]
        gradientHeader.layer.addSublayer(gradientAccent)

        if let path = Bundle.main.path(forResource: "MagnistraLoginWordmark", ofType: "png"),
           let image = UIImage(contentsOfFile: path) {
            wordmark.image = image
        } else {

            let fallback = UILabel(frame: .zero)
            fallback.text = "Magnistra"
            fallback.textColor = .white
            fallback.textAlignment = .center
            fallback.font = UIFont(name: "SnellRoundhand-Bold", size: 42) ?? UIFont.boldSystemFont(ofSize: 38)
            gradientHeader.addSubview(fallback)
            fallback.tag = 99330
        }
        wordmark.contentMode = .scaleAspectFit
        wordmark.backgroundColor = .clear
        gradientHeader.addSubview(wordmark)
        intro.backgroundColor = .clear
        intro.text = "Log in to see photos and videos\nfrom your friends."
        intro.numberOfLines = 2
        intro.font = UIFont.systemFont(ofSize: 13)
        intro.textColor = .white
        intro.textAlignment = .center
        gradientHeader.addSubview(intro)

        configureTab(importTab, "IMPORT", #selector(selectImport))
        configureTab(loginTab, "LOG IN", #selector(selectLogin))
        gradientHeader.addSubview(importTab)
        gradientHeader.addSubview(loginTab)
        gradientHeader.addSubview(pointer)

        whiteFooter.backgroundColor = .white
        view.addSubview(whiteFooter)
        formScroll.backgroundColor = .white
        formScroll.alwaysBounceVertical = false
        formScroll.showsVerticalScrollIndicator = false
        formScroll.showsHorizontalScrollIndicator = false
        whiteFooter.addSubview(formScroll)
        formScroll.addSubview(loginForm)
        formScroll.addSubview(importForm)
        mgxTransferLanding.host = self
        importForm.addSubview(mgxTransferLanding)
        loginForm.backgroundColor = .white
        importForm.backgroundColor = .white

        configureField(username, placeholder: "Username", isPassword: false)
        configureField(password, placeholder: "Password", isPassword: true)
        loginForm.addSubview(username)
        loginForm.addSubview(password)
        configureRule(usernameRule, in: loginForm)
        configureRule(passwordRule, in: loginForm)
        configureLink(forgotButton, "Forgot?", #selector(forgotPressed))
        configureAction(loginButton, "Log In", #selector(loginPressed))
        loginForm.addSubview(forgotButton)
        loginForm.addSubview(loginButton)

        let outsideTap = UITapGestureRecognizer(target: self, action: #selector(tapOutsideField))
        outsideTap.cancelsTouchesInView = false
        outsideTap.delegate = self
        formScroll.addGestureRecognizer(outsideTap)
        let headerTap = UITapGestureRecognizer(target: self, action: #selector(tapOutsideField))
        headerTap.cancelsTouchesInView = false
        headerTap.delegate = self
        gradientHeader.addGestureRecognizer(headerTap)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
             name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
             name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
             name: UIResponder.keyboardWillHideNotification, object: nil)
        hasPreparedUI = true
        applySelectedTab()
    }

    private func configureTab(_ button: UIButton, _ title: String, _ selector: Selector) {
        button.backgroundColor = .clear
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont(name: "HelveticaNeue-Bold", size: 14.5)
            ?? UIFont.boldSystemFont(ofSize: 14.5)
        button.addTarget(self, action: selector, for: .touchUpInside)
    }
    private func configureField(_ field: UITextField, placeholder: String, isPassword: Bool) {
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.placeholder = placeholder
        field.textAlignment = .left
        field.contentVerticalAlignment = .center
        field.font = UIFont.systemFont(ofSize: 15)
        field.textColor = UIColor(white: 0.28, alpha: 1)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.isSecureTextEntry = isPassword
        field.clearButtonMode = .whileEditing
        field.returnKeyType = isPassword ? .done : .next
        field.delegate = self
    }
    private func configureRule(_ line: UIView, in panel: UIView) {
        line.backgroundColor = UIColor(white: 0.87, alpha: 1)
        line.isUserInteractionEnabled = false
        panel.addSubview(line)
    }
    private func configureLink(_ button: UIButton, _ title: String, _ selector: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        button.setTitleColor(UIColor(red: 0.29, green: 0.53, blue: 0.78, alpha: 1), for: .normal)
        button.addTarget(self, action: selector, for: .touchUpInside)
    }
    private func configureAction(_ button: UIButton, _ title: String, _ selector: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont(name: "HelveticaNeue-Bold", size: 15)
            ?? UIFont.boldSystemFont(ofSize: 15)
        button.setTitleColor(UIColor(red: 0.29, green: 0.53, blue: 0.78, alpha: 1), for: .normal)
        button.addTarget(self, action: selector, for: .touchUpInside)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let major = (UIDevice.current.systemVersion as NSString).integerValue
        if major == 5 || major == 6 {
            MagnistraLegacyClearStatusBarRenderer.shared.apply(on: view)
        }
        guard hasPreparedUI else { return }
        let width = view.bounds.width
        let height = view.bounds.height
        if width < 1 || height < 1 { return }

        let footerHeight: CGFloat = min(265, max(140, height - 180))
        let topHeight = height - footerHeight
        gradientHeader.frame = CGRect(x: 0, y: 0, width: width, height: topHeight)
        gradientBase.frame = gradientHeader.bounds
        gradientAccent.frame = gradientHeader.bounds
        whiteFooter.frame = CGRect(x: 0, y: topHeight, width: width, height: footerHeight)

        let tabHeight: CGFloat = 48
        let brandingHeight = topHeight - tabHeight

        let wordWidth = min(width * 0.475, 188)
        let wordHeight: CGFloat = min(65, max(34, wordWidth * CGFloat(572.0 / 1827.0)))
        let clusterHeight = wordHeight + 38

        let idealTop = max(7, (brandingHeight - clusterHeight) * 0.58) + 9
        let clusterTop = min(idealTop, max(7, brandingHeight - clusterHeight - 7))
        wordmark.frame = CGRect(x: (width - wordWidth) / 2, y: clusterTop,
                                width: wordWidth, height: wordHeight)
        if let fallback = gradientHeader.viewWithTag(99330) {
            fallback.frame = wordmark.frame
        }
        intro.frame = CGRect(x: 18, y: clusterTop + wordHeight + 3,
                             width: width - 36, height: 38)
        importTab.frame = CGRect(x: 0, y: topHeight - tabHeight,
                                 width: width / 2, height: tabHeight)
        loginTab.frame = CGRect(x: width / 2, y: topHeight - tabHeight,
                                width: width / 2, height: tabHeight)
        let center = selectedTab == 1 ? width * 0.75 : width * 0.25
        pointer.frame = CGRect(x: center - 5, y: topHeight - 5, width: 10, height: 5)

        let visibleBottom = min(height, keyboardTop ?? height)
        let formViewport = max(1, visibleBottom - topHeight)
        formScroll.frame = CGRect(x: 0, y: 0, width: width, height: min(footerHeight, formViewport))
        formScroll.contentSize = CGSize(width: width, height: max(footerHeight, 215))
        loginForm.frame = CGRect(x: 0, y: 0, width: width, height: formScroll.contentSize.height)
        importForm.frame = loginForm.frame
        mgxTransferLanding.frame = importForm.bounds
        let insetX: CGFloat = 22
        let ruleX: CGFloat = 14
        let ruleWidth = width - ruleX * 2
        let point = 1.0 / max(1, UIScreen.main.scale)

        username.frame = CGRect(x: insetX, y: 8, width: width - insetX * 2, height: 36)
        password.frame = CGRect(x: insetX, y: 60, width: width - insetX - 91, height: 36)
        forgotButton.frame = CGRect(x: width - 79, y: 62, width: 69, height: 33)
        usernameRule.frame = CGRect(x: ruleX, y: 52, width: ruleWidth, height: point)
        passwordRule.frame = CGRect(x: ruleX, y: 104, width: ruleWidth, height: point)
        loginButton.frame = CGRect(x: 20, y: max(129, footerHeight - 58), width: width - 40, height: 40)

    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let boxed = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        let local = view.convert(boxed.cgRectValue, from: nil)
        let overlap = view.bounds.intersection(local)
        keyboardTop = overlap.isNull ? nil : max(0, overlap.minY)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        makeActiveFieldVisible()
    }
    @objc private func keyboardWillHide(_ note: Notification) {
        keyboardTop = nil
        view.setNeedsLayout()
        view.layoutIfNeeded()
        formScroll.setContentOffset(.zero, animated: true)
    }
    private func makeActiveFieldVisible() {
        for field in [username, password] where field.isFirstResponder {
            let frame = field.convert(field.bounds, to: formScroll).insetBy(dx: 0, dy: -6)
            formScroll.scrollRectToVisible(frame, animated: true)
            break
        }
    }
    func textFieldDidBeginEditing(_ textField: UITextField) { makeActiveFieldVisible() }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === username { password.becomeFirstResponder() }
        else { textField.resignFirstResponder() }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        return !(touch.view is UIControl)
    }
    @objc private func tapOutsideField() { view.endEditing(true) }
    private func applySelectedTab() {
        loginForm.isHidden = selectedTab != 1
        importForm.isHidden = selectedTab != 0
        formScroll.setContentOffset(.zero, animated: false)
        view.setNeedsLayout()
    }
    @objc private func selectImport() { view.endEditing(true); selectedTab = 0; applySelectedTab() }
    @objc private func selectLogin() { view.endEditing(true); selectedTab = 1; applySelectedTab() }
    @objc private func forgotPressed() {
        view.endEditing(true)
        showMessage("Use LegacyRelay on a supported device to authenticate and export a session.")
    }
    @objc private func loginPressed() {
        view.endEditing(true)
        guard let user = username.text, !user.isEmpty,
              let pass = password.text, !pass.isEmpty else {
            showMessage("Enter the username and password used to encrypt this LegacyRelay session.")
            return
        }
        loginButton.isEnabled = false
        loginButton.setTitle("Unlocking…", for: .normal)

        let request: NSDictionary = ["username": user, "password": pass]
        Thread.detachNewThreadSelector(#selector(v2UnlockBackground(_:)),
                                       toTarget: self, with: request)
    }
    @objc private func v2UnlockBackground(_ request: NSDictionary) {
        let archive: MagnistraV2UnlockedArchive?
        if let user = request["username"] as? String,
           let pass = request["password"] as? String {
            archive = MagnistraV2LoginBridge.decryptSession(username: user, password: pass)
        } else {
            archive = nil
        }

        let response: NSDictionary
        if let unlocked = archive {
            response = ["cookies": unlocked.cookies as NSArray,
                        "payload": unlocked.payload as NSData]
        } else {
            response = [:]
        }
        performSelector(onMainThread: #selector(v2UnlockFinished(_:)),
                        with: response, waitUntilDone: false)
    }
    @objc private func v2UnlockFinished(_ response: NSDictionary) {
        loginButton.isEnabled = true
        loginButton.setTitle("Log In", for: .normal)
        guard let cookies = response["cookies"] as? [HTTPCookie], !cookies.isEmpty,
              let payload = response["payload"] as? Data, !payload.isEmpty else {
            showMessage("Could not unlock MagnistraSession.mgsession. Check the archive credentials and file integrity.")
            return
        }

        let savedForNextLaunch = MagnistraV2SessionCache.remember(payload)
        MagnistraV2SessionCache.install(payload)
        if !savedForNextLaunch {
            NSLog("MAGNISTRA_V2_KEYCHAIN_SAVE_FAILED; SESSION_REMAINS_ACTIVE_THIS_LAUNCH")
        }
        let store = HTTPCookieStorage.shared
        for cookie in cookies { store.setCookie(cookie) }
        password.text = nil
        let root = presentingViewController as? RootViewController
        dismiss(animated: false, completion: {

            guard let navigation = root?.selectedViewController as? UINavigationController else { return }
            (navigation.topViewController as? HomeViewController)?.magnistraV2ReloadAfterLogin()
            (navigation.topViewController as? ExploreViewController)?.magnistraV2ReloadAfterLogin()
        })
    }
    private func showMessage(_ value: String) {
        UIAlertView(title: "Magnistra", message: value,
                    delegate: nil, cancelButtonTitle: "OK").show()
    }
}

private func magnistraBlueNavImage() -> UIImage {
    let size = CGSize(width: 2.0, height: 2.0)
    UIGraphicsBeginImageContextWithOptions(size, true, 0.0)
    UIColor(red: 10.0 / 255.0, green: 93.0 / 255.0,
            blue: 144.0 / 255.0, alpha: 1.0).setFill()
    UIRectFill(CGRect(origin: CGPoint.zero, size: size))
    let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    UIGraphicsEndImageContext()
    return image.resizableImage(withCapInsets: .zero)
}

func magnistraApplyBlueNavigationBars(_ controllers: [UIViewController]?) {
    let image = magnistraBlueNavImage()
    UINavigationBar.appearance().setBackgroundImage(image, for: .default)
    for controller in controllers ?? [] {
        if let nav = controller as? UINavigationController {
            nav.navigationBar.setBackgroundImage(image, for: .default)
            nav.navigationBar.backgroundColor = instaBlue()
            nav.view.backgroundColor = instaBlue()
        } else if let tabs = controller as? UITabBarController {
            for child in tabs.viewControllers ?? [] {
                if let nav = child as? UINavigationController {
                    nav.navigationBar.setBackgroundImage(image, for: .default)
            nav.navigationBar.backgroundColor = instaBlue()
            nav.view.backgroundColor = instaBlue()
                }
            }
        }
    }
}

