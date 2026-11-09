// Overview: Explore feed: saved and reposts feed modes.
import UIKit
import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import Security
import QuartzCore
import CoreText
import ImageIO
import SystemConfiguration

extension MagnistraExploreFeedViewController {

    func magnistraUseSavedFeed() { magnistraSavedFeed = true }
    func magnistraUseRepostsFeed(userID: String) {
        if !userID.isEmpty { magnistraRepostsUserID = userID }
    }

    func savedPostRequiresMetadata(_ post: MagnistraRealPost) -> Bool {
        return magnistraSavedFeed && post.videoURL == nil &&
            post.musicAudioURL == nil && post.carouselMedia.count < 2 &&
            !savedMetadataCompleted.contains(post.mediaID)
    }

    func resolveVisibleSavedVideoIfNeeded(
        _ post: MagnistraRealPost
    ) {

        guard magnistraSavedFeed || magnistraRepostsUserID != nil else { return }
        guard MagnistraProfileMediaOpeningGate.needsDetails(post),
            !savedVideoRequested.contains(post.mediaID) else { return }
        savedVideoRequested.insert(post.mediaID)
        savedVideoResolveQueue.addOperation { [weak self] in
            let rich = try? MagnistraHomeService.loadProfileRichOpenPost(original: post)
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self, let playable = rich,
                    let idx = self.posts.firstIndex(where: { $0.mediaID == post.mediaID })
                else { return }
                self.posts[idx] = playable
                self.prewarmedPostCells.removeValue(forKey: post.mediaID)
                self.prewarmCompletedMediaIDs.remove(post.mediaID)
                self.savedVideoPendingRows.insert(idx)
                self.perform(#selector(self.refreshResolvedSavedVideos),
                    with: nil, afterDelay: 0.22)
            }
        }
    }

    @objc func refreshResolvedSavedVideos() {
        guard !tableView.isDragging && !tableView.isDecelerating else {
            perform(#selector(refreshResolvedSavedVideos),
                with: nil, afterDelay: 0.35)
            return
        }
        let visible = Set((tableView.indexPathsForVisibleRows ?? []).map { $0.row })
        let redraw = savedVideoPendingRows.intersection(visible)
        savedVideoPendingRows.subtract(redraw)

        for row in redraw.sorted() {
            guard row < posts.count,
                  let cell = tableView.cellForRow(
                    at: IndexPath(row: row, section: 0)) as? MagnistraPostCell
            else { continue }
            let post = posts[row]
            cell.configure(post: post, avatarVariant: row,
                expanded: expandedMediaIDs.contains(post.mediaID),
                savedGridPreview: true)
            installMediaControls(in: cell, post: post)
            cell.savedMetadataPending = savedPostRequiresMetadata(post)
        }
    }
}
