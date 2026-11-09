// Overview: Direct thread (Matrix): playing voice messages and opening photos and videos.
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

extension MagnistraDirectThreadViewController {


    func playMatrixVoice(_ message: MagnistraDirectMessage) {
        guard let mxc = message.audioURL, mxc.hasPrefix("mxc://") else { return }
        let id = message.messageID
        if directAudioMessageID == id,
           let playing = directAudioPlayer, playing.isPlaying {
            playing.stop()
            stopDirectAudioProgressTimer()
            directAudioPlayer = nil
            directAudioMessageID = ""
            directAudioRequestToken = ""
            resetDirectVoicePlaybackUI(messageID: id)
            return
        }

        let previousID = directAudioMessageID
        directAudioPlayer?.stop()
        stopDirectAudioProgressTimer()
        directAudioPlayer = nil
        directAudioMessageID = ""
        directAudioRequestToken = id
        if !previousID.isEmpty { resetDirectVoicePlaybackUI(messageID: previousID) }

        MagnistraMatrixMediaStore.shared.materializeAudio(mxc: mxc) { [weak self] path in
            guard let self = self, let path = path else { return }
            self.directAudioQueue.addOperation { [weak self] in
                autoreleasepool {
                    guard let bytes = NSData(contentsOfFile: path) as Data?,
                          let decoded = magnistraDirectLegacyPlayableAudio(bytes),
                          let player = try? AVAudioPlayer(data: decoded) else {
                        OperationQueue.main.addOperation { [weak self] in
                            guard let self = self, self.directAudioRequestToken == id else { return }
                            self.directAudioRequestToken = ""
                            self.resetDirectVoicePlaybackUI(messageID: id)
                            self.showDirectOutboundError("This voice format could not be played.")
                        }
                        return
                    }
                    player.prepareToPlay()
                    OperationQueue.main.addOperation { [weak self] in
                        guard let self = self, self.directAudioRequestToken == id else { return }
                        self.directAudioPlayer?.stop()
                        self.stopDirectAudioProgressTimer()
                        self.directAudioPlayer = player
                        self.directAudioMessageID = id
                        player.currentTime = 0.0
                        if player.play() {
                            self.startDirectAudioProgressTimer()
                        } else {
                            self.directAudioPlayer = nil
                            self.directAudioMessageID = ""
                            self.directAudioRequestToken = ""
                            self.resetDirectVoicePlaybackUI(messageID: id)
                        }
                    }
                }
            }
        }
    }

    func openMatrixPhoto(
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

                let zoomPhoto = MagnistraDirectZoomingPhotoView(
                    frame: controller.view.bounds)
                zoomPhoto.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                controller.view.addSubview(zoomPhoto)
                zoomPhoto.show(image)

                self.navigationController?
                    .pushViewController(
                        controller,
                        animated:
                            true
                    )
            }
    }

    func openMatrixVideo(
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
}
