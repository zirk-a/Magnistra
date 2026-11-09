// Overview: Direct thread: playback of voice messages and its progress UI.
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


    func updateDirectVoicePlaybackUI(
        messageID:
            String,
        progress:
            Double,
        elapsedMilliseconds:
            Double,
        playing:
            Bool
    ) {
        guard
            let index =
                messages.firstIndex(
                    where: {
                        $0.messageID ==
                            messageID
                    }
                )
        else {
            return
        }

        let indexPath =
            self.magnistraDirectPath(forMessage: index)

        if
            let cell =
                tableView.cellForRow(
                    at:
                        indexPath
                ) as?
                    MagnistraDirectVoiceCell
        {
            cell.setPlayback(
                progress:
                    progress,
                elapsedMilliseconds:
                    elapsedMilliseconds,
                playing:
                    playing
            )
        }
    }

    func stopDirectAudioProgressTimer() {
        directAudioProgressTimer?
            .invalidate()

        directAudioProgressTimer =
            nil
    }

    func resetDirectVoicePlaybackUI(
        messageID:
            String
    ) {
        updateDirectVoicePlaybackUI(
            messageID:
                messageID,
            progress:
                0.0,
            elapsedMilliseconds:
                0.0,
            playing:
                false
        )
    }

    func startDirectAudioProgressTimer() {
        stopDirectAudioProgressTimer()

        directAudioProgressTimer =
            Timer.scheduledTimer(
                timeInterval:
                    0.05,
                target:
                    self,
                selector:
                    #selector(
                        directAudioProgressTick(
                            _:
                        )
                    ),
                userInfo:
                    nil,
                repeats:
                    true
            )

        directAudioProgressTick(
            directAudioProgressTimer!
        )
    }

    @objc func directAudioProgressTick(
        _ timer:
            Timer
    ) {
        guard
            let player =
                directAudioPlayer,
            !directAudioMessageID.isEmpty
        else {
            stopDirectAudioProgressTimer()
            return
        }

        let duration =
            max(
                0.001,
                player.duration
            )

        let progress =
            max(
                0.0,
                min(
                    1.0,
                    player.currentTime /
                    duration
                )
            )

        let messageID =
            directAudioMessageID

        updateDirectVoicePlaybackUI(
            messageID:
                messageID,
            progress:
                progress,
            elapsedMilliseconds:
                player.currentTime *
                1000.0,
            playing:
                player.isPlaying
        )

        if
            !player.isPlaying,
            player.currentTime >
                0.0
        {
            stopDirectAudioProgressTimer()

            directAudioPlayer =
                nil

            directAudioMessageID =
                ""

            directAudioRequestToken =
                ""

            resetDirectVoicePlaybackUI(
                messageID:
                    messageID
            )
        }
    }

    func playDirectVoiceMessage(
        _ message:
            MagnistraDirectMessage
    ) {
        guard
            let remoteURL =
                message.audioURL,
            !remoteURL.isEmpty
        else {
            return
        }

        if
            directAudioMessageID ==
                message.messageID,
            let player =
                directAudioPlayer,
            player.isPlaying
        {
            let stoppedID =
                directAudioMessageID

            player.stop()

            stopDirectAudioProgressTimer()

            directAudioPlayer =
                nil

            directAudioMessageID =
                ""

            directAudioRequestToken =
                ""

            resetDirectVoicePlaybackUI(
                messageID:
                    stoppedID
            )

            return
        }

        let previousID =
            directAudioMessageID

        directAudioPlayer?
            .stop()

        stopDirectAudioProgressTimer()

        directAudioPlayer =
            nil

        directAudioMessageID =
            ""

        if !previousID.isEmpty {
            resetDirectVoicePlaybackUI(
                messageID:
                    previousID
            )
        }

        let messageID =
            message.messageID

        directAudioRequestToken =
            messageID

        directAudioQueue.addOperation {
            [weak self] in

            autoreleasepool {
                guard let url = URL(string: remoteURL) else { return }
                let originalData: Data?
                if let direct = MagnistraDirectMediaDiskCache.cachedVoice(url, key: messageID) {
                    originalData = direct
                } else if let path = MagnistraHomeService.materializeFeedImage(
                        url: remoteURL,
                        stableKey: "direct-voice-" + messageID,
                        isAvatar: false) {
                    originalData = NSData(contentsOfFile: path) as Data?
                } else {
                    originalData = nil
                }
                guard let received = originalData,
                      let data = magnistraDirectLegacyPlayableAudio(received) else { return }

                do {
                    let player =
                        try AVAudioPlayer(
                            data:
                                data
                        )

                    player.prepareToPlay()

                    OperationQueue.main
                        .addOperation {
                            [weak self] in

                            guard
                                let self =
                                    self,
                                self.directAudioRequestToken ==
                                    messageID
                            else {
                                return
                            }

                            let previousID =
                                self.directAudioMessageID

                            self.directAudioPlayer?
                                .stop()

                            self.stopDirectAudioProgressTimer()

                            if !previousID.isEmpty {
                                self.resetDirectVoicePlaybackUI(
                                    messageID:
                                        previousID
                                )
                            }

                            self.directAudioPlayer =
                                player

                            self.directAudioMessageID =
                                messageID

                            player.currentTime =
                                0.0

                            player.play()

                            self.startDirectAudioProgressTimer()
                        }
                } catch {
                    return
                }
            }
        }
    }
}
