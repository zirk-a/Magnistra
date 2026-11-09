// Overview: Direct inbox and new-message screens.
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

final class MagnistraDirectNewMessageViewController:
    UIViewController, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate
{
    var onRecipientChosen: ((MagnistraExploreSearchUser) -> Void)?
    private let search = UISearchBar()
    private let searchHost = UIView()
    private let stablePlaceholder = UILabel()
    private let idleSearchGroup = UIView()
    private let idleSearchIcon = UIImageView()
    private let idleSearchText = UILabel()
    private let imageQueue = OperationQueue()
    private let directClearButton = UIButton(type: .custom)
    private let directCancelButton = UIButton(type: .custom)
    private var directEditing = false
    private var directModernSearch: Bool {
        return (UIDevice.current.systemVersion as NSString).integerValue >= 7
    }
    private var directIOS7Search: Bool {
        return UIDevice.current.systemVersion.hasPrefix("7.")
    }
    private let resultsView = UITableView(frame: .zero, style: .plain)
    private let queue = OperationQueue()
    private var users: [MagnistraExploreSearchUser] = []
    private var generation = 0
    private var searchSessionID = UUID().uuidString

override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Message"
        view.backgroundColor = UIColor.white
        queue.maxConcurrentOperationCount = 1
        search.frame = CGRect(x: 0.0, y: 0.0, width: max(1.0, view.bounds.width), height: 44.0)
        search.delegate = self
        search.placeholder = "Search people"
        view.addSubview(search)
        resultsView.frame = CGRect(x: 0.0, y: 44.0,
            width: max(1.0, view.bounds.width),
            height: max(0.0, view.bounds.height - 44.0))
        resultsView.dataSource = self
        resultsView.delegate = self
        resultsView.rowHeight = 60.0
        view.addSubview(resultsView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        NSObject.cancelPreviousPerformRequests(withTarget: self,
            selector: #selector(searchNow), object: nil)
        super.viewWillDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        searchHost.frame = CGRect(x: 0, y: 0, width: width, height: 44)
        layoutDirectSearch()
        resultsView.frame = CGRect(x: 0, y: 44, width: width,
                                   height: max(0, view.bounds.height - 44))
    }

    private func directNativeTextField(in view: UIView) -> UITextField? {
        if let text = view as? UITextField { return text }
        for child in view.subviews {
            if let text = directNativeTextField(in: child) { return text }
        }
        return nil
    }

    private func directClearGlyph() -> UIImage? {

        UIGraphicsBeginImageContextWithOptions(CGSize(width: 18.0, height: 18.0),
                                               false, 0.0)
        defer { UIGraphicsEndImageContext() }
        let disc = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 16, height: 16))
        UIColor(white: 0.62, alpha: 0.90).setFill()
        disc.fill()
        let cross = UIBezierPath()
        cross.move(to: CGPoint(x: 6.3, y: 6.3))
        cross.addLine(to: CGPoint(x: 11.7, y: 11.7))
        cross.move(to: CGPoint(x: 11.7, y: 6.3))
        cross.addLine(to: CGPoint(x: 6.3, y: 11.7))
        cross.lineCapStyle = .round
        cross.lineWidth = 1.55
        UIColor.white.setStroke()
        cross.stroke()
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    private func directMagnifierGlyph() -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 18.0, height: 18.0),
                                               false, 0.0)
        defer { UIGraphicsEndImageContext() }
        let line = UIBezierPath(ovalIn: CGRect(x: 2.5, y: 2.0, width: 10.5, height: 10.5))
        line.lineWidth = 1.55
        UIColor(white: 0.60, alpha: 1.0).setStroke()
        line.stroke()
        let handle = UIBezierPath()
        handle.move(to: CGPoint(x: 11.7, y: 11.7))
        handle.addLine(to: CGPoint(x: 16.0, y: 16.0))
        handle.lineWidth = 1.55
        handle.lineCapStyle = .round
        handle.stroke()
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    private func layoutDirectSearch() {
        let width = max(1.0, searchHost.bounds.width)
        let cancelWidth: CGFloat = directIOS7Search && directEditing ? 65.0 : 0.0
        search.frame = CGRect(x: 0, y: 0, width: max(1.0, width - cancelWidth), height: 44)
        guard directModernSearch else { return }
        search.layoutIfNeeded()
        if let field = directNativeTextField(in: search) {
            field.placeholder = ""
            field.textAlignment = .left
            field.contentVerticalAlignment = .center

            field.leftView?.isHidden = !directEditing && (search.text ?? "").isEmpty
            if directIOS7Search { field.clearButtonMode = .never }
            stablePlaceholder.font = field.font ?? UIFont.systemFont(ofSize: 14)
            if directEditing {
                if stablePlaceholder.superview !== field {
                    stablePlaceholder.removeFromSuperview()
                    field.addSubview(stablePlaceholder)
                }
                let rect = field.editingRect(forBounds: field.bounds)
                stablePlaceholder.frame = CGRect(x: rect.minX + 2.0, y: rect.minY,
                    width: max(1, rect.width - 4.0), height: rect.height)
            } else {
                if stablePlaceholder.superview !== searchHost {
                    stablePlaceholder.removeFromSuperview()
                    searchHost.addSubview(stablePlaceholder)
                }
                let rect = field.convert(field.editingRect(forBounds: field.bounds),
                                         to: searchHost)
                stablePlaceholder.frame = CGRect(x: rect.minX + 2.0, y: rect.minY,
                    width: max(1, search.frame.width - rect.minX - 18.0),
                    height: rect.height)
            }
        }
        let searchIsEmpty = (search.text ?? "").isEmpty
        stablePlaceholder.isHidden = !directEditing || !searchIsEmpty
        if !directEditing && stablePlaceholder.superview !== searchHost {
            stablePlaceholder.removeFromSuperview()
            searchHost.addSubview(stablePlaceholder)
        }
        idleSearchGroup.isHidden = directEditing || !searchIsEmpty
        if !idleSearchGroup.isHidden {
            let textSize = idleSearchText.sizeThatFits(
                CGSize(width: max(1.0, width - 70.0), height: 26.0))
            let textWidth = min(textSize.width + 2.0, max(1.0, width - 70.0))
            let groupWidth = textWidth + 26.0
            idleSearchGroup.frame = CGRect(x: max(0, (search.frame.width - groupWidth) * 0.5),
                                           y: 0, width: groupWidth, height: 44.0)
            idleSearchIcon.frame = CGRect(x: 0, y: 13, width: 18, height: 18)
            idleSearchText.frame = CGRect(x: 26, y: 9, width: textWidth, height: 26)
            searchHost.bringSubviewToFront(idleSearchGroup)
        }
        if directIOS7Search {
            directClearButton.frame = CGRect(x: max(0, search.frame.maxX - 40),
                y: 8, width: 28, height: 28)
            directClearButton.isHidden = (search.text ?? "").isEmpty
            directCancelButton.frame = CGRect(x: max(0, width - 65),
                y: 0, width: 65, height: 44)
            directCancelButton.isHidden = !directEditing
            searchHost.bringSubviewToFront(directClearButton)
            searchHost.bringSubviewToFront(directCancelButton)
        }
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        directEditing = true
        if !directIOS7Search { searchBar.showsCancelButton = true }
        layoutDirectSearch()
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        directEditing = false
        layoutDirectSearch()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        generation += 1
        NSObject.cancelPreviousPerformRequests(withTarget: self,
            selector: #selector(searchNow), object: nil)
        searchBar.text = ""
        directNativeTextField(in: searchBar)?.text = ""
        users = []
        resultsView.reloadData()
        searchBar.resignFirstResponder()
        directNativeTextField(in: searchBar)?.resignFirstResponder()
        directEditing = false
        if !directIOS7Search { searchBar.showsCancelButton = false }
        layoutDirectSearch()
    }

    @objc private func directClearTapped() {
        generation += 1
        NSObject.cancelPreviousPerformRequests(withTarget: self,
            selector: #selector(searchNow), object: nil)
        search.text = ""
        directNativeTextField(in: search)?.text = ""
        users = []
        resultsView.reloadData()
        layoutDirectSearch()
        search.becomeFirstResponder()
    }

    @objc private func directCancelTapped() {
        searchBarCancelButtonClicked(search)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        directNativeTextField(in: searchBar)?.resignFirstResponder()
        directEditing = false
        layoutDirectSearch()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        layoutDirectSearch()
        generation += 1
        NSObject.cancelPreviousPerformRequests(withTarget: self,
            selector: #selector(searchNow), object: nil)
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            users = []
            resultsView.reloadData()
            return
        }
        perform(#selector(searchNow), with: nil, afterDelay: 0.35)
    }

    @objc private func searchNow() {
        let currentGeneration = generation
        let query = (search.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        let sessionID = searchSessionID
        queue.addOperation { [weak self] in
            do {
                let page = try MagnistraHomeService.loadExploreUserSearch(
                    query: query, searchSessionID: sessionID, rankToken: "")
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self, self.generation == currentGeneration else { return }
                    self.users = page.users
                    self.resultsView.reloadData()
                }
            } catch {
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self, self.generation == currentGeneration else { return }
                    self.users = []
                    self.resultsView.reloadData()
                }
            }
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {

        search.resignFirstResponder()
        directNativeTextField(in: search)?.resignFirstResponder()
    }

    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int { return users.count }
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = (tableView.dequeueReusableCell(withIdentifier: "DirectNewUser")
                    as? MagnistraExploreSearchUserCell) ??
            MagnistraExploreSearchUserCell(style: .default,
                                          reuseIdentifier: "DirectNewUser")
        let user = users[indexPath.row]
        cell.representedID = user.userID
        cell.usernameLabel.text = user.username
        cell.fullNameLabel.text = user.fullName
        cell.avatarView.image = nil
        cell.accessoryType = .disclosureIndicator
        if let avatarURL = user.avatarURL, !avatarURL.isEmpty {
            let representedID = user.userID
            imageQueue.addOperation { [weak cell] in
                guard let path = MagnistraHomeService.materializeFeedImage(
                    url: avatarURL, stableKey: "direct-new-avatar:" + representedID,
                    isAvatar: true), let image = UIImage(contentsOfFile: path)
                else { return }
                OperationQueue.main.addOperation { [weak cell] in
                    guard let cell = cell, cell.representedID == representedID else { return }
                    cell.avatarView.image = image
                }
            }
        }
        return cell
    }
    func tableView(_ tableView: UITableView,
                   didSelectRowAt indexPath: IndexPath) {
        guard indexPath.row < users.count else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        onRecipientChosen?(users[indexPath.row])
    }
}

final class DirectViewController:
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate,
    UIActionSheetDelegate
{
    private let pullRefreshGesture = MagnistraPullRefreshGesture()
    private let pullRefreshIndicator = MagnistraNavigationPullIndicator()

    private var backendMode =
        MagnistraDirectBackendStore.current()

    private var backendButton:
        UIBarButtonItem?
    private var newMessageButton: UIBarButtonItem?

    private let tableView =
        UITableView(
            frame:
                CGRect.zero,
            style:
                .plain
        )

    private let loadQueue =
        OperationQueue()

    private var threads:
        [MagnistraDirectThreadSummary] =
            []

    private var loading =
        false

    private let reuseID =
        "MagnistraDirectInboxCell"

    override func viewDidLoad() {
        super.viewDidLoad()

        title =
            "Direct"

        view.backgroundColor =
            instaLightGray()

        loadQueue.maxConcurrentOperationCount =
            1

        tableView.dataSource =
            self

        tableView.delegate =
            self

        tableView.rowHeight =
            66.0

        tableView.backgroundColor =
            UIColor.white

        tableView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        view.addSubview(
            tableView
        )
        pullRefreshGesture.install(on: tableView) { [weak self] in
            self?.refreshTapped()
        }

        let backendItem = MagnistraProfileIcons.navbarItem(
            "MenuWhite", title: "Menu", target: self,
            action: #selector(backendTapped))

        backendButton =
            backendItem

        navigationItem.leftBarButtonItem =
            backendItem
        let composeView = UIButton(type: .custom)
        composeView.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        composeView.setTitle("+", for: .normal)
        composeView.setTitleColor(UIColor.white, for: .normal)
        composeView.titleLabel?.font = UIFont.systemFont(ofSize: 29.0)
        composeView.accessibilityLabel = "New Message"

        if #available(iOS 7.0, *) {
            composeView.frame = CGRect(x: 0, y: 0, width: 44, height: 34)
            composeView.contentVerticalAlignment = .center
            composeView.titleEdgeInsets = UIEdgeInsets(top: -2, left: 0, bottom: 2, right: 0)
        }
        composeView.addTarget(self, action: #selector(newMessageTapped), for: .touchUpInside)
        newMessageButton = UIBarButtonItem(customView: composeView)
        navigationItem.rightBarButtonItem = nil

        if backendMode == .hybrid {
            backendMode =
                .web

            MagnistraDirectBackendStore
                .set(
                    .web
                )
        }

        applyBackendMode(
            reload:
                true
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        tableView.frame =
            view.bounds
    }

    @objc private func refreshTapped() {
        guard
            backendMode == .web ||
            backendMode == .matrix
        else {
            return
        }

        guard !loading else { return }
        pullRefreshIndicator.begin(on: navigationItem, label: "Updating Direct inbox")
        loadInbox()
    }

    @objc private func backendTapped() {
        let sheet =
            UIActionSheet()

        sheet.title =
            "Direct Backend"

        sheet.delegate =
            self

        sheet.tag =
            7301

        _ = sheet.addButton(
            withTitle:
                "Web"
        )

        _ = sheet.addButton(
            withTitle:
                "Matrix"
        )

        let cancelIndex =
            sheet.addButton(
                withTitle:
                    "Cancel"
            )

        sheet.cancelButtonIndex =
            cancelIndex

        if
            let tabBar =
                tabBarController?
                    .tabBar
        {
            sheet.show(
                from:
                    tabBar
            )
        } else {
            sheet.show(
                in:
                    view
            )
        }

        for candidate in sheet.subviews {
            guard
                let button =
                    candidate as?
                        UIButton,
                let title =
                    button.title(
                        for:
                            .normal
                    )
            else {
                continue
            }

            if title == "Web" {
                button.setTitleColor(
                    backendMode == .web
                        ? instaBlue()
                        : UIColor.black,
                    for:
                        .normal
                )
            } else if title == "Matrix" {
                button.setTitleColor(
                    backendMode == .matrix
                        ? instaBlue()
                        : UIColor.black,
                    for:
                        .normal
                )
            }
        }
    }

    func actionSheet(
        _ actionSheet:
            UIActionSheet,
        clickedButtonAt
            buttonIndex:
                Int
    ) {
        guard
            actionSheet.tag == 7301
        else {
            return
        }

        if
            buttonIndex ==
                actionSheet.cancelButtonIndex
        {
            return
        }

        let mode:
            MagnistraDirectBackendMode

        switch buttonIndex {
        case 0:
            mode =
                .web
        case 1:
            mode =
                .matrix
        default:
            return
        }

        backendMode =
            mode

        MagnistraDirectBackendStore
            .set(
                mode
            )

        applyBackendMode(
            reload:
                true
        )
    }

    @objc private func newMessageTapped() {
        guard backendMode == .web else { return }
        let picker = MagnistraDirectNewMessageViewController()
        picker.onRecipientChosen = { [weak self, weak picker] user in
            guard let self = self, let picker = picker, self.backendMode == .web else { return }
            let targetID = user.userID
            guard targetID.rangeOfCharacter(
                from: CharacterSet.decimalDigits.inverted) == nil else { return }
            picker.view.isUserInteractionEnabled = false
            let currentThreads = self.threads
            self.loadQueue.addOperation { [weak self] in
                guard let self = self else { return }
                var found = currentThreads.first(where: {
                    !$0.isGroupConversation && $0.participantUserIDs.contains(targetID)
                })
                if found == nil {
                    found = try? MagnistraHomeService.resolveDirectForRecipient(userID: targetID)
                }
                let finalThread = found ?? MagnistraDirectThreadSummary(
                    threadFBID: "pending:" + targetID,
                    minUQSeqID: 0,
                    title: user.username,
                    username: user.username,
                    snippet: "", avatarURL: user.avatarURL,
                    lastActivityMilliseconds: 0,
                    isUnread: false,
                    participantUserIDs: [targetID], isGroupConversation: false)
                OperationQueue.main.addOperation { [weak self] in
                    guard let self = self, self.backendMode == .web else { return }
                    let chat = MagnistraDirectThreadViewController(summary: finalThread)
                    chat.hidesBottomBarWhenPushed = true
                    self.navigationController?.pushViewController(chat, animated: false)

                    if var stack = self.navigationController?.viewControllers,
                       let index = stack.firstIndex(where: { $0 === picker }) {
                        stack.remove(at: index)
                        self.navigationController?.setViewControllers(stack, animated: false)
                    }
                }
            }
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func setDirectControlsEnabled(
        _ enabled:
            Bool
    ) {
        backendButton?.isEnabled = enabled

        let webComposerEnabled = backendMode == .web
        newMessageButton?.isEnabled = webComposerEnabled
        (newMessageButton?.customView as? UIButton)?.isEnabled = webComposerEnabled
    }

    private func applyBackendMode(
        reload:
            Bool
    ) {
        threads.removeAll()

        tableView
            .reloadData()

        setDirectControlsEnabled(
            true
        )
        navigationItem.rightBarButtonItem =
            backendMode == .web ? newMessageButton : nil

        switch backendMode {
        case .web:
            if reload {
                showStatus(
                    "Loading Direct..."
                )

                loadInbox()
            }

        case .matrix:
            if reload {
                showStatus(
                    "Loading Matrix conversations..."
                )

                loadInbox()
            }

        case .hybrid:
            showStatus(
                "Matrix account is required for Hybrid mode."
            )
        }
    }

    private func loadInbox() {
        if loading {
            return
        }

        loading =
            true

        setDirectControlsEnabled(
            false
        )

        let requestedBackendMode =
            backendMode

        loadQueue.addOperation {
            [weak self] in

            do {
                let page =
                    try MagnistraDirectProviderFactory
                        .make(
                            requestedBackendMode
                        )
                        .loadInbox()

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        guard
                            let self =
                                self
                        else {
                            return
                        }

                        self.loading =
                            false
                        self.pullRefreshIndicator.end(on: self.navigationItem)

                        self.setDirectControlsEnabled(
                            true
                        )

                        self.threads =
                            page.threads

                        self.tableView
                            .reloadData()

                        if self.threads.isEmpty {
                            self.showStatus(
                                "No Direct conversations."
                            )
                        } else {
                            self.hideStatus()
                        }
                    }
            } catch {
                let message =
                    error.localizedDescription

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        self?.loading =
                            false
                        if let owner = self {
                            owner.pullRefreshIndicator.end(on: owner.navigationItem)
                        }

                        self?
                            .setDirectControlsEnabled(
                                true
                            )

                        self?
                            .showStatus(
                                message
                            )
                    }
            }
        }
    }

    private func showStatus(
        _ text:
            String
    ) {
        if NoConnectionBanner.showIfHTTPZero(text, on: view) {
            MagnistraBottomLoading.hide(on: view)
            tableView.backgroundView = nil
            return
        }
        NoConnectionBanner.hide(on: view)
        if text.hasPrefix("Loading") {
            tableView.backgroundView = nil
            MagnistraBottomLoading.show(on: view)
            return
        }
        MagnistraBottomLoading.hide(on: view)

        let label =
            UILabel(
                frame:
                    tableView.bounds
            )

        label.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        label.backgroundColor =
            UIColor.clear

        label.textAlignment =
            .center

        label.textColor =
            UIColor(
                white:
                    0.48,
                alpha:
                    1.0
            )

        label.font =
            UIFont.systemFont(
                ofSize:
                    12.0
            )

        label.numberOfLines =
            0

        label.text =
            text

        tableView.backgroundView =
            label
    }

    private func hideStatus() {
        NoConnectionBanner.hide(on: view)
        MagnistraBottomLoading.hide(on: view)
        tableView.backgroundView =
            nil
    }

    func tableView(
        _ tableView:
            UITableView,
        numberOfRowsInSection
            section:
                Int
    ) -> Int {
        return
            threads.count
    }

    func tableView(
        _ tableView:
            UITableView,
        cellForRowAt
            indexPath:
                IndexPath
    ) -> UITableViewCell {
        let cell =
            (
                tableView
                    .dequeueReusableCell(
                        withIdentifier:
                            reuseID
                    ) as?
                    MagnistraDirectInboxCell
            ) ??
            MagnistraDirectInboxCell(
                style:
                    .default,
                reuseIdentifier:
                    reuseID
            )

        cell.configure(
            threads[
                indexPath.row
            ]
        )

        cell.accessoryType =
            backendMode == .matrix
                ? .none
                : .disclosureIndicator

        return cell
    }

    func tableView(
        _ tableView:
            UITableView,
        didSelectRowAt
            indexPath:
                IndexPath
    ) {
        if backendMode == .matrix {
            tableView.deselectRow(
                at: indexPath,
                animated: true
            )

            let thread =
                threads[indexPath.row]

            let controller =
                MagnistraDirectThreadViewController(
                    summary: thread
                )

            controller.hidesBottomBarWhenPushed =
                true

            navigationController?
                .pushViewController(
                    controller,
                    animated: true
                )

            return
        }

        tableView.deselectRow(
            at:
                indexPath,
            animated:
                true
        )

        let thread =
            threads[
                indexPath.row
            ]

        let controller =
            MagnistraDirectThreadViewController(
                summary:
                    thread
            )

        controller.hidesBottomBarWhenPushed =
            true

        navigationController?
            .pushViewController(
                controller,
                animated:
                    true
            )
    }
}

