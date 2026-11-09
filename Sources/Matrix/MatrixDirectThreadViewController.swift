// Overview: Matrix Direct thread screen.
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

final class MagnistraMatrixThreadViewController:
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate,
    UITextViewDelegate
{
    private let pullRefreshGesture = MagnistraPullRefreshGesture()
    private let pullRefreshIndicator = MagnistraNavigationPullIndicator()

    private let summary:
        MagnistraDirectThreadSummary

    private let tableView =
        UITableView(
            frame:
                CGRect.zero,
            style:
                .plain
        )

    private let composerBar =
        UIView()

    private let attachButton =
        UIButton(
            type:
                .custom
        )

    private let messageView =
        UITextView()

    private let messagePlaceholder =
        UILabel()

    private let sendButton =
        UIButton(
            type:
                .custom
        )

    private let loadQueue =
        OperationQueue()

    private var messages:
        [MagnistraMatrixTimelineMessage] =
            []

    private var loading =
        false

    private var sending =
        false

    private var keyboardOverlap:
        CGFloat =
            0.0

    private var audioPlayer:
        AVAudioPlayer?

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
    }

    required init?(
        coder:
            NSCoder
    ) {
        return nil
    }

    // MARK: - View setup

    override func viewDidLoad() {
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

        tableView.backgroundColor =
            view.backgroundColor

        view.addSubview(
            tableView
        )
        pullRefreshGesture.install(on: tableView) { [weak self] in
            self?.refreshTapped()
        }

        composerBar.backgroundColor =
            UIColor(
                white:
                    0.98,
                alpha:
                    1.0
            )

        composerBar.layer.borderWidth =
            0.5

        composerBar.layer.borderColor =
            UIColor(
                white:
                    0.78,
                alpha:
                    1.0
            )
            .cgColor

        view.addSubview(
            composerBar
        )

        attachButton.setTitle(
            "+",
            for:
                .normal
        )

        attachButton.setTitleColor(
            MagnistraPostCell
                .magnistraBlue,
            for:
                .normal
        )

        attachButton.titleLabel?.font =
            UIFont.systemFont(
                ofSize:
                    28.0
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

        messageView.backgroundColor =
            UIColor.white

        messageView.font =
            UIFont.systemFont(
                ofSize:
                    14.0
            )

        messageView.layer.cornerRadius =
            9.0

        messageView.layer.borderWidth =
            0.5

        messageView.layer.borderColor =
            UIColor(
                white:
                    0.78,
                alpha:
                    1.0
            )
            .cgColor

        messageView.delegate =
            self

        composerBar.addSubview(
            messageView
        )

        messagePlaceholder.text =
            "Message..."

        messagePlaceholder.font =
            UIFont.systemFont(
                ofSize:
                    14.0
            )

        messagePlaceholder.textColor =
            UIColor(
                white:
                    0.58,
                alpha:
                    1.0
            )

        messagePlaceholder.backgroundColor =
            UIColor.clear

        messageView.addSubview(
            messagePlaceholder
        )

        sendButton.setTitle(
            "Send",
            for:
                .normal
        )

        sendButton.setTitleColor(
            MagnistraPostCell
                .magnistraBlue,
            for:
                .normal
        )

        sendButton.titleLabel?.font =
            UIFont.boldSystemFont(
                ofSize:
                    14.0
            )

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

        NotificationCenter.default.addObserver(
            self,
            selector:
                #selector(
                    keyboardWillShow(
                        _:
                    )
                ),
            name:
                UIResponder.keyboardWillShowNotification,
            object:
                nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector:
                #selector(
                    keyboardWillHide(
                        _:
                    )
                ),
            name:
                UIResponder.keyboardWillHideNotification,
            object:
                nil
        )

        navigationItem.rightBarButtonItem = nil

        MagnistraMatrixDirectBackend
            .shared
            .prepare()

        loadTimeline()
    }

    deinit {
        NotificationCenter.default
            .removeObserver(
                self
            )
    }

    // MARK: - Layout

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width =
            view.bounds.size.width

        let height =
            view.bounds.size.height

        let composerHeight:
            CGFloat =
                50.0

        let composerY =
            max(
                0.0,
                height -
                keyboardOverlap -
                composerHeight
            )

        tableView.frame =
            CGRect(
                x:
                    0.0,
                y:
                    0.0,
                width:
                    width,
                height:
                    max(
                        0.0,
                        composerY
                    )
            )

        composerBar.frame =
            CGRect(
                x:
                    0.0,
                y:
                    composerY,
                width:
                    width,
                height:
                    composerHeight
            )

        attachButton.frame =
            CGRect(
                x:
                    4.0,
                y:
                    4.0,
                width:
                    40.0,
                height:
                    42.0
            )

        sendButton.frame =
            CGRect(
                x:
                    max(
                        0.0,
                        width -
                        58.0
                    ),
                y:
                    4.0,
                width:
                    54.0,
                height:
                    42.0
            )

        messageView.frame =
            CGRect(
                x:
                    44.0,
                y:
                    7.0,
                width:
                    max(
                        40.0,
                        width -
                        106.0
                    ),
                height:
                    36.0
            )

        messagePlaceholder.frame =
            CGRect(
                x:
                    5.0,
                y:
                    7.0,
                width:
                    max(
                        20.0,
                        messageView
                            .bounds
                            .size
                            .width -
                        10.0
                    ),
                height:
                    20.0
            )
    }

    override func viewWillDisappear(
        _ animated:
            Bool
    ) {
        super.viewWillDisappear(
            animated
        )

        audioPlayer?
            .stop()

        audioPlayer =
            nil
    }

    @objc private func refreshTapped() {
        guard !loading else { return }
        pullRefreshIndicator.begin(on: navigationItem, label: "Updating Matrix messages")
        loadTimeline()
    }

    // MARK: - Compose and attachments

    @objc private func sendTapped() {
        guard
            !sending
        else {
            return
        }

        let text =
            messageView.text
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        guard
            !text.isEmpty
        else {
            return
        }

        sending =
            true

        sendButton.isEnabled =
            false

        MagnistraMatrixDirectBackend
            .shared
            .sendText(
                roomId:
                    summary.threadFBID,
                text:
                    text
            ) {
                [weak self]
                json,
                error in

                OperationQueue.main
                    .addOperation {
                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.sending =
                            false

                        self.sendButton.isEnabled =
                            true

                        if
                            let error =
                                error
                        {
                            self.showError(
                                error.localizedDescription
                            )
                            return
                        }

                        self.messageView.text =
                            ""

                        self.messagePlaceholder.isHidden =
                            false

                        let eventId =
                            (
                                json?[
                                    "event_id"
                                ] as? String
                            ) ??
                            (
                                "local-" +
                                String(
                                    Int64(
                                        Date()
                                            .timeIntervalSince1970 *
                                        1000.0
                                    )
                                )
                            )

                        self.messages.append(
                            MagnistraMatrixTimelineMessage(
                                eventId:
                                    eventId,
                                text:
                                    text,
                                timestampMilliseconds:
                                    Date()
                                        .timeIntervalSince1970 *
                                    1000.0,
                                isOutgoing:
                                    true,
                                isEncrypted:
                                    false,
                                detailText:
                                    nil,
                                eventType:
                                    "m.room.message",
                                content: [
                                    "msgtype":
                                        "m.text",
                                    "body":
                                        text
                                ]
                            )
                        )

                        self.tableView
                            .reloadData()

                        self.scrollToBottom(
                            animated:
                                true
                        )
                    }
            }
    }

    @objc private func attachTapped() {
        let sheet =
            UIActionSheet(
                title:
                    "Photo, video and voice sending will use this same composer in the next media-send stage.",
                delegate:
                    nil,
                cancelButtonTitle:
                    "OK",
                destructiveButtonTitle:
                    nil
            )

        sheet.show(
            in:
                view
        )
    }

    func textViewDidChange(
        _ textView:
            UITextView
    ) {
        messagePlaceholder.isHidden =
            !textView.text.isEmpty
    }

    @objc private func keyboardWillShow(
        _ note:
            Notification
    ) {
        guard
            let value =
                note.userInfo?[
                    UIResponder
                        .keyboardFrameEndUserInfoKey
                ] as? NSValue
        else {
            return
        }

        let frame =
            value.cgRectValue

        keyboardOverlap =
            max(
                0.0,
                min(
                    view.bounds
                        .size
                        .height,
                    frame.size.height
                )
            )

        view.setNeedsLayout()
        view.layoutIfNeeded()

        scrollToBottom(
            animated:
                false
        )
    }

    @objc private func keyboardWillHide(
        _ note:
            Notification
    ) {
        keyboardOverlap =
            0.0

        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    // MARK: - Timeline loading and media preparation

    private func loadTimeline() {
        guard
            !loading
        else {
            return
        }

        loading =
            true

        navigationItem
            .rightBarButtonItem?
            .isEnabled =
                false

        let roomId =
            summary.threadFBID

        loadQueue.addOperation {
            [weak self] in

            do {
                let loaded =
                    try
                        MagnistraMatrixDirectService
                            .loadTimeline(
                                roomId:
                                    roomId
                            )

                OperationQueue.main
                    .addOperation {
                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.loading =
                            false
                        self.pullRefreshIndicator.end(on: self.navigationItem)

                        self.navigationItem
                            .rightBarButtonItem?
                            .isEnabled =
                                true

                        self.messages =
                            loaded

                        self.tableView
                            .reloadData()

                        self.primeVisibleMedia()

                        self.scrollToBottom(
                            animated:
                                false
                        )
                    }
            } catch {
                OperationQueue.main
                    .addOperation {
                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.loading =
                            false
                        self.pullRefreshIndicator.end(on: self.navigationItem)

                        self.navigationItem
                            .rightBarButtonItem?
                            .isEnabled =
                                true

                        self.showError(
                            error.localizedDescription
                        )
                    }
            }
        }
    }

    private func primeVisibleMedia() {
        for
            (
                index,
                timeline
            )
            in messages.enumerated()
        {
            let direct =
                directMessage(
                    timeline
                )

            guard
                (
                    direct.mediaKind ==
                        "photo" ||
                    direct.mediaKind ==
                        "video"
                ),
                let mxc =
                    direct.previewURL,
                mxc.hasPrefix(
                    "mxc://"
                )
            else {
                continue
            }

            MagnistraMatrixMediaStore
                .shared
                .loadImage(
                    mxc:
                        mxc
                ) {
                    [weak self]
                    image in

                    guard
                        let self =
                            self,
                        let image =
                            image,
                        index <
                            self.messages
                                .count,
                        self.messages[
                            index
                        ].eventId ==
                            timeline.eventId
                    else {
                        return
                    }

                    MagnistraDirectMessageCell
                        .seedPreview(
                            image,
                            messageID:
                                timeline.eventId
                        )

                    self.tableView
                        .reloadRows(
                            at: [
                                IndexPath(
                                    row:
                                        index,
                                    section:
                                        0
                                )
                            ],
                            with:
                                .none
                        )
                }
        }
    }

    // MARK: - Message presentation model

    private func directMessage(
        _ timeline:
            MagnistraMatrixTimelineMessage
    ) -> MagnistraDirectMessage {
        let content =
            timeline.content

        let msgtype =
            (
                content[
                    "msgtype"
                ] as? String ??
                ""
            )
            .lowercased()

        let info =
            content[
                "info"
            ] as? [String: Any] ??
            [:]

        let url =
            (content["url"] as? String) ??
            ((content["file"] as? [String: Any])?["url"] as? String)

        let thumbnail =
            (info["thumbnail_url"] as? String) ??
            ((info["thumbnail_file"] as? [String: Any])?["url"] as? String)

        var mediaKind =
            ""

        var previewURL:
            String? =
                nil

        var mediaURL:
            String? =
                nil

        var audioURL:
            String? =
                nil

        if msgtype == "m.image" {
            mediaKind =
                "photo"

            previewURL =
                url

            mediaURL =
                url
        } else if
            msgtype ==
                "m.video"
        {
            mediaKind =
                "video"

            previewURL =
                thumbnail

            mediaURL =
                url
        } else if
            msgtype ==
                "m.audio"
        {
            mediaKind =
                "voice"

            audioURL =
                url

            mediaURL =
                url
        }

        let width =
            (
                info[
                    "w"
                ] as? NSNumber
            )?
            .doubleValue ??
            0.0

        let height =
            (
                info[
                    "h"
                ] as? NSNumber
            )?
            .doubleValue ??
            0.0

        let aspect =
            (
                width >
                    0.0 &&
                height >
                    0.0
            )
                ? width /
                    height
                : 1.0

        let duration =
            (
                info[
                    "duration"
                ] as? NSNumber
            )?
            .doubleValue ??
            0.0

        var waveform:
            [Double] =
                []

        if
            let audioInfo =
                content[
                    "org.matrix.msc1767.audio"
                ] as? [String: Any],
            let values =
                audioInfo[
                    "waveform"
                ] as? [NSNumber]
        {
            waveform =
                values.map {
                    $0.doubleValue
                }
        }

        return
            MagnistraDirectMessage(
                messageID:
                    timeline.eventId,
                text:
                    timeline.text,
                detailText:
                    timeline.detailText,
                previewURL:
                    previewURL,
                contentType:
                    msgtype.isEmpty
                        ? timeline.eventType
                        : msgtype,
                timestampMilliseconds:
                    timeline.timestampMilliseconds,
                isOutgoing:
                    timeline.isOutgoing,
                audioURL:
                    audioURL,
                audioDurationMilliseconds:
                    duration,
                mediaURL:
                    mediaURL,
                targetURL:
                    nil,
                mediaKind:
                    mediaKind,
                audioWaveform:
                    waveform,
                mediaAspectRatio:
                    aspect
            )
    }

    private func scrollToBottom(
        animated:
            Bool
    ) {
        guard
            !messages.isEmpty
        else {
            return
        }

        tableView.scrollToRow(
            at:
                IndexPath(
                    row:
                        messages.count -
                        1,
                    section:
                        0
                ),
            at:
                .bottom,
            animated:
                animated
        )
    }

    // MARK: - Audio and media presentation

    private func playVoice(
        _ message:
            MagnistraDirectMessage
    ) {
        guard
            let mxc =
                message.audioURL,
            mxc.hasPrefix(
                "mxc://"
            )
        else {
            return
        }

        audioPlayer?
            .stop()

        audioPlayer =
            nil

        MagnistraMatrixMediaStore
            .shared
            .materializeAudio(
                mxc:
                    mxc
            ) {
                [weak self]
                path in

                guard
                    let self =
                        self,
                    let path =
                        path,
                    let player =
                        try?
                            AVAudioPlayer(
                                contentsOf:
                                    URL(
                                        fileURLWithPath:
                                            path
                                    )
                            )
                else {
                    return
                }

                self.audioPlayer =
                    player

                player.prepareToPlay()
                player.play()
            }
    }

    private func openPhoto(
        _ message:
            MagnistraDirectMessage
    ) {
        guard
            let mxc =
                message.mediaURL,
            mxc.hasPrefix(
                "mxc://"
            )
        else {
            return
        }

        MagnistraMatrixMediaStore
            .shared
            .loadImage(
                mxc:
                    mxc
            ) {
                [weak self]
                image in

                guard
                    let self =
                        self,
                    let image =
                        image
                else {
                    return
                }

                let controller =
                    UIViewController()

                controller.title =
                    "Photo"

                controller.view.backgroundColor =
                    UIColor.black

                let imageView =
                    UIImageView(
                        frame:
                            controller
                                .view
                                .bounds
                    )

                imageView.autoresizingMask = [
                    .flexibleWidth,
                    .flexibleHeight
                ]

                imageView.contentMode =
                    .scaleAspectFit

                imageView.image =
                    image

                controller.view.addSubview(
                    imageView
                )

                self.navigationController?
                    .pushViewController(
                        controller,
                        animated:
                            true
                    )
            }
    }

    private func openVideo(
        _ message:
            MagnistraDirectMessage
    ) {
        guard
            let mxc =
                message.mediaURL,
            mxc.hasPrefix(
                "mxc://"
            )
        else {
            return
        }

        MagnistraMatrixMediaStore
            .shared
            .materializeVideo(
                mxc:
                    mxc
            ) {
                [weak self]
                path in

                guard
                    let self =
                        self,
                    let path =
                        path
                else {
                    return
                }

                let controller =
                    MPMoviePlayerViewController(
                        contentURL:
                            URL(
                                fileURLWithPath:
                                    path
                            )
                    )

                self
                    .presentMoviePlayerViewControllerAnimated(
                        controller
                    )
            }
    }

    private func showError(
        _ message:
            String
    ) {
        let alert =
            UIAlertView()

        alert.title =
            "Matrix"

        alert.message =
            message

        alert.addButton(
            withTitle:
                "OK"
        )

        alert.show()
    }

    // MARK: - Table view rendering

    func numberOfSections(
        in tableView:
            UITableView
    ) -> Int {
        return 1
    }

    func tableView(
        _ tableView:
            UITableView,
        numberOfRowsInSection
            section:
                Int
    ) -> Int {
        return
            messages.count
    }

    func tableView(
        _ tableView:
            UITableView,
        cellForRowAt
            indexPath:
                IndexPath
    ) -> UITableViewCell {
        let message =
            directMessage(
                messages[
                    indexPath.row
                ]
            )

        let cell:
            MagnistraDirectMessageCell

        switch
            magnistraDirectRenderKind(
                message
            )
        {
        case .text:
            let id =
                "MagnistraDirectTextCell"

            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier:
                                id
                        ) as?
                        MagnistraDirectTextCell
                ) ??
                MagnistraDirectTextCell(
                    style:
                        .default,
                    reuseIdentifier:
                        id
                )

        case .unsupported:
            let id =
                "MagnistraDirectUnsupportedCell"

            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier:
                                id
                        ) as?
                        MagnistraDirectUnsupportedCell
                ) ??
                MagnistraDirectUnsupportedCell(
                    style:
                        .default,
                    reuseIdentifier:
                        id
                )

        case .photo:
            let id =
                "MagnistraDirectPhotoCell"

            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier:
                                id
                        ) as?
                        MagnistraDirectPhotoCell
                ) ??
                MagnistraDirectPhotoCell(
                    style:
                        .default,
                    reuseIdentifier:
                        id
                )

        case .video:
            let id =
                "MagnistraDirectVideoCell"

            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier:
                                id
                        ) as?
                        MagnistraDirectVideoCell
                ) ??
                MagnistraDirectVideoCell(
                    style:
                        .default,
                    reuseIdentifier:
                        id
                )

        case .voice:
            let id =
                "MagnistraDirectVoiceCell"

            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier:
                                id
                        ) as?
                        MagnistraDirectVoiceCell
                ) ??
                MagnistraDirectVoiceCell(
                    style:
                        .default,
                    reuseIdentifier:
                        id
                )

        case .sharedPost:
            let id =
                "MagnistraDirectSharedPostCell"

            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier:
                                id
                        ) as?
                        MagnistraDirectSharedPostCell
                ) ??
                MagnistraDirectSharedPostCell(
                    style:
                        .default,
                    reuseIdentifier:
                        id
                )

        case .sharedReel:
            let id =
                "MagnistraDirectSharedReelCell"

            cell =
                (
                    tableView
                        .dequeueReusableCell(
                            withIdentifier:
                                id
                        ) as?
                        MagnistraDirectSharedReelCell
                ) ??
                MagnistraDirectSharedReelCell(
                    style:
                        .default,
                    reuseIdentifier:
                        id
                )
        }

        cell.configure(
            message
        )

        return cell
    }

    func tableView(
        _ tableView:
            UITableView,
        heightForRowAt
            indexPath:
                IndexPath
    ) -> CGFloat {
        let message =
            directMessage(
                messages[
                    indexPath.row
                ]
            )

        switch
            magnistraDirectRenderKind(
                message
            )
        {
        case .text,
             .unsupported:
            return
                MagnistraDirectTextCell
                    .rowHeight(
                        for:
                            message,
                        width:
                            tableView
                                .bounds
                                .size
                                .width
                    )

        case .photo,
             .video:
            return
                MagnistraDirectMediaCell
                    .rowHeight(
                        for:
                            message,
                        width:
                            tableView
                                .bounds
                                .size
                                .width
                    )

        case .voice:
            return
                MagnistraDirectVoiceCell
                    .rowHeight()

        case .sharedPost,
             .sharedReel:
            return
                MagnistraDirectSharedCell
                    .rowHeight(
                        for:
                            message,
                        width:
                            tableView
                                .bounds
                                .size
                                .width
                    )
        }
    }

    func tableView(
        _ tableView:
            UITableView,
        didSelectRowAt
            indexPath:
                IndexPath
    ) {
        tableView.deselectRow(
            at:
                indexPath,
            animated:
                true
        )

        guard
            indexPath.row >=
                0,
            indexPath.row <
                messages.count
        else {
            return
        }

        let message =
            directMessage(
                messages[
                    indexPath.row
                ]
            )

        if
            message.mediaKind ==
                "voice"
        {
            playVoice(
                message
            )
            return
        }

        if
            message.mediaKind ==
                "video"
        {
            openVideo(
                message
            )
            return
        }

        if
            message.mediaKind ==
                "photo"
        {
            openPhoto(
                message
            )
        }
    }
}

