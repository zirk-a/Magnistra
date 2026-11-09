// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: libcurl HTTP fetcher used by Magnistra's Matrix-backed Direct.
import Foundation

class MagnistraMatrixCurlFetcher {
    private static var active: [MagnistraMatrixCurlFetcher] = []

    private var lastFailure: String?

    private static let curlQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 6
        return q
    }()

    private static let downloadQueue = DispatchQueue(label: "com.magnistra.curl.download")

    private static let uploadQueue = DispatchQueue(label: "com.magnistra.curl.upload")

    private static let stallBytesPerSecond = 1
    private static let stallSeconds = 30

    private static let curlGlobalInit: Bool = { magnistra_matrix_curl_global_init(); return true }()

    private static let caBundlePath: String? = Bundle.main.path(forResource: "CACert", ofType: "pem")

    private static func describe(_ rc: Int32) -> String {
        if let cstr = magnistra_matrix_curl_strerror(rc) {
            return "\(String(cString: cstr)) (curl \(rc))"
        }
        return "curl error \(rc)"
    }

    private static func applyTLS(_ h: MagnistraMatrixCurlHandle!) {
        magnistra_matrix_curl_set_ssl_verify(h)
        if let path = caBundlePath {
            path.withCString { magnistra_matrix_curl_set_ca_bundle(h, $0) }
        }
    }

    static func fetchData(url: String,
                          headers: [String: String] = [:],
                          timeout: Int = 30,
                          transportError: ((String) -> Void)? = nil,
                          completion: @escaping (Data?) -> Void) {
        let fetcher = MagnistraMatrixCurlFetcher()
        retain(fetcher)
        MagnistraMatrixCurlFetcher.curlQueue.addOperation {
            let data = fetcher.syncFetchData(url: url, headers: headers, timeout: timeout)
            DispatchQueue.main.async {
                release(fetcher)
                if let reason = fetcher.lastFailure { transportError?(reason) }
                completion(data)
            }
        }
    }

    static func postData(url: String,
                         headers: [String: String],
                         body: Data,
                         timeout: Int = 30,
                         transportError: ((String) -> Void)? = nil,
                         completion: @escaping (Data?) -> Void) {
        let fetcher = MagnistraMatrixCurlFetcher()
        retain(fetcher)
        MagnistraMatrixCurlFetcher.curlQueue.addOperation {
            let data = fetcher.syncPostData(url: url, headers: headers, body: body, timeout: timeout)
            DispatchQueue.main.async {
                release(fetcher)
                if let reason = fetcher.lastFailure { transportError?(reason) }
                completion(data)
            }
        }
    }

    static func putData(url: String,
                        headers: [String: String],
                        body: Data,
                        timeout: Int = 30,
                        transportError: ((String) -> Void)? = nil,
                        completion: @escaping (Data?) -> Void) {
        let fetcher = MagnistraMatrixCurlFetcher()
        retain(fetcher)
        MagnistraMatrixCurlFetcher.curlQueue.addOperation {
            let data = fetcher.syncPutData(url: url, headers: headers, body: body, timeout: timeout)
            DispatchQueue.main.async {
                release(fetcher)
                if let reason = fetcher.lastFailure { transportError?(reason) }
                completion(data)
            }
        }
    }

    static func downloadToFile(url: String,
                               headers: [String: String] = [:],
                               outputPath: String,
                               progress: ((Float) -> Void)?,
                               completion: @escaping (Bool) -> Void) {
        let fetcher = MagnistraMatrixCurlFetcher()
        retain(fetcher)
        MagnistraMatrixCurlFetcher.downloadQueue.async {
            let ok = fetcher.syncDownload(url: url, headers: headers,
                                          outputPath: outputPath, progress: progress)
            DispatchQueue.main.async {
                release(fetcher)
                completion(ok)
            }
        }
    }

    static func postFile(url: String,
                         headers: [String: String],
                         filePath: String,
                         progress: ((Float) -> Void)?,
                         completion: @escaping (Data?) -> Void) {
        let fetcher = MagnistraMatrixCurlFetcher()
        retain(fetcher)
        MagnistraMatrixCurlFetcher.uploadQueue.async {
            let data = fetcher.syncPostFile(url: url, headers: headers,
                                            filePath: filePath, progress: progress)
            DispatchQueue.main.async {
                release(fetcher)
                completion(data)
            }
        }
    }

    private static func retain(_ f: MagnistraMatrixCurlFetcher) {
        objc_sync_enter(MagnistraMatrixCurlFetcher.self)
        active.append(f)
        objc_sync_exit(MagnistraMatrixCurlFetcher.self)
    }

    private static func release(_ f: MagnistraMatrixCurlFetcher) {
        objc_sync_enter(MagnistraMatrixCurlFetcher.self)
        active.removeAll { $0 === f }
        objc_sync_exit(MagnistraMatrixCurlFetcher.self)
    }

    private func syncFetchData(url: String, headers: [String: String], timeout: Int) -> Data? {
        _ = MagnistraMatrixCurlFetcher.curlGlobalInit
        let h = magnistra_matrix_curl_init()
        defer { magnistra_matrix_curl_cleanup(h) }

        let buf = NSMutableData()
        let ptr = Unmanaged.passUnretained(buf).toOpaque()

        url.withCString { magnistra_matrix_curl_set_url(h, $0) }
        MagnistraMatrixCurlFetcher.applyTLS(h)
        magnistra_matrix_curl_set_follow_redirects(h)
        magnistra_matrix_curl_set_timeout(h, CLong(timeout))
        magnistra_matrix_curl_set_write_fn(h, curlDataWriteCallback, ptr)

        var headerList: UnsafeMutableRawPointer?
        for (k, v) in headers {
            "\(k): \(v)".withCString { headerList = magnistra_matrix_curl_headers_append(headerList, $0) }
        }
        if headerList != nil { magnistra_matrix_curl_set_headers(h, headerList) }
        defer { if headerList != nil { magnistra_matrix_curl_headers_free(headerList) } }

        let rc = magnistra_matrix_curl_perform(h)
        guard rc == 0 else {
            lastFailure = MagnistraMatrixCurlFetcher.describe(rc)
            return nil
        }
        let code = magnistra_matrix_curl_response_code(h)

        return buf as Data
    }

    private func syncPostData(url: String, headers: [String: String], body: Data, timeout: Int) -> Data? {
        _ = MagnistraMatrixCurlFetcher.curlGlobalInit
        let h = magnistra_matrix_curl_init()
        defer { magnistra_matrix_curl_cleanup(h) }

        let buf = NSMutableData()
        let ptr = Unmanaged.passUnretained(buf).toOpaque()

        url.withCString { magnistra_matrix_curl_set_url(h, $0) }
        MagnistraMatrixCurlFetcher.applyTLS(h)
        magnistra_matrix_curl_set_follow_redirects(h)
        magnistra_matrix_curl_set_timeout(h, CLong(timeout))
        magnistra_matrix_curl_set_write_fn(h, curlDataWriteCallback, ptr)

        var headerList: UnsafeMutableRawPointer?
        for (k, v) in headers {
            "\(k): \(v)".withCString { headerList = magnistra_matrix_curl_headers_append(headerList, $0) }
        }
        if headerList != nil { magnistra_matrix_curl_set_headers(h, headerList) }
        defer { if headerList != nil { magnistra_matrix_curl_headers_free(headerList) } }

        body.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            magnistra_matrix_curl_set_post_body(h, raw.baseAddress, CLong(body.count))
        }

        let rc = magnistra_matrix_curl_perform(h)
        guard rc == 0 else {
            lastFailure = MagnistraMatrixCurlFetcher.describe(rc)
            return nil
        }
        let code = magnistra_matrix_curl_response_code(h)

        return buf as Data
    }

    private func syncPutData(url: String, headers: [String: String], body: Data, timeout: Int) -> Data? {
        _ = MagnistraMatrixCurlFetcher.curlGlobalInit
        let h = magnistra_matrix_curl_init()
        defer { magnistra_matrix_curl_cleanup(h) }

        let buf = NSMutableData()
        let ptr = Unmanaged.passUnretained(buf).toOpaque()

        url.withCString { magnistra_matrix_curl_set_url(h, $0) }
        MagnistraMatrixCurlFetcher.applyTLS(h)
        magnistra_matrix_curl_set_follow_redirects(h)
        magnistra_matrix_curl_set_timeout(h, CLong(timeout))
        magnistra_matrix_curl_set_write_fn(h, curlDataWriteCallback, ptr)

        var headerList: UnsafeMutableRawPointer?
        for (k, v) in headers {
            "\(k): \(v)".withCString { headerList = magnistra_matrix_curl_headers_append(headerList, $0) }
        }
        if headerList != nil { magnistra_matrix_curl_set_headers(h, headerList) }
        defer { if headerList != nil { magnistra_matrix_curl_headers_free(headerList) } }

        body.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            magnistra_matrix_curl_set_put_body(h, raw.baseAddress, CLong(body.count))
        }

        let rc = magnistra_matrix_curl_perform(h)
        guard rc == 0 else {
            lastFailure = MagnistraMatrixCurlFetcher.describe(rc)
            return nil
        }
        let code = magnistra_matrix_curl_response_code(h)

        return buf as Data
    }

    private func syncPostFile(url: String, headers: [String: String],
                              filePath: String, progress: ((Float) -> Void)?) -> Data? {
        _ = MagnistraMatrixCurlFetcher.curlGlobalInit
        let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
        let length = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        guard length > 0, let file = filePath.withCString({ magnistra_matrix_curl_upload_open($0) }) else { return nil }
        defer { magnistra_matrix_curl_upload_close(file) }

        let h = magnistra_matrix_curl_init()
        defer { magnistra_matrix_curl_cleanup(h) }

        let buf = NSMutableData()
        let ptr = Unmanaged.passUnretained(buf).toOpaque()

        url.withCString { magnistra_matrix_curl_set_url(h, $0) }
        MagnistraMatrixCurlFetcher.applyTLS(h)

        magnistra_matrix_curl_set_timeout(h, 0)
        magnistra_matrix_curl_set_low_speed_abort(h, MagnistraMatrixCurlFetcher.stallBytesPerSecond,
                                        MagnistraMatrixCurlFetcher.stallSeconds)
        magnistra_matrix_curl_set_write_fn(h, curlDataWriteCallback, ptr)

        let box = CurlTransferBox()
        box.progressHandler = progress
        let boxPtr = Unmanaged.passUnretained(box).toOpaque()
        if progress != nil { magnistra_matrix_curl_set_progress_fn(h, curlUploadProgressCallback, boxPtr) }

        var headerList: UnsafeMutableRawPointer?
        for (k, v) in headers {
            "\(k): \(v)".withCString { headerList = magnistra_matrix_curl_headers_append(headerList, $0) }
        }
        if headerList != nil { magnistra_matrix_curl_set_headers(h, headerList) }
        defer { if headerList != nil { magnistra_matrix_curl_headers_free(headerList) } }

        magnistra_matrix_curl_set_post_stream(h, file, length)

        let rc = magnistra_matrix_curl_perform(h)
        guard rc == 0 else { return nil }

        return buf as Data
    }

    private func syncDownload(url: String, headers: [String: String],
                              outputPath: String, progress: ((Float) -> Void)?) -> Bool {
        _ = MagnistraMatrixCurlFetcher.curlGlobalInit
        let h = magnistra_matrix_curl_init()
        defer { magnistra_matrix_curl_cleanup(h) }

        FileManager.default.createFile(atPath: outputPath, contents: nil, attributes: nil)
        guard let fh = FileHandle(forWritingAtPath: outputPath) else { return false }
        let box = CurlTransferBox()
        box.fileHandle = fh
        box.progressHandler = progress
        let boxPtr = Unmanaged.passUnretained(box).toOpaque()

        url.withCString { magnistra_matrix_curl_set_url(h, $0) }
        MagnistraMatrixCurlFetcher.applyTLS(h)
        magnistra_matrix_curl_set_follow_redirects(h)
        magnistra_matrix_curl_set_timeout(h, 0)
        magnistra_matrix_curl_set_low_speed_abort(h, MagnistraMatrixCurlFetcher.stallBytesPerSecond,
                                        MagnistraMatrixCurlFetcher.stallSeconds)
        magnistra_matrix_curl_set_write_fn(h, curlFileWriteCallback, boxPtr)
        if progress != nil { magnistra_matrix_curl_set_progress_fn(h, curlProgressCallback, boxPtr) }

        var headerList: UnsafeMutableRawPointer?
        for (k, v) in headers {
            "\(k): \(v)".withCString { headerList = magnistra_matrix_curl_headers_append(headerList, $0) }
        }
        if headerList != nil { magnistra_matrix_curl_set_headers(h, headerList) }
        defer { if headerList != nil { magnistra_matrix_curl_headers_free(headerList) } }

        let rc = magnistra_matrix_curl_perform(h)
        fh.closeFile()
        guard rc == 0 else {
            try? FileManager.default.removeItem(atPath: outputPath)
            return false
        }
        let code = magnistra_matrix_curl_response_code(h)
        guard code >= 200, code < 300 else {
            try? FileManager.default.removeItem(atPath: outputPath)
            return false
        }
        return box.bytesReceived > 0
    }
}
