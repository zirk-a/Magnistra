// Overview: Profile grid tiles and the post detail screen.
import UIKit

final class MagnistraProfileGridTile: UIControl {
    let imageView = UIImageView()
    var index = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.clear
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.cgColor
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
    }
}

final class MagnistraProfileDetailVideoButton:
    UIButton
{
    var mediaID = ""
}

final class MagnistraProfilePostViewController:
    UIViewController,
    UITableViewDataSource,
    UITableViewDelegate
{
    private let post:
        MagnistraRealPost

    private let tableView =
        UITableView(
            frame:
                CGRect.zero,
            style:
                .plain
        )

    private var expanded =
        false

    private let videoButtonTag =
        74510

    init(
        post:
            MagnistraRealPost
    ) {
        self.post =
            post

        super.init(
            nibName:
                nil,
            bundle:
                nil
        )
    }

    required init?(
        coder: NSCoder
    ) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title =
            post.username

        view.backgroundColor =
            UIColor(
                white:
                    0.94,
                alpha:
                    1.0
            )

        tableView.dataSource =
            self

        tableView.delegate =
            self

        tableView.separatorStyle =
            .none

        tableView.autoresizingMask = [
            .flexibleWidth,
            .flexibleHeight
        ]

        view.addSubview(
            tableView
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        tableView.frame =
            view.bounds
    }

    override func viewWillDisappear(
        _ animated:
            Bool
    ) {
        super.viewWillDisappear(
            animated
        )

        MagnistraInlineVideoPlayer
            .shared
            .stopIfMediaID(
                post.mediaID
            )

        MagnistraPhotoMusicPlayer
            .shared
            .stopIfMediaID(
                post.mediaID
            )
    }

    func tableView(
        _ tableView:
            UITableView,
        numberOfRowsInSection
            section:
            Int
    ) -> Int {
        return 1
    }

    func tableView(
        _ tableView:
            UITableView,
        cellForRowAt
            indexPath:
            IndexPath
    ) -> UITableViewCell {
        let cell =
            MagnistraPostCell(
                style:
                    .default,
                reuseIdentifier:
                    nil
            )

        cell.onProfileTap = {
            [weak self] in

            guard
                let self =
                    self
            else {
                return
            }

            self.navigationController?
                .pushViewController(
                    MagnistraProfileViewController(
                        post:
                            self.post
                    ),
                    animated:
                        true
                )
        }

        cell.onCaptionToggle = {
            [weak self] in

            guard
                let self =
                    self
            else {
                return
            }

            self.expanded =
                !self.expanded

            self.tableView
                .reloadData()
        }

        cell.onCommentsTap = {
            [weak self] in

            guard
                let self =
                    self
            else {
                return
            }

            self.navigationController?
                .pushViewController(
                    MagnistraCommentsViewController(
                        post:
                            self.post
                    ),
                    animated:
                        true
                )
        }

        cell.configure(
            post:
                post,
            avatarVariant:
                0,
            expanded:
                expanded
        )

        MagnistraInlineVideoPlayer
            .shared
            .prepare(
                hostView:
                    cell.contentView,
                mediaID:
                    post.mediaID
            )

        cell.contentView
            .viewWithTag(
                videoButtonTag
            )?
            .removeFromSuperview()

        if post.videoURL != nil {
            let width =
                max(
                    1.0,
                    tableView.bounds
                        .size.width
                )

            let size:
                CGFloat =
                    48.0

            let button =
                MagnistraProfileDetailVideoButton(
                    frame:
                        CGRect(
                            x:
                                (
                                    width -
                                    size
                                ) /
                                2.0,
                            y:
                                46.0 +
                                (
                                    width -
                                    size
                                ) /
                                2.0,
                            width:
                                size,
                            height:
                                size
                        )
                )

            button.tag =
                videoButtonTag

            button.mediaID =
                post.mediaID

            button.backgroundColor =
                UIColor(
                    white:
                        0.0,
                    alpha:
                        0.58
                )

            button.setTitleColor(
                UIColor.white,
                for:
                    .normal
            )

            button.titleLabel?
                .font =
                    UIFont.boldSystemFont(
                        ofSize:
                            22.0
                    )

            button.layer.cornerRadius =
                24.0

            button.layer.masksToBounds =
                true

            let active =
                MagnistraInlineVideoPlayer
                    .shared
                    .activeMediaID ==
                post.mediaID

            button.setTitle(
                active
                    ? "II"
                    : "▶",
                for:
                    .normal
            )

            button.addTarget(
                self,
                action:
                    #selector(
                        detailVideoTapped(
                            _:
                        )
                    ),
                for:
                    .touchUpInside
            )

            cell.contentView
                .addSubview(
                    button
                )
        }

        return cell
    }

    func tableView(
        _ tableView:
            UITableView,
        heightForRowAt
            indexPath:
            IndexPath
    ) -> CGFloat {
        return MagnistraPostCell
            .rowHeight(
                post:
                    post,
                expanded:
                    expanded,
                width:
                    tableView.bounds
                        .size.width
            )
    }

    @objc private func detailVideoTapped(
        _ sender:
            MagnistraProfileDetailVideoButton
    ) {
        let player =
            MagnistraInlineVideoPlayer
                .shared

        if
            player.activeMediaID ==
                post.mediaID
        {
            if
                let playing =
                    player.toggle(
                        mediaID:
                            post.mediaID
                    )
            {
                sender.setTitle(
                    playing
                        ? "II"
                        : "▶",
                    for:
                        .normal
                )
            }

            return
        }

        guard
            let host =
                sender.superview
        else {
            return
        }

        MagnistraPhotoMusicPlayer
            .shared
            .stop()

        sender.setTitle(
            "...",
            for:
                .normal
        )

        let width =
            max(
                1.0,
                tableView.bounds
                    .size.width
            )

        let started =
            player.start(
                post:
                    post,
                hostView:
                    host,
                frame:
                    CGRect(
                        x:
                            0.0,
                        y:
                            46.0,
                        width:
                            width,
                        height:
                            width
                    )
            )

        sender.setTitle(
            started
                ? "II"
                : "▶",
            for:
                .normal
        )

        if started {
            host.bringSubviewToFront(
                sender
            )
        }
    }
}
