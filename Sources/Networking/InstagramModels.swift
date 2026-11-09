// Overview: Instagram data models: photo quality, media preferences, activity items.
import Foundation
import UIKit
import CoreFoundation

enum MagnistraPhotoQuality:
    Int
{
    case standard = 0
    case retina = 1
    case highest = 2

    var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .retina:
            return "Retina"
        case .highest:
            return "Highest"
        }
    }

    var cacheToken: String {
        switch self {
        case .standard:
            return "standard"
        case .retina:
            return "retina"
        case .highest:
            return "highest"
        }
    }

    var targetWidth: Int {
        switch self {
        case .standard:
            return 320
        case .retina:
            return 640
        case .highest:
            return Int.max
        }
    }
}

final class MagnistraMediaPreferences:
    NSObject
{
    static let photoQualityKey =
        "MagnistraPhotoQuality"

    static let videoQualityKey =
        "MagnistraVideoQuality"

    static var photoQuality:
        MagnistraPhotoQuality
    {
        guard let saved = UserDefaults.standard.object(forKey: photoQualityKey) as? NSNumber else {
            return .retina
        }
        return MagnistraPhotoQuality(rawValue: saved.intValue) ?? .retina
    }

    static func setPhotoQuality(
        _ quality:
            MagnistraPhotoQuality
    ) {
        UserDefaults.standard.set(
            quality.rawValue,
            forKey:
                photoQualityKey
        )

        UserDefaults.standard.synchronize()
    }
}

struct MagnistraActivityItem {
    let activityID: String
    let text: String
    let createdAt: Double

    let userID: String
    let username: String
    let fullName: String
    let avatarURL: String?

    let mediaID: String?
    let mediaImageURL: String?
    let referencePost: MagnistraRealPost?
    let referencedShortcode: String?
}

struct MagnistraActivityPage {
    let items: [MagnistraActivityItem]
}

struct MagnistraComment {
    let commentID: String
    let username: String
    let text: String
    let createdAt: Double
    let avatarURL: String?
    let likeCount: Int
    let hasLiked: Bool
    let parentCommentID: String?
    let childCommentCount: Int
    let giphyURL: String?
    let giphyWidth: Int
    let giphyHeight: Int
}

struct MagnistraCarouselMedia {
    let mediaID: String
    let imageURL: String
    let videoURL: String?
    let videoWidth: Int
    let videoHeight: Int
}

struct MagnistraRealPost {
    let mediaID: String
    let userID: String
    let username: String
    let fullName: String
    let caption: String
    let commentCount: Int
    let previewComments: [MagnistraComment]
    let likes: Int
    let location: String
    let takenAt: Double
    let imagePath: String
    let imageURL: String
    let imageCacheKey: String
    let avatarPath: String?
    let avatarURL: String?
    let avatarCacheKey: String
    let musicTitle: String?
    let musicArtist: String?
    let musicAudioURL: String?
    let musicStartTimeMs: Int
    let photoMusicImageURLFallback: String?
    let videoURL: String?
    let videoWidth: Int
    let videoHeight: Int
    var isVideo: Bool = false
    var shortcode: String = ""
    var carouselMedia: [MagnistraCarouselMedia] = []
}

struct MagnistraCommentsPage {
    let comments: [MagnistraComment]
    let nextMaxID: String?
}

struct MagnistraProfileMediaPage {
    let posts: [MagnistraRealPost]
    let nextMaxID: String?
}

struct MagnistraProfileInfo {
    let userID: String
    let username: String
    let fullName: String
    let biography: String
    let profilePicURL: String?
    let profilePicURLFallback: String?
    let followerCount: Int
    let followingCount: Int
    let mediaCount: Int
    let isPrivate: Bool
    let viewerFollows: Bool?
}

final class MagnistraHomePageRequest: NSObject {
    let maxID: String?
    let replacesFeed: Bool

    init(
        maxID: String?,
        replacesFeed: Bool
    ) {
        self.maxID = maxID
        self.replacesFeed = replacesFeed
        super.init()
    }
}

final class MagnistraHomeLoadResult: NSObject {
    let posts: [MagnistraRealPost]
    let nextMaxID: String?
    let replacesFeed: Bool
    let errorText: String?

    init(
        posts: [MagnistraRealPost],
        nextMaxID: String?,
        replacesFeed: Bool,
        errorText: String?
    ) {
        self.posts = posts
        self.nextMaxID = nextMaxID
        self.replacesFeed = replacesFeed
        self.errorText = errorText
        super.init()
    }
}

struct MagnistraSessionInput {
    let userAgent: String
    let language: String
    let cookieHeader: String
    let csrfToken: String
}

enum MagnistraMediaCacheKind {
    case avatar
    case post
}

struct MagnistraExplorePage {
    let posts: [MagnistraRealPost]
    let nextMaxID: String?
}

struct MagnistraExploreTwelveBatch {
    let page: MagnistraExplorePage
    let deferredPosts: [MagnistraRealPost]
    let deferredNextMaxID: String?
}

struct MagnistraReelsPage {
    let posts: [MagnistraRealPost]
    let nextMaxID: String?
}

struct MagnistraExploreSearchUser {
    let userID: String
    let username: String
    let fullName: String
    let avatarURL: String?
    let isVerified: Bool
}

struct MagnistraExploreUserSearchPage {
    let users: [MagnistraExploreSearchUser]
    let rankToken: String
}

struct MagnistraExploreTagSearchItem {
    let mediaID: String
    let shortcode: String
    let thumbnailURL: String
    let isVideo: Bool
}

struct MagnistraExploreTagSearchPage {
    let items: [MagnistraExploreTagSearchItem]
    let endCursor: String?
    let hasNextPage: Bool
}

struct MagnistraDirectThreadSummary {
    let threadFBID: String
    let minUQSeqID: Int
    let title: String
    let username: String
    let snippet: String
    let avatarURL: String?
    let lastActivityMilliseconds: Double
    let isUnread: Bool
    let participantUserIDs: [String]
    let isGroupConversation: Bool
}

struct MagnistraDirectSendResult {
    let messageID: String
    let timestampMilliseconds: Double
}

struct MagnistraDirectInboxPage {
    let threads: [MagnistraDirectThreadSummary]
    let endCursor: String?
    let hasNextPage: Bool
}

struct MagnistraDirectMessage {
    let messageID: String
    let text: String
    let detailText: String?
    let previewURL: String?
    let contentType: String
    let timestampMilliseconds: Double
    let isOutgoing: Bool
    let audioURL: String?
    let audioDurationMilliseconds: Double
    let mediaURL: String?
    let targetURL: String?
    let mediaKind: String
    let audioWaveform: [Double]
    let mediaAspectRatio: Double
    let senderID: String
    let senderName: String

    init(
        messageID:
            String,
        text:
            String,
        detailText:
            String?,
        previewURL:
            String?,
        contentType:
            String,
        timestampMilliseconds:
            Double,
        isOutgoing:
            Bool,
        audioURL:
            String? = nil,
        audioDurationMilliseconds:
            Double = 0.0
,
        mediaURL:
            String? = nil,
        targetURL:
            String? = nil,
        mediaKind:
            String = ""
,
        audioWaveform:
            [Double] = []
,
        mediaAspectRatio:
            Double = 1.0,
        senderID: String = "",
        senderName: String = ""
    ) {
        self.messageID =
            messageID

        self.text =
            text

        self.detailText =
            detailText

        self.previewURL =
            previewURL

        self.contentType =
            contentType

        self.timestampMilliseconds =
            timestampMilliseconds

        self.isOutgoing =
            isOutgoing

        self.audioURL =
            audioURL

        self.audioDurationMilliseconds =
            audioDurationMilliseconds

        self.mediaURL =
            mediaURL

        self.targetURL =
            targetURL

        self.mediaKind =
            mediaKind

        self.audioWaveform =
            audioWaveform

        self.mediaAspectRatio =
            mediaAspectRatio

        self.senderID = senderID
        self.senderName = senderName
    }
}

struct MagnistraDirectThreadPayload {
    let threadFBID: String
    let title: String
    let messages: [MagnistraDirectMessage]
    let startCursor: String?
    let hasPreviousPage: Bool
}

struct MagnistraPostInteractionState {
    let liked: Bool
    let saved: Bool
}

struct MagnistraPostSocialState {
    let reposted: Bool
    let reposts: Int
    let shares: Int
}

struct MagnistraStoryReel {
    let id: String
    let title: String
    let avatarURL: String
    let isSeen: Bool
    let rank: Int
    let highlight: Bool
}

struct MagnistraStorySlide {
    let imageURL: String
    let videoURL: String
    let username: String
    let timestamp: Double
    let mediaPK: String
    let ownerID: String
    init(imageURL: String, videoURL: String, username: String,
         timestamp: Double, mediaPK: String = "", ownerID: String = "") {
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.username = username
        self.timestamp = timestamp
        self.mediaPK = mediaPK
        self.ownerID = ownerID
    }
}

struct MagnistraArchiveDay {
    let id: String
    let mediaCount: Int
    let timestamp: Double
}

enum MagnistraDirectMediaTrace {
    static func record(_ stage: String, id: String = "", info: String = "") { }
    static func urlTag(_ value: String?) -> String { return "" }
    static func describeNode(_ node: [String: Any]) -> String { return "" }
}

struct MagnistraIGCatalogEntry {
    let id: String
    let kind: String
    let previewURL: String?
    let label: String
    let width: Int
    let height: Int
}

