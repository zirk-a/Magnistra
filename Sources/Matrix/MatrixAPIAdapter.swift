// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Matrix HTTP API client used by Magnistra's Matrix-backed Direct.
import Foundation

class MagnistraMatrixAPIClient {

    struct MatrixError: Error, CustomStringConvertible {
        let errcode: String
        let error: String
        var description: String { "\(errcode): \(error)" }
    }

    var homeserverBaseURL: String
    var accessToken: String?

    init(homeserverBaseURL: String, accessToken: String? = nil) {
        self.homeserverBaseURL = homeserverBaseURL
        self.accessToken = accessToken
    }

    func get(_ path: String, timeout: Int = 30, completion: @escaping ([String: Any]?, Error?) -> Void) {
        MagnistraMatrixHTTPClient.get(url: fullURL(path), headers: authHeaders(), timeout: timeout) { data, error in
            self.parse(data, error, completion: completion)
        }
    }

    func post(_ path: String, body: [String: Any], completion: @escaping ([String: Any]?, Error?) -> Void) {
        MagnistraMatrixHTTPClient.post(url: fullURL(path), headers: authHeaders(), body: body) { data, error in
            self.parse(data, error, completion: completion)
        }
    }

    func put(_ path: String, body: [String: Any], completion: @escaping ([String: Any]?, Error?) -> Void) {
        MagnistraMatrixHTTPClient.put(url: fullURL(path), headers: authHeaders(), body: body) { data, error in
            self.parse(data, error, completion: completion)
        }
    }

    func uploadMedia(data: Data, filename: String, mimeType: String,
                     completion: @escaping ([String: Any]?, Error?) -> Void) {
        var headers = authHeaders()
        headers["Content-Type"] = mimeType
        let path = "/_matrix/media/v3/upload?filename=\(filename)"
        MagnistraMatrixCurlFetcher.postData(url: fullURL(path), headers: headers, body: data, timeout: 120) { responseData in
            self.parse(responseData,
                       responseData == nil ? MatrixError(errcode: "M_UNKNOWN", error: "Upload connection failed") : nil,
                       completion: completion)
        }
    }

    func uploadMediaFile(path: String, filename: String, mimeType: String,
                         progress: ((Float) -> Void)?,
                         completion: @escaping ([String: Any]?, Error?) -> Void) {
        var headers = authHeaders()
        headers["Content-Type"] = mimeType
        let apiPath = "/_matrix/media/v3/upload?filename=\(filename)"
        MagnistraMatrixCurlFetcher.postFile(url: fullURL(apiPath), headers: headers,
                             filePath: path, progress: progress) { responseData in
            self.parse(responseData,
                       responseData == nil ? MatrixError(errcode: "M_UNKNOWN", error: "Upload connection failed") : nil,
                       completion: completion)
        }
    }

    private func fullURL(_ path: String) -> String {
        return homeserverBaseURL + path
    }

    private func authHeaders() -> [String: String] {
        guard let token = accessToken else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    private func parse(_ data: Data?, _ error: Error?, completion: @escaping ([String: Any]?, Error?) -> Void) {
        if let error = error {
            completion(nil, error)
            return
        }
        guard let data = data,
              let json = try? MagnistraJSONKit.jsonObject(with: data) as? [String: Any] else {
            completion(nil, MatrixError(errcode: "M_UNKNOWN", error: "Invalid or empty JSON response"))
            return
        }
        if let errcode = json["errcode"] as? String {
            let message = json["error"] as? String ?? "Unknown Matrix error"
            completion(nil, MatrixError(errcode: errcode, error: message))
            return
        }
        completion(json, nil)
    }
}
