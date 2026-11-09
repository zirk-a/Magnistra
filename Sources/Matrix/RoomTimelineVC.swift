// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Room timeline screen: main view controller.
import Foundation
import UIKit
import Security
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import QuartzCore
import CoreText
import ImageIO
import SystemConfiguration



class RoomTimelineVC: UIViewController {

    var room: Room
    let client: MatrixAPIClient
    let syncEngine: SyncEngine

    var tableView: UITableView!
    var inputBar: UIView!
    var messageField: UITextView!
    var placeholderLabel: UILabel!
    var sendButton: UIButton!
    var attachButton: UIButton!
    var statusLabel: UILabel!

    let inputVPad: CGFloat = 9
    let inputMinHeight: CGFloat = 36
    let inputMaxHeight: CGFloat = 120
    let attachWidth: CGFloat = 34
    let sendWidth: CGFloat = 56
    let hMargin: CGFloat = 12
    let hSpacing: CGFloat = 8
    var currentFieldHeight: CGFloat = 36
    var keyboardHeight: CGFloat = 0

    var didInitialScroll = false

    var keepInitialBackfillAtBottom = false

    var typingLabel: UILabel!
    let typingBarHeight: CGFloat = 22

    var replyBar: UIView!
    var replyLabel: UILabel!
    var replyCancelButton: UIButton!
    let replyBarHeight: CGFloat = 30

    var uploadBar: UIView!
    var uploadLabel: UILabel!
    var uploadProgressView: UIProgressView!
    let uploadBarHeight: CGFloat = 30
    var typingUsers: [String] = []

    var lastTypingSent: TimeInterval = 0

    var memberNames: [String: String] = [:]
    var memberAvatars: [String: String] = [:]

    var othersReadEventIds = Set<String>()

    var events: [RoomEvent] = []
    var seenEventIds = Set<String>()
    var isLoadingBackfill = false
    var hasLoadedInitial = false
    var isSending = false

    var backfillFrom: String?
    var reachedHistoryStart = false

    var backfillHeader: UIView?
    var backfillSpinner: UIActivityIndicatorView?

    var pendingCopyText: String?

    var pendingReactionEventId: String?

    var pendingDeleteEventId: String?

    var pendingSaveSticker: (
        mxc: String,
        width: Int,
        height: Int,
        semanticGIF: Bool
    )?

    var pendingReplyTargetId: String?

    var replyingToEventId: String?
    var replyingToSender: String?
    var replyingToPreview: String?

    enum InputMode { case text, voice }
    var inputMode: InputMode = .text
    var voiceCancelButton: UIButton!
    var voiceRecordButton: UIButton!
    var audioRecorder: AVAudioRecorder?
    var voiceRecordingURL: URL?
    var voiceRecordTimer: Timer?
    var voiceRecordSeconds: Int = 0
    var voiceHasRecording = false
    var voiceIsRecording = false

    var audioPlayer: AVAudioPlayer?
    var playingAudioMxc: String?
    var audioProgressTimer: Timer?
    let audioCellId = "AudioEventCell"
    let fileCellId = "FileEventCell"
    let videoCellId = "VideoEventCell"

    var fileProgress: [String: Float] = [:]

    var docController: UIDocumentInteractionController?
    var moviePlayerVC: MPMoviePlayerViewController?

    var prefetchedMxcs = Set<String>()

    var prefetchRequests: [(mxc: String, w: Int, h: Int)] = []

    var syncListenerToken: Int?

    var revealOffset: CGFloat = 0

    static let maxReplyPull: CGFloat = 56
    static let replyTriggerDistance: CGFloat = 44
    var replySwipeEventId: String?
    var replySwipeArmed = false

    struct EventRow {
        let event: RoomEvent
        let showMeta: Bool

        let editedBody: String?
    }

    enum Row {
        case date(String)
        case event(EventRow)

        case receipt(String)

        case reactions(ReactionRow)

        case pending(PendingMessage)
    }
    struct ReactionRow {
        let targetEventId: String
        let items: [ReactionItem]
        let isOwn: Bool
    }
    var rows: [Row] = []

    enum PendingState { case sending, failed }
    struct PendingMessage {

        let txnId: String
        let body: String
        let replyTo: String?

        let timestamp: Int64
        var state: PendingState

        var eventId: String?

        var errorText: String? = nil
    }

    var pending: [PendingMessage] = []

    var isSendInFlight = false

    var pendingActionTxnId: String?

    var myReactions: [String: [String: String]] = [:]

    var eventsById: [String: RoomEvent] = [:]

    let cellId = "EventCell"
    let imageCellId = "ImageEventCell"
    let membershipCellId = "MembershipCell"
    let dateCellId = "DateCell"
    let reactionsCellId = "ReactionsCell"

    let reactionSheetTag = 93
    let deleteSheetTag = 94
    let pendingSheetTag = 96

    static let quickReactions = ["\u{1F44D}", "\u{2764}\u{FE0F}", "\u{1F602}",
                                             "\u{1F62E}", "\u{1F622}", "\u{1F389}"]

    init(room: Room, client: MatrixAPIClient, syncEngine: SyncEngine) {
        self.room = room
        self.client = client
        self.syncEngine = syncEngine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = room.name

        NotificationCenter.default.addObserver(
            self, selector: #selector(e2eeLiveDecrypted(_:)),
            name: MatrixE2EEManager.liveDecryptedEventNotification, object: nil)

        view.backgroundColor = UIColor(white: 0.95, alpha: 1.0)

        memberNames = room.memberNames
        memberAvatars = room.memberAvatars

        setupTitleView()
        buildInputBar()
        buildReplyBar()
        buildUploadBar()
        buildTypingLabel()
        buildTableView()
        buildStatusLabel()
        registerKeyboardObservers()
        installTimelineKeyboardDismissTap()

        seedInitialEvents()

        syncListenerToken = syncEngine.addUpdateListener { [weak self] json, _ in
            self?.handleSync(json)
        }

        if events.isEmpty {
            loadBackfill()
        } else {
            markInitialLoadDone()
            keepInitialBackfillAtBottom = true

            loadBackfill()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutInputBar()

        if !didInitialScroll, !rows.isEmpty {
            didInitialScroll = true
            scrollToBottom(animated: false)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        sendTypingStop()

        stopAudioPlayback()
        refreshAudioCells()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let token = syncListenerToken { syncEngine.removeUpdateListener(token) }
        cleanUpRecording(deleteFile: true)
        stopAudioPlayback()
    }

    override var canBecomeFirstResponder: Bool { return true }

    override func copy(_ sender: Any?) {
        if let text = pendingCopyText { UIPasteboard.general.string = text }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {

        if action == #selector(replyMenuTapped(_:)) { return pendingReplyTargetId != nil }
        if action == #selector(UIResponder.copy(_:)) { return pendingCopyText != nil }
        if action == #selector(reactMenuTapped(_:)) { return pendingReactionEventId != nil }
        if action == #selector(deleteMenuTapped(_:)) { return pendingDeleteEventId != nil }
        return false
    }

    struct VideoMeta {
        let width: Int
        let height: Int
        let durationMs: Int
    }
}
