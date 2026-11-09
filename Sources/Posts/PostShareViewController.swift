// Overview: Share-post screen.
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

final class MagnistraPostShareViewController:
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate
{
    private let post:
        MagnistraRealPost

    private let tableView =
        UITableView(
            frame: CGRect.zero,
            style: .plain
        )

    private let loadQueue =
        OperationQueue()
    private let imageQueue = OperationQueue()

    private var threads:
        [MagnistraDirectThreadSummary] =
            []

    private var loading =
        false
    private let backendPicker = UISegmentedControl(items: ["Instagram", "Matrix"])
    private var lastLoadedMode = -1
    private var displayedBackendMode = -1
    private var matrixSharePending = false

    init(
        post: MagnistraRealPost
    ) {
        self.post = post
        super.init(
            nibName: nil,
            bundle: nil
        )

        loadQueue
            .maxConcurrentOperationCount =
                1
        imageQueue.maxConcurrentOperationCount = 2
    }

    required init?(
        coder: NSCoder
    ) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Share"

        view.backgroundColor =
            UIColor.white

        tableView.dataSource =
            self
        tableView.delegate =
            self
        tableView.rowHeight =
            58.0
        tableView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        view.addSubview(tableView)
        backendPicker.selectedSegmentIndex = 0
        backendPicker.addTarget(self, action: #selector(changeShareBackend),
                                for: .valueChanged)
        view.addSubview(backendPicker)
        loadThreads()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = view.bounds.width
        backendPicker.frame = CGRect(x: 12, y: 8, width: max(1, width-24), height: 30)
        tableView.frame = CGRect(x: 0, y: 44, width: width,
                                 height: max(1, view.bounds.height - 44))
    }

    @objc private func changeShareBackend() {

        displayedBackendMode = -1
        threads.removeAll()
        tableView.reloadData()
        if !loading { loadThreads() }
    }

    private func loadThreads() {
        if loading { return }
        loading = true
        displayedBackendMode = -1
        threads.removeAll()
        tableView.reloadData()
        let matrixMode = backendPicker.selectedSegmentIndex == 1
        lastLoadedMode = matrixMode ? 1 : 0
        loadQueue.addOperation { [weak self] in
            do {
                let page = matrixMode
                    ? try MagnistraMatrixDirectService.loadInbox()
                    : try MagnistraHomeService.loadDirectInbox()
                if matrixMode {
                    MatrixSession.makeAPIClient().get(
                        "/_matrix/client/v3/joined_rooms", timeout: 30) { [weak self] response, membershipError in
                        OperationQueue.main.addOperation {
                            guard let owner = self else { return }
                            owner.loading = false
                            if owner.backendPicker.selectedSegmentIndex != owner.lastLoadedMode {
                                owner.loadThreads()
                                return
                            }
                            guard membershipError == nil,
                                  let joinedRooms = response?["joined_rooms"] as? [String] else {
                                UIAlertView(title: "Share", message: "Could not load joined Matrix conversations.",
                                            delegate: nil, cancelButtonTitle: "OK").show()
                                return
                            }
                            let joined = Set(joinedRooms)
                            owner.threads = page.threads.filter {
                                $0.threadFBID.hasPrefix("!") && joined.contains($0.threadFBID)
                            }
                            owner.displayedBackendMode = 1
                            owner.tableView.reloadData()
                        }
                    }
                    return
                }
                OperationQueue.main.addOperation { [weak self] in
                    guard let owner = self else { return }
                    owner.loading = false
                    if owner.backendPicker.selectedSegmentIndex != owner.lastLoadedMode {
                        owner.loadThreads()
                        return
                    }
                    owner.threads = page.threads
                    owner.displayedBackendMode = 0
                    owner.tableView.reloadData()
                }
            } catch {
                let message = error.localizedDescription
                OperationQueue.main.addOperation { [weak self] in
                    guard let owner = self else { return }
                    owner.loading = false
                    if owner.backendPicker.selectedSegmentIndex != owner.lastLoadedMode {
                        owner.loadThreads()
                        return
                    }
                    UIAlertView(title: "Share", message: message,
                                delegate: nil, cancelButtonTitle: "OK").show()
                }
            }
        }
    }

    private func permalink()
        -> String?
    {
        if !post.shortcode.isEmpty {
            let route = post.isVideo ? "reel" : "p"
            return "https://www.instagram.com/" + route + "/" + post.shortcode + "/"
        }
        let rawID =
            post.mediaID
                .split(
                    separator: "_",
                    omittingEmptySubsequences:
                        true
                )
                .first
                .map(String.init) ??
            post.mediaID

        guard var value =
            UInt64(rawID)
        else {
            return nil
        }

        let alphabet =
            Array(
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
            )

        var chars:
            [Character] = []

        repeat {
            let index =
                Int(
                    value %
                    64
                )

            chars.append(
                alphabet[index]
            )

            value /=
                64
        } while value > 0

        let shortcode =
            String(
                chars.reversed()
            )

        let route =
            post.videoURL != nil
                ? "reel"
                : "p"

        return
            "https://www.instagram.com/" +
            route +
            "/" +
            shortcode +
            "/"
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

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseID = "MagnistraPostShareThread"
        let cell = (tableView.dequeueReusableCell(withIdentifier: reuseID)
                    as? MagnistraExploreSearchUserCell) ??
            MagnistraExploreSearchUserCell(style: .default, reuseIdentifier: reuseID)
        let thread = threads[indexPath.row]
        cell.representedID = thread.threadFBID
        cell.usernameLabel.text = thread.title.isEmpty ? thread.username : thread.title
        cell.fullNameLabel.text = thread.username
        cell.avatarView.image = nil
        cell.accessoryType = .none
        if let avatarURL = thread.avatarURL, !avatarURL.isEmpty {
            let representedID = thread.threadFBID
            imageQueue.addOperation { [weak cell] in
                guard let path = MagnistraHomeService.materializeFeedImage(
                    url: avatarURL, stableKey: "share-thread-avatar:" + representedID,
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

    func tableView(
        _ tableView:
            UITableView,
        didSelectRowAt
            indexPath:
                IndexPath
    ) {
        tableView.deselectRow(
            at: indexPath,
            animated: true
        )

        guard !loading, displayedBackendMode == backendPicker.selectedSegmentIndex else { return }

        guard
            indexPath.row >= 0,
            indexPath.row <
                threads.count,
            let url =
                permalink()
        else {
            return
        }

        let thread = threads[indexPath.row]
        if backendPicker.selectedSegmentIndex == 1 {
            guard !matrixSharePending, thread.threadFBID.hasPrefix("!") else { return }
            matrixSharePending = true

            MagnistraMatrixDirectBackend.shared.sendText(roomId: thread.threadFBID,
                                                           text: url) { [weak self] _, error in
                OperationQueue.main.addOperation { [weak self] in
                    guard let owner = self else { return }
                    owner.matrixSharePending = false
                    if let error = error {
                        UIAlertView(title: "Share", message: error.localizedDescription,
                                    delegate: nil, cancelButtonTitle: "OK").show()
                    } else {
                        owner.navigationController?.popViewController(animated: true)
                    }
                }
            }
            return
        }

        loadQueue.addOperation {
            [weak self] in

            do {
                _ =
                    try MagnistraHomeService
                        .sendDirectText(
                            threadFBID:
                                thread.threadFBID,
                            minUQSeqID:
                                thread.minUQSeqID,
                            text:
                                url
                        )

                OperationQueue.main
                    .addOperation {
                        [weak self] in

                        let alert =
                            UIAlertView(
                                title:
                                    "Share",
                                message:
                                    "Post sent.",
                                delegate:
                                    nil,
                                cancelButtonTitle:
                                    "OK"
                            )

                        alert.show()

                        self?
                            .navigationController?
                            .popViewController(
                                animated:
                                    true
                            )
                    }
            } catch {
                let message =
                    error.localizedDescription

                OperationQueue.main
                    .addOperation {
                        let alert =
                            UIAlertView(
                                title:
                                    "Share",
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
}

