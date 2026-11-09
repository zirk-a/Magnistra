// Overview: Comments screen.
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



final class MagnistraCommentsViewController:
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate,
    UITextViewDelegate
{
    let unifiedLoadingBand = MagnistraUnifiedLoadMoreBand(frame: CGRect.zero)
    private let initialCommentsBand = UILabel(frame: .zero)

    private struct DisplayRow {
        let comment: MagnistraComment
        let parentID: String
        let isThreadReply: Bool
        let showHideReplies: Bool
    }

    private let post: MagnistraRealPost
    private let queue = OperationQueue()
    private let profileQueue = OperationQueue()
    private let tableView = UITableView(frame: CGRect.zero, style: .plain)
    private let initialCommentsCenterSpinner = UIActivityIndicatorView(style: .gray)
    private let composerBar = UIView()
    private let composerSeparator = UIView()
    private let composerAvatar = UIImageView()
    private let commentField = UITextView()
    private let commentPlaceholder = UILabel()
    private let cancelReplyButton = UIButton(type: .custom)
    private var commentEditorHeight: CGFloat = 38.0
    private let commentEditorMaxHeight: CGFloat = 112.0
    private var commentMeasuredWidth: CGFloat = 0.0
    private let sendButton = UIButton(type: .custom)

    private var comments: [MagnistraComment] = []
    private var childCommentsByParentID:
        [String: [MagnistraComment]] = [:]
    private var expandedReplyIDs = Set<String>()
    private var loadingReplyIDs = Set<String>()
    private var likingCommentIDs = Set<String>()

    private var replyingToCommentID: String? = nil
    private var replyingToUsername: String? = nil

    private var nextMaxID: String? = nil
    private var isLoading = false
    private var reachedEnd = false
    private var isSendingComment = false
    private var keyboardHeight: CGFloat = 0.0
    private var resolvingProfileUsername = ""

    init(post: MagnistraRealPost) {
        self.post = post
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
        queue.maxConcurrentOperationCount = 1
        profileQueue.maxConcurrentOperationCount = 1
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        MagnistraCommentCell
            .clearAvatarMemoryCache()
    }

    // MARK: - View setup

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Comments"
        view.backgroundColor = UIColor.white

        unifiedLoadingBand.useCommentsGrayAppearance()
        initialCommentsCenterSpinner.hidesWhenStopped = true
        initialCommentsCenterSpinner.color = UIColor(white: 0.42, alpha: 1.0)
        initialCommentsCenterSpinner.backgroundColor = UIColor.clear
        view.addSubview(initialCommentsCenterSpinner)

        tableView.backgroundColor = UIColor.white
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView(frame: CGRect.zero)
        let dismissKeyboardTap = UITapGestureRecognizer(
            target: self, action: #selector(commentListTapped(_:)))
        dismissKeyboardTap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(dismissKeyboardTap)

        if #available(iOS 7.0, *) {
            if tableView.responds(to: NSSelectorFromString("setKeyboardDismissMode:")) {
                tableView.keyboardDismissMode = .onDrag
            }
        }
        view.addSubview(tableView)

        composerBar.backgroundColor = UIColor.white
        view.addSubview(composerBar)
        composerSeparator.backgroundColor = UIColor(white: 0.87, alpha: 1.0)
        composerBar.addSubview(composerSeparator)
        composerAvatar.backgroundColor = UIColor(white: 0.91, alpha: 1.0)
        composerAvatar.contentMode = .scaleAspectFill
        composerAvatar.clipsToBounds = true
        composerAvatar.layer.cornerRadius = 17.0
        composerBar.addSubview(composerAvatar)

        commentField.layer.borderWidth = 0.0
        commentField.backgroundColor = UIColor.white
        commentField.textColor = UIColor(white: 0.12, alpha: 1.0)
        commentField.font = UIFont.systemFont(ofSize: 14.0)
        commentField.returnKeyType = .send
        commentField.delegate = self
        commentField.isScrollEnabled = false
        commentField.showsVerticalScrollIndicator = true
        KeyboardPreferences.apply(to: commentField)
        composerBar.addSubview(commentField)
        commentPlaceholder.font = UIFont.systemFont(ofSize: 14.0)
        commentPlaceholder.textColor = UIColor(white: 0.70, alpha: 1.0)
        commentPlaceholder.backgroundColor = .clear
        commentPlaceholder.text = "Add a comment..."
        commentPlaceholder.isUserInteractionEnabled = false
        commentPlaceholder.lineBreakMode = .byTruncatingTail
        composerBar.addSubview(commentPlaceholder)
        cancelReplyButton.backgroundColor = UIColor(white: 0.87, alpha: 1.0)
        cancelReplyButton.setTitle(nil, for: .normal)
        let cancelCross = UIBezierPath()
        cancelCross.move(to: CGPoint(x: 7.5, y: 7.5))
        cancelCross.addLine(to: CGPoint(x: 14.5, y: 14.5))
        cancelCross.move(to: CGPoint(x: 14.5, y: 7.5))
        cancelCross.addLine(to: CGPoint(x: 7.5, y: 14.5))
        let crossLayer = CAShapeLayer()
        crossLayer.path = cancelCross.cgPath
        crossLayer.fillColor = UIColor.clear.cgColor
        crossLayer.strokeColor = UIColor(white: 0.40, alpha: 1.0).cgColor
        crossLayer.lineWidth = 2.2
        crossLayer.lineCap = .round
        cancelReplyButton.layer.addSublayer(crossLayer)
        cancelReplyButton.layer.cornerRadius = 11.0
        cancelReplyButton.clipsToBounds = true
        cancelReplyButton.isHidden = true
        cancelReplyButton.accessibilityLabel = "Cancel reply"
        cancelReplyButton.addTarget(
            self, action: #selector(cancelCommentReplyTapped), for: .touchUpInside)
        composerBar.addSubview(cancelReplyButton)

        sendButton.setTitle("Post", for: .normal)

        sendButton.backgroundColor = UIColor(
            red: 0.176,
            green: 0.312,
            blue: 0.448,
            alpha: 1.0
        )
        sendButton.layer.cornerRadius = 5.0
        sendButton.clipsToBounds = true
        sendButton.setTitleColor(UIColor.white, for: .normal)
        sendButton.setTitleColor(
            UIColor(white: 1.0, alpha: 0.55),
            for: .disabled
        )
        sendButton.titleLabel?.font =
            UIFont.boldSystemFont(ofSize: 13.0)
        sendButton.addTarget(
            self,
            action: #selector(sendCommentTapped),
            for: .touchUpInside
        )
        composerBar.addSubview(sendButton)

        sendButton.isHidden = true
        loadComposerAvatar()

        initialCommentsBand.backgroundColor = UIColor(white: 0.10, alpha: 0.88)
        initialCommentsBand.textColor = .white
        initialCommentsBand.textAlignment = .center
        initialCommentsBand.font = UIFont.boldSystemFont(ofSize: 12.0)
        initialCommentsBand.text = "Loading comments..."
        initialCommentsBand.isUserInteractionEnabled = false
        initialCommentsBand.isHidden = true
        view.addSubview(initialCommentsBand)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )

        setInitialCommentsLoading(
            true
        )

        loadPage(maxID: nil, replacing: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        unifiedLoadingBand.layout(on: view)

        let width = max(1.0, view.bounds.size.width)
        let height = max(1.0, view.bounds.size.height)

        let fieldWidth = max(40.0, width - 66.0 -
                             (replyingToCommentID == nil ? 0.0 : 30.0))
        if abs(commentMeasuredWidth - fieldWidth) > 0.5 {
            recalculateCommentEditorHeight(forWidth: fieldWidth)
        }
        let composerHeight = max(58.0, commentEditorHeight + 20.0)
        unifiedLoadingBand.bottomInset = composerHeight + keyboardHeight
        unifiedLoadingBand.layout(on: view)
        let composerY =
            max(
                0.0,
                height -
                keyboardHeight -
                composerHeight
            )

        tableView.frame = CGRect(
            x: 0.0,
            y: 0.0,
            width: width,
            height: composerY
        )

        composerBar.frame = CGRect(
            x: 0.0,
            y: composerY,
            width: width,
            height: composerHeight
        )

        initialCommentsBand.frame = CGRect(
            x: 0.0,
            y: 0.0,
            width: width,
            height: 38.0
        )
        initialCommentsBand.isHidden = true
        initialCommentsCenterSpinner.center = CGPoint(
            x: width * 0.5,
            y: max(30.0, composerY * 0.5)
        )
        view.bringSubviewToFront(initialCommentsCenterSpinner)

        composerSeparator.frame = CGRect(
            x: 0.0, y: 0.0, width: width, height: 1.0
        )

        let composerMidY = composerHeight * 0.5
        let avatarSize: CGFloat = 34.0
        let fieldHeight = commentEditorHeight
        composerAvatar.frame = CGRect(
            x: 12.0, y: composerMidY - avatarSize * 0.5,
            width: avatarSize, height: avatarSize
        )
        commentField.frame = CGRect(
            x: 55.0,
            y: composerMidY - fieldHeight * 0.5,
            width: fieldWidth,
            height: fieldHeight
        )

        let caret = commentField.caretRect(for: commentField.beginningOfDocument)
        let hasCaret = caret.height >= 8.0 &&
            caret.minY >= 0.0 && caret.maxY <= commentField.bounds.height + 8.0
        let textFontHeight = commentField.font?.lineHeight ?? 17.0
        let left = hasCaret ? caret.minX : 7.0
        let midY = hasCaret ? caret.midY : 17.0
        commentPlaceholder.frame = CGRect(
            x: commentField.frame.minX + left,
            y: commentField.frame.minY + midY - textFontHeight * 0.5,
            width: max(1.0, commentField.frame.width - left - 4.0),
            height: textFontHeight
        )

        cancelReplyButton.frame = CGRect(
            x: max(0.0, width - 32.0),
            y: composerMidY - 11.0, width: 22.0, height: 22.0)
        sendButton.frame = CGRect(
            x: max(0.0, width - 60.0),
            y: composerMidY - fieldHeight * 0.5,
            width: 54.0,
            height: fieldHeight
        )
    }

    // MARK: - Composer layout and text input

    private func recalculateCommentEditorHeight(forWidth width: CGFloat) {
        commentMeasuredWidth = width

        let wasScrollable = commentField.isScrollEnabled
        if wasScrollable { commentField.isScrollEnabled = false }
        let unconstrained = commentField.sizeThatFits(
            CGSize(width: width, height: 10000.0)).height
        let naturalHeight = max(38.0, ceil(unconstrained))
        commentEditorHeight = min(commentEditorMaxHeight, naturalHeight)
        commentField.isScrollEnabled = naturalHeight > commentEditorMaxHeight
    }

    private func updateCommentComposerText() {
        commentPlaceholder.isHidden = !commentField.text.isEmpty
        let width = max(40.0, view.bounds.width - 66.0 -
                        (replyingToCommentID == nil ? 0.0 : 30.0))
        let oldHeight = commentEditorHeight
        recalculateCommentEditorHeight(forWidth: width)
        if abs(oldHeight - commentEditorHeight) > 0.5 {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        if commentField.isScrollEnabled {
            let selection = commentField.selectedRange
            commentField.scrollRangeToVisible(selection)
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        guard textView === commentField else { return }
        commentPlaceholder.isHidden = !commentField.text.isEmpty
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        guard textView === commentField else { return }
        commentPlaceholder.isHidden = !commentField.text.isEmpty
    }

    func textViewDidChange(_ textView: UITextView) {
        guard textView === commentField else { return }
        updateCommentComposerText()
    }

    func textView(_ textView: UITextView,
                  shouldChangeTextIn range: NSRange,
                  replacementText text: String) -> Bool {

        if textView === commentField && text == "\n" {
            sendCommentTapped()
            return false
        }
        return true
    }

    private func loadComposerAvatar() {

        profileQueue.addOperation { [weak self] in
            guard let profile = try? MagnistraHomeService.loadCurrentProfile(),
                  let image = MagnistraHomeService.loadProfileAvatar(
                      primaryURL: profile.profilePicURL,
                      fallbackURL: profile.profilePicURLFallback)
            else { return }
            OperationQueue.main.addOperation { [weak self] in
                self?.composerAvatar.image = image
            }
        }
    }

    @objc private func commentListTapped(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended {
            commentField.resignFirstResponder()
        }
    }

    // MARK: - Comment list and table rendering

    private func displayRows() -> [DisplayRow] {
        var rows: [DisplayRow] = []

        for comment in comments {
            let expanded =
                expandedReplyIDs.contains(
                    comment.commentID
                )

            rows.append(
                DisplayRow(
                    comment: comment,
                    parentID:
                        comment.commentID,
                    isThreadReply:
                        false,
                    showHideReplies:
                        false
                )
            )

            if expanded {
                let children =
                    childCommentsByParentID[
                        comment.commentID
                    ] ?? []

                for index in
                    children.indices
                {
                    rows.append(
                        DisplayRow(
                            comment:
                                children[index],
                            parentID:
                                comment.commentID,
                            isThreadReply:
                                true,
                            showHideReplies:
                                index ==
                                children.count - 1
                        )
                    )
                }
            }
        }

        return rows
    }

    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        return displayRows().count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let rows = displayRows()
        let row = rows[indexPath.row]
        let reuse = "MagnistraCommentCell"
        let cell: MagnistraCommentCell

        if let reused =
            tableView.dequeueReusableCell(
                withIdentifier: reuse
            ) as? MagnistraCommentCell
        {
            cell = reused
        } else {
            cell = MagnistraCommentCell(
                style: .default,
                reuseIdentifier: reuse
            )
        }

        cell.configure(
            row.comment,
            repliesExpanded:
                expandedReplyIDs.contains(
                    row.parentID
                ),
            repliesLoading:
                loadingReplyIDs.contains(
                    row.parentID
                ),
            isThreadReply:
                row.isThreadReply,
            showHideReplies:
                row.showHideReplies
        )

        cell.onReply = {
            [weak self] in
            self?.beginReply(
                to: row.comment
            )
        }

        cell.onReplies = {
            [weak self] in
            self?.toggleReplies(
                parentID:
                    row.parentID
            )
        }

        cell.onLike = {
            [weak self] in
            self?.toggleLike(
                commentID:
                    row.comment.commentID
            )
        }

        cell.onProfileTap = {
            [weak self] username in

            self?
                .openCommentProfile(
                    username:
                        username
                )
        }

        return cell
    }

    func tableView(
        _ tableView: UITableView,
        heightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        let rows = displayRows()

        return
            MagnistraCommentCell.rowHeight(
                comment:
                    rows[
                        indexPath.row
                    ].comment,
                width:
                    tableView.bounds.size.width,
                isThreadReply:
                    rows[
                        indexPath.row
                    ].isThreadReply,
                showRepliesControl:
                    (
                        rows[
                            indexPath.row
                        ].showHideReplies ||
                        (
                            !rows[
                                indexPath.row
                            ].isThreadReply &&
                            rows[
                                indexPath.row
                            ].comment
                                .childCommentCount >
                                0 &&
                            !expandedReplyIDs
                                .contains(
                                    rows[
                                        indexPath.row
                                    ].parentID
                                )
                        )
                    )
            )
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        let count = displayRows().count

        if
            indexPath.row >=
            max(0, count - 2) &&
            magnistraUserInitiatedPagination(tableView)
        {
            requestNextPageIfNeeded()
        }
    }

    func scrollViewDidScroll(
        _ scrollView: UIScrollView
    ) {
        unifiedLoadingBand.refresh()
        let remaining =
            scrollView.contentSize.height -
            (
                scrollView.contentOffset.y +
                scrollView.bounds.size.height
            )

        if remaining < 220.0 &&
            magnistraUserInitiatedPagination(scrollView) {
            requestNextPageIfNeeded()
        }
    }

    private func setInitialCommentsLoading(
        _ visible: Bool
    ) {

        tableView.backgroundView = nil
        initialCommentsBand.isHidden = !visible
        if visible {
            view.bringSubviewToFront(initialCommentsBand)
        }

        initialCommentsBand.isHidden = true
        if visible {
            initialCommentsCenterSpinner.startAnimating()
        } else {
            initialCommentsCenterSpinner.stopAnimating()
        }
    }

    private func setPaginationLoading(_ visible: Bool) {
        let filler = UILabel(frame: CGRect(x: 0.0, y: 0.0,
                                           width: max(1.0, tableView.bounds.width),
                                           height: visible ? 38.0 : 0.0))
        filler.backgroundColor = UIColor(white: 0.86, alpha: 1.0)
        filler.textAlignment = .center
        filler.textColor = UIColor(white: 0.22, alpha: 1.0)
        filler.font = UIFont.boldSystemFont(ofSize: 12.0)
        filler.text = visible ? "Loading..." : ""
        tableView.tableFooterView = filler
        unifiedLoadingBand.show(visible, on: view, tracking: tableView,
                                inline: filler)
    }

    private func requestNextPageIfNeeded() {
        guard
            !isLoading,
            !reachedEnd,
            let cursor = nextMaxID,
            !cursor.isEmpty
        else {
            return
        }

        loadPage(
            maxID: cursor,
            replacing: false
        )
    }

    // MARK: - Profile navigation

    private func openCommentProfile(
        username rawUsername: String
    ) {
        var username =
            rawUsername
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        while username.hasPrefix("@") {
            username.removeFirst()
        }

        guard
            !username.isEmpty
        else {
            return
        }

        if
            resolvingProfileUsername
                .lowercased() ==
            username.lowercased()
        {
            return
        }

        resolvingProfileUsername =
            username

        let searchSessionID =
            MagnistraHomeService
                .makeExploreSearchSessionID()

        profileQueue.addOperation {
            [weak self] in

            do {
                let page =
                    try MagnistraHomeService
                        .loadExploreUserSearch(
                            query:
                                username,
                            searchSessionID:
                                searchSessionID,
                            rankToken:
                                ""
                        )

                var selected:
                    MagnistraExploreSearchUser? =
                        nil

                for user in page.users {
                    if
                        user.username
                            .lowercased() ==
                        username.lowercased()
                    {
                        selected =
                            user
                        break
                    }
                }

                if selected == nil {
                    selected =
                        page.users.first
                }

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self = self
                        else {
                            return
                        }

                        if
                            self.resolvingProfileUsername
                                .lowercased() ==
                            username.lowercased()
                        {
                            self.resolvingProfileUsername =
                                ""
                        }

                        guard
                            let user =
                                selected,
                            !user.userID.isEmpty
                        else {
                            return
                        }

                        let synthetic =
                            MagnistraRealPost(
                                mediaID:
                                    "",
                                userID:
                                    user.userID,
                                username:
                                    user.username,
                                fullName:
                                    user.fullName,
                                caption:
                                    "",
                                commentCount:
                                    0,
                                previewComments:
                                    [],
                                likes:
                                    0,
                                location:
                                    "",
                                takenAt:
                                    0.0,
                                imagePath:
                                    "",
                                imageURL:
                                    "",
                                imageCacheKey:
                                    "comment-profile:" +
                                    user.userID,
                                avatarPath:
                                    nil,
                                avatarURL:
                                    user.avatarURL,
                                avatarCacheKey:
                                    "comment-profile-avatar:" +
                                    user.userID,
                                musicTitle:
                                    nil,
                                musicArtist:
                                    nil,
                                musicAudioURL:
                                    nil,
                                musicStartTimeMs:
                                    0,
                                photoMusicImageURLFallback:
                                    nil,
                                videoURL:
                                    nil,
                                videoWidth:
                                    0,
                                videoHeight:
                                    0
                            )

                        let controller =
                            MagnistraProfileViewController(
                                post:
                                    synthetic
                            )

                        self.navigationController?
                            .pushViewController(
                                controller,
                                animated:
                                    true
                            )
                    }
            } catch {
                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self = self
                        else {
                            return
                        }

                        if
                            self.resolvingProfileUsername
                                .lowercased() ==
                            username.lowercased()
                        {
                            self.resolvingProfileUsername =
                                ""
                        }
                    }
            }
        }
    }

    // MARK: - Replies

    private func beginReply(
        to comment: MagnistraComment
    ) {
        replyingToCommentID =
            comment.commentID
        replyingToUsername =
            comment.username

        commentPlaceholder.text =
            "Reply to @" +
            comment.username +
            "…"
        cancelReplyButton.isHidden = false
        updateCommentComposerText()
        view.setNeedsLayout()

        commentField.becomeFirstResponder()
    }

    @objc private func cancelCommentReplyTapped() {
        guard replyingToCommentID != nil else { return }

        resetReplyTarget()
    }

    private func resetReplyTarget() {
        replyingToCommentID = nil
        replyingToUsername = nil
        commentPlaceholder.text = "Add a comment..."
        cancelReplyButton.isHidden = true
        updateCommentComposerText()
        view.setNeedsLayout()
    }

    private func toggleReplies(
        parentID: String
    ) {
        if expandedReplyIDs.contains(
            parentID
        ) {
            expandedReplyIDs.remove(
                parentID
            )
            tableView.reloadData()
            return
        }

        if childCommentsByParentID[
            parentID
        ] != nil
        {
            expandedReplyIDs.insert(
                parentID
            )
            tableView.reloadData()
            return
        }

        loadReplies(
            parentID: parentID
        )
    }

    private func loadReplies(
        parentID: String
    ) {
        guard
            !loadingReplyIDs.contains(
                parentID
            )
        else {
            return
        }

        loadingReplyIDs.insert(
            parentID
        )

        tableView.reloadData()

        let mediaID = post.mediaID

        queue.addOperation {
            [weak self] in

            do {
                let replies =
                    try MagnistraHomeService
                        .loadChildComments(
                            mediaID:
                                mediaID,
                            parentCommentID:
                                parentID
                        )

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.loadingReplyIDs
                            .remove(
                                parentID
                            )

                        self.childCommentsByParentID[
                            parentID
                        ] =
                            replies

                        self.expandedReplyIDs
                            .insert(
                                parentID
                            )

                        self.tableView
                            .reloadData()
                    }
            } catch {
                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.loadingReplyIDs
                            .remove(
                                parentID
                            )

                        self.tableView
                            .reloadData()
                    }
            }
        }
    }

    private func comment(
        withID commentID: String
    ) -> MagnistraComment? {
        for comment in comments {
            if
                comment.commentID ==
                commentID
            {
                return comment
            }
        }

        for values in
            childCommentsByParentID
                .values
        {
            for comment in values {
                if
                    comment.commentID ==
                    commentID
                {
                    return comment
                }
            }
        }

        return nil
    }

    private func parentID(
        forCommentID commentID: String
    ) -> String {
        for comment in comments {
            if
                comment.commentID ==
                commentID
            {
                return commentID
            }
        }

        for pair in
            childCommentsByParentID
        {
            if
                pair.value.contains(
                    where: {
                        $0.commentID ==
                            commentID
                    }
                )
            {
                return pair.key
            }
        }

        return commentID
    }

    private func copiedComment(
        _ comment: MagnistraComment,
        likeCount: Int? = nil,
        hasLiked: Bool? = nil,
        childCommentCount: Int? = nil
    ) -> MagnistraComment {
        return
            MagnistraComment(
                commentID:
                    comment.commentID,
                username:
                    comment.username,
                text:
                    comment.text,
                createdAt:
                    comment.createdAt,
                avatarURL:
                    comment.avatarURL,
                likeCount:
                    likeCount ??
                    comment.likeCount,
                hasLiked:
                    hasLiked ??
                    comment.hasLiked,
                parentCommentID:
                    comment.parentCommentID,
                childCommentCount:
                    childCommentCount ??
                    comment.childCommentCount,
                giphyURL:
                    comment.giphyURL,
                giphyWidth:
                    comment.giphyWidth,
                giphyHeight:
                    comment.giphyHeight
            )
    }

    private func replaceComment(
        _ updated: MagnistraComment
    ) {
        for index in
            comments.indices
        {
            if
                comments[index].commentID ==
                updated.commentID
            {
                comments[index] =
                    updated
                return
            }
        }

        for key in
            Array(
                childCommentsByParentID
                    .keys
            )
        {
            guard
                var values =
                    childCommentsByParentID[
                        key
                    ]
            else {
                continue
            }

            for index in
                values.indices
            {
                if
                    values[index].commentID ==
                    updated.commentID
                {
                    values[index] =
                        updated

                    childCommentsByParentID[
                        key
                    ] =
                        values
                    return
                }
            }
        }
    }

    private func incrementReplyCount(
        parentID: String
    ) {
        guard
            let parent =
                comment(
                    withID:
                        parentID
                )
        else {
            return
        }

        replaceComment(
            copiedComment(
                parent,
                childCommentCount:
                    parent.childCommentCount +
                    1
            )
        )
    }

    // MARK: - Comment actions

    private func toggleLike(
        commentID: String
    ) {
        guard
            !likingCommentIDs
                .contains(
                    commentID
                ),
            let old =
                comment(
                    withID:
                        commentID
                )
        else {
            return
        }

        let liked =
            !old.hasLiked

        let nextCount =
            max(
                0,
                old.likeCount +
                (
                    liked
                        ? 1
                        : -1
                )
            )

        likingCommentIDs.insert(
            commentID
        )

        replaceComment(
            copiedComment(
                old,
                likeCount:
                    nextCount,
                hasLiked:
                    liked
            )
        )

        tableView.reloadData()

        queue.addOperation {
            [weak self] in

            do {
                try MagnistraHomeService
                    .setCommentLiked(
                        commentID:
                            commentID,
                        liked:
                            liked
                    )

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        self?
                            .likingCommentIDs
                            .remove(
                                commentID
                            )
                    }
            } catch {
                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.likingCommentIDs
                            .remove(
                                commentID
                            )

                        self.replaceComment(
                            old
                        )

                        self.tableView
                            .reloadData()
                    }
            }
        }
    }

    @objc private func keyboardWillShow(
        _ note: Notification
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

        let screenFrame =
            value.cgRectValue

        let localFrame =
            view.convert(
                screenFrame,
                from: nil
            )

        keyboardHeight =
            max(
                0.0,
                view.bounds.maxY -
                localFrame.minY
            )

        view.setNeedsLayout()
    }

    @objc private func keyboardWillHide(
        _ note: Notification
    ) {
        keyboardHeight = 0.0
        view.setNeedsLayout()
    }

    // MARK: - Submitting comments

    @objc private func sendCommentTapped() {
        if isSendingComment {
            return
        }

        let text =
            commentField.text
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        if text.isEmpty {
            return
        }

        let replyTarget =
            replyingToCommentID

        let replyParent =
            replyTarget.map {
                parentID(
                    forCommentID:
                        $0
                )
            }

        isSendingComment = true
        sendButton.isEnabled = false
        commentField.isEditable = false

        let mediaID =
            post.mediaID

        queue.addOperation {
            [weak self] in

            do {
                let created =
                    try MagnistraHomeService
                        .addComment(
                            mediaID:
                                mediaID,
                            text:
                                text,
                            repliedToCommentID:
                                replyTarget
                        )

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.isSendingComment =
                            false
                        self.sendButton.isEnabled =
                            true
                        self.commentField.isEditable =
                            true
                        self.commentField.text =
                            ""
                        self.updateCommentComposerText()
                        self.commentField
                            .resignFirstResponder()

                        self.resetReplyTarget()

                        if
                            let targetParent =
                                replyParent
                        {
                            if
                                let created =
                                    created
                            {
                                var children =
                                    self.childCommentsByParentID[
                                        targetParent
                                    ] ?? []

                                if
                                    !children.contains(
                                        where: {
                                            $0.commentID ==
                                            created.commentID
                                        }
                                    )
                                {
                                    children.append(
                                        created
                                    )
                                }

                                self.childCommentsByParentID[
                                    targetParent
                                ] =
                                    children

                                self.expandedReplyIDs
                                    .insert(
                                        targetParent
                                    )

                                self.incrementReplyCount(
                                    parentID:
                                        targetParent
                                )

                                self.tableView
                                    .reloadData()
                            } else {
                                self.loadReplies(
                                    parentID:
                                        targetParent
                                )
                            }

                            return
                        }

                        if
                            let created =
                                created
                        {
                            self.comments.insert(
                                created,
                                at: 0
                            )

                            self.tableView
                                .reloadData()

                            self.tableView
                                .scrollToRow(
                                    at:
                                        IndexPath(
                                            row:
                                                0,
                                            section:
                                                0
                                        ),
                                    at:
                                        .top,
                                    animated:
                                        true
                                )
                        } else {
                            self.loadPage(
                                maxID:
                                    nil,
                                replacing:
                                    true
                            )
                        }
                    }
            } catch {
                let message =
                    error.localizedDescription

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.isSendingComment =
                            false
                        self.sendButton.isEnabled =
                            true
                        self.commentField.isEditable =
                            true

                        let alert =
                            UIAlertView(
                                title:
                                    "Comment",
                                message:
                                    message,
                                delegate:
                                    nil,
                                cancelButtonTitle:
                                    "OK"
                            )

                        alert.show()
                    }
            }
        }
    }

    // MARK: - Pagination and data merging

    private func loadPage(
        maxID: String?,
        replacing: Bool
    ) {
        guard !isLoading else {
            return
        }

        isLoading = true

        if !replacing {
            setPaginationLoading(
                true
            )
        }

        let mediaID =
            post.mediaID

        queue.addOperation {
            [weak self] in

            do {
                let page =
                    try MagnistraHomeService
                        .loadComments(
                            mediaID:
                                mediaID,
                            maxID:
                                maxID
                        )

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        self?
                            .applyPage(
                                page,
                                replacing:
                                    replacing
                            )
                    }
            } catch {
                let failureIsHTTPZero = NoConnectionBanner.isHTTPZero(
                    error.localizedDescription)
                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        self?.isLoading =
                            false

                        self?
                            .setInitialCommentsLoading(
                                false
                            )

                        self?
                            .setPaginationLoading(
                                false
                            )
                        if failureIsHTTPZero, let owner = self {
                            NoConnectionBanner.show(on: owner.view,
                                bottomInset: 49.0 + owner.keyboardHeight)
                        }
                    }
            }
        }
    }

    private func applyPage(
        _ page: MagnistraCommentsPage,
        replacing: Bool
    ) {

        NoConnectionBanner.hide(on: view)
        setInitialCommentsLoading(false)

        var seen =
            Set<String>()

        if !replacing {
            seen =
                Set(
                    comments.map {
                        $0.commentID
                    }
                )
        }

        var incoming:
            [MagnistraComment] = []

        for comment in
            page.comments
        {
            if
                !seen.contains(
                    comment.commentID
                )
            {
                seen.insert(
                    comment.commentID
                )

                incoming.append(
                    comment
                )
            }
        }

        if replacing {
            comments = incoming
            childCommentsByParentID
                .removeAll()
            expandedReplyIDs
                .removeAll()
        } else {
            comments.append(
                contentsOf:
                    incoming
            )
        }

        nextMaxID =
            page.nextMaxID

        reachedEnd =
            page.nextMaxID ==
            nil

        let retainedOffset = tableView.contentOffset

        tableView.reloadData()
        if !replacing {
            tableView.layoutIfNeeded()
        }
        setPaginationLoading(false)
        if !replacing {
            tableView.layoutIfNeeded()
            let minY = -tableView.contentInset.top
            let maxY = max(minY,
                tableView.contentSize.height - tableView.bounds.height +
                tableView.contentInset.bottom)
            let stableY = min(max(retainedOffset.y, minY), maxY)
            tableView.setContentOffset(
                CGPoint(x: retainedOffset.x, y: stableY), animated: false)
        }
        isLoading = false
    }
}

