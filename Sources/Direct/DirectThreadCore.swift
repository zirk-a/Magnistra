// Overview: Direct thread: the main view controller (lifecycle, layout and setup).
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

final class MagnistraDirectThreadViewController:
    UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIActionSheetDelegate, UIAlertViewDelegate , UIGestureRecognizerDelegate {

    var matrixSilentRefresh = false

    var firstOpenReconciled = false
    var loadWasSilent = false
    var loadWasNearBottom = false
    var matrixRefreshQueued = false
    var magnistraDirectHistoryCursor: String? = nil
    var magnistraDirectHasOlder = false

    var silentPollRequested = false
    var deferredIncomingMessages: [MagnistraDirectMessage] = []
    var deferredThreadTitle: String? = nil
    var lastFetchedPageIDs: [String] = []
    var magnistraDirectLoadingOlder = false
    var magnistraDirectOlderRetryAfter: TimeInterval = 0
    var magnistraDirectLiveTimer: Timer? = nil
    var magnistraDirectInitialPageReceived = false
    var matrixTimelineCursor: String? = nil
    var matrixTimelineHasOlder = false
    var matrixTimelineInitialized = false
    var matrixOlderLoading = false
    var matrixOlderRetryAfter: TimeInterval = 0
    var matrixOlderArmed = true
    var magnistraDirectOpeningShared = Set<String>()

    let chatThumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 72
        cache.totalCostLimit = 20 * 1024 * 1024
        return cache
    }()

    var magnistraPendingStickerSaveIndex: Int = -1

    var magnistraRecordedVoiceLevels: [Double] = []

    let pullRefreshGesture = MagnistraPullRefreshGesture()
    let pullRefreshIndicator = MagnistraNavigationPullIndicator()

    var summary:
        MagnistraDirectThreadSummary

    var matrixMemberNames: [String: String] = [:]
    var matrixGroupConfirmed = false

    let tableView =
        UITableView(
            frame:
                CGRect.zero,
            style:
                .plain
        )

    let composerMicButton = UIButton(type: .custom)

    let composerCameraButton = UIButton(type: .custom)

    let composerFadeLayer = CAGradientLayer()
    var keepKeyboardDuringVoice = false
    let composerPhotoButton = UIButton(type: .custom)
    let composerStickerButton = UIButton(type: .custom)
    let voiceRecordBand = UIView()
    let voiceTrashDisk = UIView()
    let voiceTrashIcon = UIImageView()
    let voiceDurationLabel = UILabel()
    var voiceRecordingDots: [UIView] = []
    var voiceHoldGesture: UILongPressGestureRecognizer?
    var isRecordingVoice = false
    var voiceCancelArmed = false
    var voiceRecordingStartDate: Date?
    var voiceRefreshTimer: Timer?

    var inlineWebVoiceRecording = false

    let composerBar =
        UIView()

    let composerTopBorder =
        UIView()

    let messageFieldShell =
        UIView()

    let messageView =
        UITextView()

    let messagePlaceholder =
        UILabel()

    let attachButton =
        UIButton(
            type:
                .custom
        )

    let voiceStatusLabel =
        UILabel()

    let magnistraVoiceToggleButton = UIButton(type: .custom)

    var pendingPickerMode =
        ""

    var outgoingVoiceRecorder:
        AVAudioRecorder?

    var outgoingVoiceURL:
        URL?

    var outgoingVoiceTimer:
        Timer?

    var outgoingVoiceStartedAt:
        Date?

    var voiceDurationMS = 0

    var outgoingVoiceMode =
        false

    var outgoingVoiceReady =
        false

    let sendButton =
        UIButton(
            type:
                .custom
        )

    let composerMinHeight:
        CGFloat =
            52.0

    let composerMaxHeight:
        CGFloat =
            144.0

    var composerHeight:
        CGFloat =
            52.0

    var keyboardHeight:
        CGFloat =
            0.0

    var keyboardKeepsBottomPinned =
        false

    let directAudioQueue:
        OperationQueue =
            {
                let queue =
                    OperationQueue()

                queue.maxConcurrentOperationCount =
                    1

                return queue
            }()

    var directAudioPlayer:
        AVAudioPlayer?

    var directAudioMessageID =
        ""

    var directAudioProgressTimer:
        Timer?

    var directAudioRequestToken =
        ""

    lazy var keyboardDismissTap:
        UITapGestureRecognizer =
            {
                let tap =
                    UITapGestureRecognizer(
                        target:
                            self,
                        action:
                            #selector(
                                dismissKeyboardFromChat
                            )
                    )

                tap.cancelsTouchesInView =
                    false

                return tap
            }()

    let loadQueue =
        OperationQueue()

    var daySeparatorIndexes: [Int] = []
    var cachedRowHeights: [IndexPath: CGFloat] = [:]
    var cachedRowWidth: CGFloat = -1.0
    var observedGIFGeometryVersion = -1

    var olderPullArmed = true
    var olderLoadPending = false

    var messages: [MagnistraDirectMessage] = [] {
        didSet {
            var starts: [Int] = []
            if !messages.isEmpty {
                starts.append(0)
                if messages.count > 1 {
                    for index in 1..<messages.count {
                        if magnistraDirectShowsDate(at: index) {
                            starts.append(index)
                        }
                    }
                }
            }
            daySeparatorIndexes = starts
            cachedRowHeights.removeAll(keepingCapacity: true)
        }
    }

    var loading =
        false

    var sending =
        false

    let reuseID =
        "MagnistraDirectMessageCell"

    var usesMatrixBackend: Bool {
        return summary.threadFBID.hasPrefix("!")
    }

    var audioPlayer:
        AVAudioPlayer?

    let magnistraDirectTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    let magnistraDirectDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    let magnistraDirectDayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var magnistraDirectHorizontalPan: UIPanGestureRecognizer?
    var magnistraDirectTimestampReveal: CGFloat = 0.0
    let magnistraDirectTimeTag = 913701
    let magnistraDirectDateTag = 913702

    var magnistraDirectIsMatrix: Bool {
        return summary.threadFBID.hasPrefix("!")
    }

    init(
        summary:
            MagnistraDirectThreadSummary
    ) {
        self.summary =
            summary

        super.init(
            nibName:
                nil,
            bundle:
                nil
        )

        loadQueue.maxConcurrentOperationCount =
            1

        hidesBottomBarWhenPushed =
            true
    }

    required init?(
        coder:
            NSCoder
    ) {
        return nil
    }

    var magnistraWebRecorder: AVAudioRecorder?
    var magnistraWebRecordingURL: URL?
    var magnistraWebVoiceWaveform = [Double]()
    var magnistraWebMeterTimer: Timer?
    var magnistraWebSending = false

override func viewDidLoad() {
        tableView.separatorStyle = .none
        tableView.separatorColor = UIColor.clear
        tableView.sectionHeaderHeight = 0.0
        tableView.sectionFooterHeight = 0.0

        let revealPan = UIPanGestureRecognizer(target: self,
                            action: #selector(magnistraDirectTimestampPullChanged(_:)))
        revealPan.maximumNumberOfTouches = 1
        revealPan.cancelsTouchesInView = false
        revealPan.delegate = self
        magnistraDirectHorizontalPan = revealPan
        tableView.addGestureRecognizer(revealPan)

        super.viewDidLoad()

        title =
            summary.title

        view.backgroundColor =
            UIColor(
                white:
                    0.96,
                alpha:
                    1.0
            )

        tableView.dataSource =
            self

        tableView.delegate =
            self

        tableView.separatorStyle =
            .none
        tableView.separatorColor = UIColor.clear
        tableView.sectionFooterHeight = 0.0

        tableView.backgroundColor =
            UIColor(
                white:
                    0.96,
                alpha:
                    1.0
            )

        tableView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        view.addSubview(
            tableView
        )
        if usesMatrixBackend {

            pullRefreshGesture.install(on: tableView) { [weak self] in
                self?.loadMatrixOlder()
            }
        }

        tableView.addGestureRecognizer(
            keyboardDismissTap
        )

        composerBar.backgroundColor = instaBlue()

        composerBar.layer.shadowColor =
            UIColor.black.cgColor

        composerBar.layer.shadowOpacity =
            0.10

        composerBar.layer.shadowRadius =
            1.0

        composerBar.layer.shadowOffset =
            CGSize(
                width:
                    0.0,
                height:
                    -1.0
            )

        view.addSubview(
            composerBar
        )

        composerTopBorder.backgroundColor = UIColor(
            red: 0.176, green: 0.312, blue: 0.448, alpha: 1.0
        )

        composerBar.addSubview(
            composerTopBorder
        )

        attachButton.setTitle(
            "+",
            for:
                .normal
        )

        attachButton.setTitleColor(
            UIColor.white,
            for:
                .normal
        )

        attachButton.titleLabel?.font =
            UIFont.boldSystemFont(
                ofSize:
                    24.0
            )

        attachButton.addTarget(
            self,
            action:
                #selector(
                    attachTapped
                ),
            for:
                .touchUpInside
        )

        composerBar.addSubview(
            attachButton
        )

        voiceStatusLabel.backgroundColor =
            UIColor.clear

        voiceStatusLabel.textColor =
            UIColor(
                white:
                    0.35,
                alpha:
                    1.0
            )

        voiceStatusLabel.font =
            UIFont.systemFont(
                ofSize:
                    12.0
            )

        voiceStatusLabel.textAlignment =
            .left

        voiceStatusLabel.isHidden =
            true

        messageFieldShell.addSubview(
            voiceStatusLabel
        )

        messageFieldShell.backgroundColor =
            UIColor(
                white:
                    0.985,
                alpha:
                    1.0
            )

        messageFieldShell.layer.cornerRadius =
            7.0

        messageFieldShell.layer.borderWidth =
            1.0

        messageFieldShell.layer.borderColor =
            UIColor(
                white:
                    0.72,
                alpha:
                    1.0
            )
            .cgColor

        composerBar.addSubview(
            messageFieldShell
        )

        messageView.backgroundColor =
            UIColor.clear

        messageView.font =
            UIFont.systemFont(
                ofSize:
                    13.0
            )

        messageView.textColor =
            UIColor(
                white:
                    0.18,
                alpha:
                    1.0
            )

        messageView.returnKeyType =
            .default

        messageView.delegate =
            self

        messageView.isScrollEnabled =
            false

        messageView.showsVerticalScrollIndicator =
            false

        messageFieldShell.addSubview(
            messageView
        )

        messagePlaceholder.backgroundColor =
            UIColor.clear

        messagePlaceholder.text =
            "Message..."

        messagePlaceholder.textColor =
            UIColor(
                white:
                    0.60,
                alpha:
                    1.0
            )

        messagePlaceholder.font =
            UIFont.systemFont(
                ofSize:
                    13.0
            )

        messagePlaceholder.isUserInteractionEnabled =
            false

        messageFieldShell.addSubview(
            messagePlaceholder
        )

        magnistraVoiceToggleButton.backgroundColor = UIColor.clear
        magnistraVoiceToggleButton.setTitleColor(
            UIColor(red: 0.176, green: 0.312, blue: 0.448, alpha: 1.0),
            for: .normal
        )
        magnistraVoiceToggleButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13.0)
        magnistraVoiceToggleButton.setTitle("Start", for: .normal)
        magnistraVoiceToggleButton.isHidden = true
        magnistraVoiceToggleButton.accessibilityLabel = "Start voice recording"
        magnistraVoiceToggleButton.addTarget(
            self,
            action: #selector(magnistraVoiceToggleTapped),
            for: .touchUpInside
        )
        messageFieldShell.addSubview(magnistraVoiceToggleButton)

        sendButton.setTitle(
            "Send",
            for:
                .normal
        )

        sendButton.setTitleColor(
            UIColor.white,
            for:
                .normal
        )

        sendButton.setTitleColor(
            UIColor.white,
            for:
                .disabled
        )

        sendButton.titleLabel?
            .font =
                UIFont.boldSystemFont(
                    ofSize:
                        12.5
                )

        sendButton.backgroundColor = UIColor(
            red: 0.176, green: 0.312, blue: 0.448, alpha: 1.0
        )

        sendButton.layer.cornerRadius =
            6.0

        sendButton.layer.borderWidth =
            1.0

        sendButton.layer.borderColor =
            UIColor(
                red:
                    0.10,
                green:
                    0.39,
                blue:
                    0.66,
                alpha:
                    1.0
            )
            .cgColor

        sendButton.isEnabled =
            false

        sendButton.alpha =
            1.0

        sendButton.addTarget(
            self,
            action:
                #selector(
                    sendTapped
                ),
            for:
                .touchUpInside
        )

        composerBar.addSubview(
            sendButton
        )
        setupComposer()

        showStatus(
            "Loading messages..."
        )

        loadThread()
        loadMatrixGroupNames()

        if !magnistraDirectIsMatrix {
            if !summary.isGroupConversation {
                let profile = MagnistraDirectProfileButton(type: .custom)
                profile.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
                profile.backgroundColor = UIColor.clear
                profile.accessibilityLabel = "Open Instagram profile"
                profile.addTarget(self, action: #selector(magnistraDirectProfileTapped), for: .touchUpInside)
                navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: profile)]
            } else {
                navigationItem.rightBarButtonItems = nil
            }
        } else {

            let info = MagnistraDirectProfileButton(type: .custom)
            info.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
            info.backgroundColor = UIColor.clear
            info.accessibilityLabel = "Room participants"
            info.addTarget(self, action: #selector(matrixMembersTapped),
                           for: .touchUpInside)
            navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: info)]
        }

}

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let bounds =
            view.bounds

        let composerY =
            max(
                0.0,
                bounds.size.height -
                keyboardHeight -
                composerHeight
            )

        composerBar.frame =
            CGRect(
                x:
                    0.0,
                y:
                    composerY,
                width:
                    bounds.size.width,
                height:
                    composerHeight
            )

        composerTopBorder.frame =
            CGRect(
                x:
                    0.0,
                y:
                    0.0,
                width:
                    composerBar.bounds.size.width,
                height:
                    1.0
            )

        voiceStatusLabel.frame =
            CGRect(
                x:
                    8.0,
                y:
                    5.0,
                width:
                    max(
                        1.0,
                        messageFieldShell.bounds.size.width -
                        16.0
                    ),
                height:
                    max(
                        20.0,
                        messageFieldShell.bounds.size.height -
                        10.0
                    )
            )

        magnistraVoiceToggleButton.frame = messageFieldShell.bounds

        layoutComposer()

        tableView.frame =
            CGRect(
                x:
                    0.0,
                y:
                    0.0,
                width:
                    bounds.size.width,
                height:
                    max(
                        0.0,
                        composerY + composerHeight
                    )
            )

        let currentInset = tableView.contentInset
        if abs(currentInset.bottom - composerHeight) > 0.5 {
            tableView.contentInset = UIEdgeInsets(top: currentInset.top,
                                                   left: currentInset.left,
                                                   bottom: composerHeight,
                                                   right: currentInset.right)
        }
        let indicatorInset = tableView.scrollIndicatorInsets
        if abs(indicatorInset.bottom - composerHeight) > 0.5 {
            tableView.scrollIndicatorInsets = UIEdgeInsets(top: indicatorInset.top,
                                                            left: indicatorInset.left,
                                                            bottom: composerHeight,
                                                            right: indicatorInset.right)
        }
    }

    override func viewWillAppear(
        _ animated: Bool
    ) {
        super.viewWillAppear(
            animated
        )
        KeyboardPreferences.apply(to: messageView)

        NotificationCenter.default
            .addObserver(
                self,
                selector:
                    #selector(
                        keyboardWillShow
                    ),
                name:
                    UIResponder
                        .keyboardWillShowNotification,
                object:
                    nil
            )

        NotificationCenter.default
            .addObserver(
                self,
                selector:
                    #selector(
                        keyboardWillHide
                    ),
                name:
                    UIResponder
                        .keyboardWillHideNotification,
                object:
                    nil
            )
        if usesMatrixBackend {
            NotificationCenter.default.removeObserver(
                self, name: Notification.Name("MagnistraMatrixRoomsUpdated"), object: nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(matrixSyncUpdate(_:)),
                name: Notification.Name("MagnistraMatrixRoomsUpdated"), object: nil)
            NotificationCenter.default.removeObserver(
                self, name: MatrixE2EEManager.liveDecryptedEventNotification, object: nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(matrixKeyUpdate(_:)),
                name: MatrixE2EEManager.liveDecryptedEventNotification, object: nil)
        }
        if !usesMatrixBackend {
        magnistraDirectOpeningShared.removeAll()
        magnistraDirectLiveTimer?.invalidate()

        magnistraDirectLiveTimer = Timer(
            timeInterval: 3.0,
            target: self,
            selector: #selector(magnistraDirectCheckNewMessages),
            userInfo: nil,
            repeats: true
        )
        if let liveTimer = magnistraDirectLiveTimer {
            RunLoop.main.add(liveTimer, forMode: .common)
        }
        NotificationCenter.default.removeObserver(
            self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(magnistraDirectLiveDidBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }
}

    var nativePickerAppearanceSuspended = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        (tabBarController as? RootViewController)?
            .showExistingStatusAbovePhotoPicker(false)
        if nativePickerAppearanceSuspended {
            nativePickerAppearanceSuspended = false
            magnistraApplyFlatTopBarButtonAppearance()
        }
    }

    override func viewWillDisappear(
        _ animated: Bool
    ) {
        NotificationCenter.default.removeObserver(
            self, name: UIApplication.didBecomeActiveNotification, object: nil)
        magnistraDirectLiveTimer?.invalidate()
        magnistraDirectLiveTimer = nil
        NotificationCenter.default.removeObserver(
            self, name: Notification.Name("MagnistraMatrixRoomsUpdated"), object: nil)
        NotificationCenter.default.removeObserver(
            self, name: MatrixE2EEManager.liveDecryptedEventNotification, object: nil)

        super.viewWillDisappear(
            animated
        )

        resumeDirectPreviewPresentation()

        NotificationCenter.default
            .removeObserver(
                self,
                name:
                    UIResponder
                        .keyboardWillShowNotification,
                object:
                    nil
            )

        NotificationCenter.default
            .removeObserver(
                self,
                name:
                    UIResponder
                        .keyboardWillHideNotification,
                object:
                    nil
            )

        messageView
            .resignFirstResponder()

        stopDirectAudioProgressTimer()

        directAudioRequestToken =
            ""

        directAudioPlayer?
            .stop()

        directAudioPlayer =
            nil

        directAudioMessageID =
            ""

        outgoingVoiceTimer?
            .invalidate()

        outgoingVoiceTimer =
            nil

        outgoingVoiceRecorder?
            .stop()

        outgoingVoiceRecorder =
            nil

        if
            let url =
                outgoingVoiceURL
        {
            try?
                FileManager.default
                    .removeItem(
                        at:
                            url
                    )
        }

        outgoingVoiceURL =
            nil

        outgoingVoiceMode =
            false

        outgoingVoiceReady =
            false
}

    var magnistraSavedStickerSending = false

    let magnistraIGCatalogSendQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()
}

