// Overview: Core declarations of MagnistraHomeService, the Instagram service layer.
@_silgen_name("magnistra_direct_voice_wav_to_ogg_opus")
func magnistraDirectVoiceWAVToOGG(
    _ wav: UnsafePointer<CChar>, _ ogg: UnsafePointer<CChar>) -> Int32

@_silgen_name("magnistra_direct_media_prepare_auth")
func magnistraDirectMediaPrepareAuth(
    _ ca: UnsafePointer<CChar>?, _ ua: UnsafePointer<CChar>?,
    _ lang: UnsafePointer<CChar>?, _ cookies: UnsafePointer<CChar>?,
    _ csrf: UnsafePointer<CChar>?) -> Int32
@_silgen_name("magnistra_direct_media_auth_dtsg")
func magnistraDirectMediaAuthDTSG() -> UnsafePointer<CChar>
@_silgen_name("magnistra_direct_media_auth_jazoest")
func magnistraDirectMediaAuthJazoest() -> UnsafePointer<CChar>

@_silgen_name("magnistra_direct_media_upload_response_type")
func magnistraDirectMediaResponseType() -> UnsafePointer<CChar>
@_silgen_name("magnistra_direct_media_upload_endpoint_matches")
func magnistraDirectMediaEndpointMatches() -> Int32

@_silgen_name("magnistra_direct_media_upload_curl")
func magnistraDirectMediaCurlUpload(
    _ ca: UnsafePointer<CChar>?, _ ua: UnsafePointer<CChar>?,
    _ lang: UnsafePointer<CChar>?, _ cookies: UnsafePointer<CChar>?,
    _ csrf: UnsafePointer<CChar>?, _ mime: UnsafePointer<CChar>?,
    _ bytes: UnsafePointer<UInt8>?, _ length: Int) -> Int32

@_silgen_name("magnistra_direct_media_response_data")
func magnistraDirectMediaResponseData() -> UnsafePointer<UInt8>?

@_silgen_name("magnistra_direct_media_response_length")
func magnistraDirectMediaResponseLength() -> Int

@_silgen_name("magnistra_direct_media_upload_http_status")
func magnistraDirectMediaHTTPStatus() -> Int

import Foundation
import UIKit
import CoreFoundation

@_silgen_name("MagnistraWebPDecodeThumbnailRGBA")
func magnistraWebPDecodeThumbnailRGBA(
    _ input: UnsafePointer<UInt8>?, _ byteCount: Int,
    _ maxEdge: Int32, _ output: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ width: UnsafeMutablePointer<Int32>?,
    _ height: UnsafeMutablePointer<Int32>?
) -> Int32

@_silgen_name("MagnistraWebPFreeThumbnail")
func magnistraWebPFreeThumbnail(_ pixels: UnsafeMutablePointer<UInt8>?)

@_silgen_name("magnistra_archive_web_read")
func magnistraArchiveWebRead(
    _ ca: UnsafePointer<CChar>?, _ agent: UnsafePointer<CChar>?,
    _ language: UnsafePointer<CChar>?, _ cookies: UnsafePointer<CChar>?,
    _ csrf: UnsafePointer<CChar>?, _ url: UnsafePointer<CChar>?,
    _ postBody: UnsafePointer<CChar>?
) -> Int32

@_silgen_name("magnistra_archive_web_fields")
func magnistraArchiveWebFields() -> Int32
@_silgen_name("magnistra_archive_header_bytes")
func magnistraArchiveHeaderBytes() -> Int32
@_silgen_name("magnistra_archive_mime_kind")
func magnistraArchiveMimeKind() -> Int32

enum MagnistraHomeService {

    struct PostActionMetadata {
        var liked: Bool
        var saved: Bool
        var following: Bool?
        var trackingToken: String
        var loggingInfoToken: String
        var inventorySource: String
        var navChain: String
        var repostCount: Int
        var shareCount: Int
        var reposted: Bool
        var repostNoteID: String?
    }

    static let postActionMetadataLock =
        NSLock()

    static var postActionMetadataByMediaID:
        [String: PostActionMetadata] =
            [:]

    static var postActionFollowingByUserID:
        [String: Bool] =
            [:]

    static var postActionLikeCountByMediaID:
        [String: Int] =
            [:]

    static var postActionMutationCounter:
        Int = 0

    struct MagnistraMetadataIndex {
        var ints: [String: Int] = [:]
        var strings: [String: String] = [:]
        var repostCandidates: [MagnistraRepostCandidate] = []
    }

        struct MagnistraRepostCandidate {
        let userID: String?
        let noteID: String
        let anonymousAllowed: Bool
    }

    static var timelineSeenMediaIDs:
        [String] = []

    static let timelineSeenMediaLimit =
        80

    static let avatarCacheMaxBytes =
        16 * 1024 * 1024

    static let avatarCacheMaxEntries =
        250

    static let avatarTTL:
        TimeInterval =
            24.0 * 60.0 * 60.0

    static let postCacheMaxBytes =
        64 * 1024 * 1024

    static let postCacheMaxEntries =
        120

    static let profileMediaLock = NSLock()

    static let exploreLock = NSLock()

    static var magnistraWebReelSeenIDs = [String]()

    static let exploreSearchLock =
        NSLock()

    static let magnistraWebMediaUploadLock = NSLock()

}

