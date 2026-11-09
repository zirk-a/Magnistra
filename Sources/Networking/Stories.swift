// Overview: Stories: tray, highlights and story gallery loading.
import Foundation
import UIKit
import CoreFoundation

extension MagnistraHomeService {


static func magnistraDirectGIFBytes(urlString: String) -> Data? {

        let mediaTag = MagnistraDirectMediaTrace.urlTag(urlString)
        let traceThis = mediaTag == "fbcdn:unknown" || mediaTag == "instagram:unknown"
        func trace(_ state: String, _ extra: String = "") {
            if traceThis {
                MagnistraDirectMediaTrace.record("FETCH_" + state, info: extra)
            }
        }
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            trace("INVALID_URL")
            return nil
        }
        let permitted = ["instagram.com", "cdninstagram.com", "fbcdn.net",
                         "giphy.com", "giphyusercontent.com", "tenor.com", "tenor.co"]
        guard permitted.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else { trace("HOST_NOT_ALLOWED"); return nil }
        guard let session = try? loadSession() else {
            trace("NO_LOCAL_SESSION")
            return nil
        }
        guard let caPath = Bundle.main.path(forResource: "CACert", ofType: "pem")
        else { trace("MISSING_CA_BUNDLE"); return nil }
        trace("START", "host=fbcdn_or_instagram;format=" + mediaTag)
        guard let bytes = MagnistraLazyImageTransport.fetch(
            url: urlString, caPath: caPath, userAgent: session.userAgent) else {
            trace("TRANSPORT_NIL")
            return nil
        }
        let sizeClass: String
        if bytes.count == 0 { sizeClass = "empty" }
        else if bytes.count < 4096 { sizeClass = "tiny" }
        else if bytes.count < 131072 { sizeClass = "small" }
        else if bytes.count < 2097152 { sizeClass = "medium" }
        else { sizeClass = "large" }
        guard bytes.count >= 8 && bytes.count <= 8 * 1024 * 1024 else {
            trace("SIZE_REJECT", "size=" + sizeClass)
            return nil
        }
        let header = Array(bytes.prefix(12))
        let isGIF = Array(bytes.prefix(6)) == [71, 73, 70, 56, 55, 97]
            || Array(bytes.prefix(6)) == [71, 73, 70, 56, 57, 97]
        let isPNG = Array(header.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10]
        let isJPEG = header[0] == 255 && header[1] == 216 && header[2] == 255
        let isWebP = visitedGridWebPHeader(bytes)
        let isMP4 = header.count >= 8 && header[4] == 102 && header[5] == 116
            && header[6] == 121 && header[7] == 112
        let isHTML = header[0] == 60
        let family = isGIF ? "gif" : (isPNG ? "png" :
                     (isJPEG ? "jpeg" : (isWebP ? "webp" :
                     (isMP4 ? "mp4" : (isHTML ? "html_or_xml" : "other")))))
        trace("BYTES", "format=" + family + ";size=" + sizeClass)
        if isGIF || isPNG || isJPEG { return bytes }
        if isWebP {

            trace("WEBP_ORIGINAL_PRESERVED")
            return bytes
        }
        trace("FORMAT_UNSUPPORTED", "format=" + family)
        return nil
    }

    static func storyGalleryObject(_ object: Any?, depth: Int = 0) -> [String: Any]? {
        guard depth < 24 else { return nil }
        if let dictionary = object as? [String: Any] {
            if let found = dictionary["xdt_api__v1__feed__reels_tray"] as? [String: Any],
               found["tray"] is [Any] { return found }

            for (_, value) in dictionary {
                if let found = storyGalleryObject(value, depth: depth + 1) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = storyGalleryObject(value, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    static func storeStoryTrayProbe(_ state: String, _ http: Int,
                                             _ bytes: Int, _ scriptCount: Int,
                                             _ jsonCount: Int, _ resultCount: Int,
                                             _ markerCount: Int) {
        guard let docs = documentsPath() else { return }
        let path = (docs as NSString).appendingPathComponent("MagnistraStoryTray-Diagnostic.txt")
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    static func loadStoryTray() throws -> [MagnistraStoryReel] {
        var storyState = "SESSION"
        var storyHTTP = 0
        var storyBytes = 0
        var storyScripts = 0
        var storyJSON = 0
        var storyCount = 0
        var storyMarkerScripts = 0
        defer {
            storeStoryTrayProbe(storyState, storyHTTP, storyBytes,
                                storyScripts, storyJSON, storyCount,
                                storyMarkerScripts)
        }
        let session = try loadSession()
        guard let caPath = Bundle.main.path(forResource: "CACert", ofType: "pem") else {
            throw NSError(domain: "MagnistraStories", code: 7100,
                          userInfo: [NSLocalizedDescriptionKey: "CA certificate unavailable."])
        }
        exploreSearchLock.lock()
        defer { exploreSearchLock.unlock() }
        let site = "https://www.instagram.com/"
        let code = caPath.withCString { ca in
            session.userAgent.withCString { ua in
                session.language.withCString { lang in
                    session.cookieHeader.withCString { cookies in
                        session.csrfToken.withCString { csrf in
                            site.withCString { address in
                                Int32(magnistra_explore_rest_get(ca, ua, lang, cookies, csrf, address))
                            }
                        }
                    }
                }
            }
        }
        let http = magnistra_explore_search_http_status()
        storyHTTP = Int(http)
        storyState = code == 0 ? "HTTP" : "CURL_ERROR"
        guard code == 0, http >= 200, http < 300,
              magnistra_explore_search_tls_verify_result() == 0 else {
            throw NSError(domain: "MagnistraStories", code: Int(http),
                          userInfo: [NSLocalizedDescriptionKey: "Stories Home request unavailable."])
        }
        let length = Int(magnistra_explore_search_body_length())
        storyBytes = length
        storyState = "HTML_MISSING"
        guard length > 0, length < 12000000,
              let pointer = magnistra_explore_search_body(),
              let html = String(data: Data(bytes: pointer, count: length), encoding: .utf8) else {
            return []
        }

        var offset = html.startIndex
        var scriptCount = 0
        while scriptCount < 250,
              let opener = html.range(of: "<script", options: .caseInsensitive, range: offset..<html.endIndex),
              let tagEnd = html.range(of: ">", range: opener.upperBound..<html.endIndex),
              let closer = html.range(of: "</script>", options: .caseInsensitive,
                                     range: tagEnd.upperBound..<html.endIndex) {
            offset = closer.upperBound
            scriptCount += 1
            storyScripts = scriptCount
            let tag = String(html[opener.lowerBound..<tagEnd.upperBound]).lowercased()
            guard tag.contains("application/json") else { continue }
            storyJSON += 1
            let content = String(html[tagEnd.upperBound..<closer.lowerBound])
            guard content.contains("xdt_api__v1__feed__reels_tray") else { continue }
            storyMarkerScripts += 1
            guard let data = content.data(using: .utf8),
                  let parsed = try? MagnistraJSONKit.jsonObject(with: data, options: []),
                  let payload = storyGalleryObject(parsed),
                  let tray = payload["tray"] as? [[String: Any]] else { continue }
            var reels: [MagnistraStoryReel] = []
            var seenIDs = Set<String>()
            for item in tray {
                guard let user = item["user"] as? [String: Any],
                      let id = item["id"] as? String, !id.isEmpty,
                      let name = user["username"] as? String, !name.isEmpty,
                      !seenIDs.contains(id) else { continue }
                seenIDs.insert(id)
                let avatar = user["profile_pic_url"] as? String ?? ""
                let seen = (item["seen"] as? NSNumber)?.doubleValue ?? 0
                let latest = (item["latest_reel_media"] as? NSNumber)?.doubleValue ?? 0
                let rank = (item["ranked_position"] as? NSNumber)?.intValue ?? reels.count
                reels.append(MagnistraStoryReel(id: id, title: name, avatarURL: avatar,
                                                 isSeen: seen > 0 && seen >= latest,
                                                 rank: rank, highlight: false))
            }
            storyCount = reels.count
            storyState = reels.isEmpty ? "EMPTY_TRAY" : "OK"
            return reels.sorted { $0.rank < $1.rank }
        }
        storyState = storyJSON == 0 ? "NO_JSON_SCRIPTS" : "NO_TRAY_PAYLOAD"
        return []
    }

    static func loadStoryHighlights(userID: String) throws -> [MagnistraStoryReel] {
        guard !userID.isEmpty,
              userID.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil else { return [] }
        let root = try exploreSearchGraphQLRoot(
            variables: ["user_id": userID],
            docID: "26970053832668570",
            friendlyName: "PolarisProfileStoryHighlightsTrayContentQuery")
        guard let data = root["data"] as? [String: Any],
              let highlights = data["highlights"] as? [String: Any],
              let edges = highlights["edges"] as? [[String: Any]] else { return [] }
        var items: [MagnistraStoryReel] = []
        for edge in edges {
            guard let node = edge["node"] as? [String: Any],
                  let id = node["id"] as? String, !id.isEmpty else { continue }
            let cover = node["cover_media"] as? [String: Any] ?? [:]
            let cropped = cover["cropped_image_version"] as? [String: Any] ?? [:]
            let imageURL = cropped["url"] as? String ?? (cover["url"] as? String ?? "")
            let title = node["title"] as? String ?? "Highlights"
            items.append(MagnistraStoryReel(id: id, title: title, avatarURL: imageURL,
                                            isSeen: true, rank: items.count, highlight: true))
        }
        return items
    }

    static func archiveReadOnlyJSON(path: String, postBody: String?) throws -> [String: Any] {
        let session = try loadSession()
        guard let ca = Bundle.main.path(forResource: "CACert", ofType: "pem") else {
            throw NSError(domain: "MagnistraArchive", code: 8010,
                userInfo: [NSLocalizedDescriptionKey: "CA certificate unavailable."])
        }
        exploreSearchLock.lock()
        defer { exploreSearchLock.unlock() }
        let isPost = postBody != nil

        let requestCode: Int32 = ca.withCString { caPtr in
            session.userAgent.withCString { agent in
                session.language.withCString { language in
                    session.cookieHeader.withCString { cookies in
                        session.csrfToken.withCString { csrf in
                            path.withCString { route in
                                if let payload = postBody {
                                    return payload.withCString { form in
                                        magnistraArchiveWebRead(caPtr, agent, language,
                                            cookies, csrf, route, form)
                                    }
                                }
                                return magnistraArchiveWebRead(caPtr, agent, language,
                                    cookies, csrf, route, nil)
                            }
                        }
                    }
                }
            }
        }
        let status = magnistra_explore_search_http_status()
        let tls = magnistra_explore_search_tls_verify_result()
        let length = Int(magnistra_explore_search_body_length())
        let archiveMeta = "headers=\(magnistraArchiveHeaderBytes()) mime=\(magnistraArchiveMimeKind()) webFields=\(magnistraArchiveWebFields())"

        print("MAGNISTRA_ARCHIVE_TRANSPORT phase=\(isPost ? "reels_media" : "day_shells") http=\(status) curl=\(requestCode) tls=\(tls) bytes=\(length)")

        let failureReason: String?
        if requestCode != 0 {
            failureReason = "Network transport error \(requestCode) (HTTP \(status))."
        } else if tls != 0 {
            failureReason = "TLS verification error \(tls) (HTTP \(status))."
        } else if !(200..<300).contains(Int(status)) {
            failureReason = "Archive HTTP \(status)."
        } else if length <= 0 {
            failureReason = "Archive returned an empty response (HTTP \(status); \(archiveMeta))."
        } else if length >= 10000000 {
            failureReason = "Archive response exceeds the size limit (HTTP \(status))."
        } else {
            failureReason = nil
        }
        if let reason = failureReason {
            throw NSError(domain: "MagnistraArchive", code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: reason])
        }
        let pointer = magnistra_explore_search_body()
        guard let bytes = pointer,
              let text = String(data: Data(bytes: bytes, count: length),
                                encoding: .utf8),
              let start = text.firstIndex(of: "{") else {
            throw NSError(domain: "MagnistraArchive", code: 8011,
                userInfo: [NSLocalizedDescriptionKey: "Archive response missing JSON."])
        }
        let startOfResponse = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if startOfResponse.hasPrefix("<") || startOfResponse.hasPrefix("<!") {
            throw NSError(domain: "MagnistraArchive", code: 8014,
                userInfo: [NSLocalizedDescriptionKey:
                    "Archive returned HTML instead of JSON (HTTP \(status))."])
        }
        let raw = String(text[start...])
        guard let data = raw.data(using: .utf8),
              let json = try MagnistraJSONKit.jsonObject(with: data, options: [])
                as? [String: Any] else {
            throw NSError(domain: "MagnistraArchive", code: 8012,
                userInfo: [NSLocalizedDescriptionKey: "Unrecognized Archive response."])
        }
        if let result = json["status"] as? String, result == "fail" {
            throw NSError(domain: "MagnistraArchive", code: 8013,
                userInfo: [NSLocalizedDescriptionKey:
                    json["message"] as? String ?? "Archive request rejected."])
        }
        return json
    }

    static func archiveIsEmptyHTTP200(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == "MagnistraArchive" && value.code == 200 &&
            value.localizedDescription.hasPrefix("Archive returned an empty response")
    }

    static func archiveDayItems(_ root: [String: Any]) -> [[String: Any]]? {
        if let days = root["items"] as? [[String: Any]] { return days }
        if let data = root["data"] as? [String: Any],
           let days = data["items"] as? [[String: Any]] { return days }
        return nil
    }

    static func archiveSchemaSummary(_ root: [String: Any]) -> String {

        let data = root["data"] as? [String: Any] ?? [:]
        let count = (root["items"] as? [Any])?.count ??
                    (data["items"] as? [Any])?.count ?? -1
        let declared = (root["num_results"] as? NSNumber)?.intValue ?? -1
        let kind = root["items"] != nil ? "items" :
                   root["data"] != nil ? "data" : "unknown"
        return "\(kind):\(count)/\(declared)"
    }

    static func loadStoryArchiveDays() throws -> [MagnistraArchiveDay] {
        let timezone = TimeZone.current.secondsFromGMT()
        let base = "https://www.instagram.com/api/v1/archive/reel/day_shells/"
        let primary = "\(base)?__a=1&__d=www&timezone_offset=\(timezone)&is_in_archive_home=true&include_cover=0&include_suggested_highlights=false"
        let minimal = "\(base)?timezone_offset=\(timezone)"
        var firstShape = "not-read"
        var secondShape = "not-read"
        var rawDays: [[String: Any]] = []
        do {
            let first = try archiveReadOnlyJSON(path: primary, postBody: nil)
            firstShape = archiveSchemaSummary(first)
            rawDays = archiveDayItems(first) ?? []
        } catch {

            guard archiveIsEmptyHTTP200(error) else { throw error }
            firstShape = "HTTP200-empty-body"
        }
        if rawDays.isEmpty {

            do {
                let second = try archiveReadOnlyJSON(path: minimal, postBody: nil)
                secondShape = archiveSchemaSummary(second)
                rawDays = archiveDayItems(second) ?? []
            } catch {
                let err = error as NSError
                if archiveIsEmptyHTTP200(error) {
                    throw NSError(domain: "MagnistraArchive", code: 8200,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Archive unresolved. A: \(firstShape); B: \(err.localizedDescription)"])
                }
                throw error
            }
        }
        var seen = Set<String>()
        var result: [MagnistraArchiveDay] = []
        for item in rawDays {
            let value = item["id"]
            let rawID = (value as? String) ?? (value as? NSNumber)?.stringValue ?? ""
            let normalizedID = rawID.hasPrefix("archiveDay:")
                ? rawID : "archiveDay:" + rawID
            let allowed = CharacterSet(charactersIn:
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:_-")
            guard !rawID.isEmpty, normalizedID.count < 120,
                  normalizedID.rangeOfCharacter(from: allowed.inverted) == nil,
                  !seen.contains(normalizedID) else { continue }
            seen.insert(normalizedID)
            let count = (item["media_count"] as? NSNumber)?.intValue ?? 0
            let timestamp = (item["timestamp"] as? NSNumber)?.doubleValue ??
                            (item["latest_reel_media"] as? NSNumber)?.doubleValue ?? 0
            result.append(MagnistraArchiveDay(id: normalizedID,
                mediaCount: max(0, count), timestamp: timestamp))
        }
        if result.isEmpty {
            throw NSError(domain: "MagnistraArchive", code: 8201,
                userInfo: [NSLocalizedDescriptionKey:
                    "Archive unverified. A: \(firstShape); B: \(secondShape)."])
        }
        return result
    }

    static func loadArchivedStorySlides(reelID: String) throws -> [MagnistraStorySlide] {
        let permitted = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:_-")
        guard reelID.hasPrefix("archiveDay:"), reelID.count < 120,
              reelID.rangeOfCharacter(from: permitted.inverted) == nil else { return [] }
        let encoded = reelID.addingPercentEncoding(withAllowedCharacters:
            CharacterSet.alphanumerics) ?? ""

        let root: [String: Any]
        do {
            root = try archiveReadOnlyJSON(
                path: "https://www.instagram.com/api/v1/feed/reels_media/", postBody: "reel_ids=\(encoded)")
        } catch {
            guard archiveIsEmptyHTTP200(error) else { throw error }
            root = try archiveReadOnlyJSON(
                path: "https://www.instagram.com/api/v1/feed/reels_media/?reel_ids=\(encoded)",
                postBody: nil)
        }
        let keyed = root["reels"] as? [String: Any] ?? [:]
        let item = keyed[reelID] as? [String: Any]
        let array = root["reels_media"] as? [[String: Any]] ?? []
        let content = item ?? array.first(where: { ($0["id"] as? String) == reelID })
        guard let entries = content?["items"] as? [[String: Any]] else { return [] }
        var slides: [MagnistraStorySlide] = []
        for media in entries {
            let image = media["image_versions2"] as? [String: Any] ?? [:]
            let candidates = image["candidates"] as? [[String: Any]] ?? []
            let preview = candidates.compactMap { $0["url"] as? String }.first ?? ""
            let versions = media["video_versions"] as? [[String: Any]] ?? []
            let video = versions.compactMap { $0["url"] as? String }.first ?? ""
            let owner = media["user"] as? [String: Any] ?? [:]
            let timestamp = (media["taken_at"] as? NSNumber)?.doubleValue ?? 0
            if !preview.isEmpty || !video.isEmpty {
                slides.append(MagnistraStorySlide(imageURL: preview, videoURL: video,
                    username: owner["username"] as? String ?? "", timestamp: timestamp))
            }
        }
        return slides
    }

    static func loadStorySlides(reelID: String, highlight: Bool) throws -> [MagnistraStorySlide] {
        guard !reelID.isEmpty, reelID.count < 256 else { return [] }
        if reelID.hasPrefix("archiveDay:") {
            return try loadArchivedStorySlides(reelID: reelID)
        }
        let docID = highlight ? "39400183649572570" : "29306733562261201"
        let name = highlight ? "PolarisStoriesV3HighlightsPageQuery" : "PolarisStoriesV3ReelPageGalleryQuery"
        let root = try exploreSearchGraphQLRoot(
            variables: ["first": 1, "initial_reel_id": reelID, "reel_ids": [reelID],
                        "__relay_internal__pv__PolarisCommunityNoteStoriesLabelEnabledrelayprovider": false],
            docID: docID, friendlyName: name)
        guard let data = root["data"] as? [String: Any],
              let connection = data["xdt_api__v1__feed__reels_media__connection"] as? [String: Any],
              let edges = connection["edges"] as? [[String: Any]] else { return [] }
        var slides: [MagnistraStorySlide] = []
        for edge in edges {
            guard let node = edge["node"] as? [String: Any],
                  let entries = node["items"] as? [[String: Any]] else { continue }
            for media in entries {
                let pictures = media["image_versions2"] as? [String: Any] ?? [:]
                let candidates = pictures["candidates"] as? [[String: Any]] ?? []
                let preview = candidates.compactMap { $0["url"] as? String }.first ?? ""
                let versions = media["video_versions"] as? [[String: Any]] ?? []
                let video = versions.compactMap { $0["url"] as? String }.first ?? ""
                let user = media["user"] as? [String: Any] ?? [:]
                let owner = user["username"] as? String ?? ""
                let timestamp = (media["taken_at"] as? NSNumber)?.doubleValue ?? 0

                let rawMedia = stringValue(media["pk"]) ?? stringValue(media["id"]) ?? ""
                let mediaPK = String(rawMedia.split(separator: "_").first ?? "")
                let authorID = stringValue(user["pk"]) ?? stringValue(user["id"]) ?? ""
                if !preview.isEmpty || !video.isEmpty {
                    slides.append(MagnistraStorySlide(imageURL: preview, videoURL: video,
                        username: owner, timestamp: timestamp,
                        mediaPK: mediaPK, ownerID: authorID))
                }
            }
        }
        return slides
    }

    static func acknowledgeStoryView(reelID: String, mediaPK: String,
                                     ownerID: String, timestamp: Double) throws {
        let digits = CharacterSet(charactersIn: "0123456789")
        func validNumericID(_ value: String) -> Bool {
            return !value.isEmpty && value.count < 32 &&
                value.unicodeScalars.allSatisfy { digits.contains($0) }
        }
        guard validNumericID(reelID), validNumericID(mediaPK),
              validNumericID(ownerID), reelID == ownerID,
              timestamp > 0, timestamp.isFinite else {
            throw NSError(domain: "MagnistraStorySeen", code: 9501,
                userInfo: [NSLocalizedDescriptionKey: "Invalid story metadata"])
        }

        let takenAt = Int64(timestamp)
        let form = "reels%5B\(reelID)%5D%5B%5D=\(mediaPK)_\(ownerID)_\(takenAt)"
        let response = try postActionRoot(relativePath: "/api/v2/media/seen/",
                                          postBody: form)
        if let status = response["status"] as? String, status != "ok" {
            throw NSError(domain: "MagnistraStorySeen", code: 9502,
                userInfo: [NSLocalizedDescriptionKey: "Story receipt rejected"])
        }
    }

    static func storyVideoLocalURL(_ remote: String) throws -> URL? {
        guard remote.hasPrefix("https://") else { return nil }
        let session = try loadSession()
        guard let caPath = Bundle.main.path(forResource: "CACert", ofType: "pem") else { return nil }
        return StreamProxy.shared.localURL(for: remote, caPath: caPath,
                                                     userAgent: session.userAgent,
                                                     prepareForNextReel: false)
    }
}
