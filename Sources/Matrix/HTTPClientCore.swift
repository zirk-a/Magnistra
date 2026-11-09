// Shared request orchestration for ElementOld-derived HTTP clients.
// The two Curl fetchers still select their original, independent C transports.
// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
import Foundation

protocol MagnistraHTTPDataFetcher {
    static func fetchData(url: String, headers: [String: String], timeout: Int,
                          transportError: ((String) -> Void)?, completion: @escaping (Data?) -> Void)
    static func postData(url: String, headers: [String: String], body: Data, timeout: Int,
                         transportError: ((String) -> Void)?, completion: @escaping (Data?) -> Void)
    static func putData(url: String, headers: [String: String], body: Data, timeout: Int,
                        transportError: ((String) -> Void)?, completion: @escaping (Data?) -> Void)
}

extension CurlFetcher: MagnistraHTTPDataFetcher {}
extension MagnistraMatrixCurlFetcher: MagnistraHTTPDataFetcher {}

class MagnistraHTTPClientCore<Fetcher: MagnistraHTTPDataFetcher> {
    class var errorDomain: String { "HTTPClient" }

    class func get(url: String, headers: [String: String] = [:], timeout: Int = 30, completion: @escaping (Data?, Error?) -> Void) {
        guard URL(string: url) != nil else {
            completion(nil, makeError("Invalid URL: \(url)"))
            return
        }

        var reason: String?
        Fetcher.fetchData(url: url, headers: headers, timeout: timeout,
                          transportError: { reason = $0 }) { data in
            if let data = data {
                completion(data, nil)
            } else {
                completion(nil, makeError(failureMessage(reason)))
            }
        }
    }

    class func post(url: String, headers: [String: String] = [:], body: [String: Any], completion: @escaping (Data?, Error?) -> Void) {
        guard URL(string: url) != nil else {
            completion(nil, makeError("Invalid URL: \(url)"))
            return
        }
        var allHeaders = headers
        allHeaders["Content-Type"] = "application/json"
        let bodyData = (try? MagnistraJSONKit.data(withJSONObject: body, options: [])) ?? Data()

        var reason: String?
        Fetcher.postData(url: url, headers: allHeaders, body: bodyData, timeout: 30,
                         transportError: { reason = $0 }) { data in
            if let data = data {
                completion(data, nil)
            } else {
                completion(nil, makeError(failureMessage(reason)))
            }
        }
    }

    class func put(url: String, headers: [String: String] = [:], body: [String: Any], completion: @escaping (Data?, Error?) -> Void) {
        guard URL(string: url) != nil else {
            completion(nil, makeError("Invalid URL: \(url)"))
            return
        }
        var allHeaders = headers
        allHeaders["Content-Type"] = "application/json"
        let bodyData = (try? MagnistraJSONKit.data(withJSONObject: body, options: [])) ?? Data()

        var reason: String?
        Fetcher.putData(url: url, headers: allHeaders, body: bodyData, timeout: 30,
                        transportError: { reason = $0 }) { data in
            if let data = data {
                completion(data, nil)
            } else {
                completion(nil, makeError(failureMessage(reason)))
            }
        }
    }

    private class func failureMessage(_ reason: String?) -> String {
        if let reason = reason {
            return "Connection failed: \(reason)"
        }
        return "Connection failed. Check the server URL and that it is reachable."
    }

    private class func makeError(_ message: String) -> NSError {
        return NSError(domain: errorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
