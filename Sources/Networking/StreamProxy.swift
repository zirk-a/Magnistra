// Overview: Local streaming proxy that serves remote media to the system video player through libcurl.
import Foundation
import Darwin

private final class ProxyConnection {
    let clientFd: Int32
    let gen: UInt64
    let owner: StreamProxy

    var responseHead = ""
    var headersSent = false
    var aborted = false

    init(
        _ fd: Int32,
        gen: UInt64,
        owner: StreamProxy
    ) {
        clientFd = fd
        self.gen = gen
        self.owner = owner
    }
}

private let proxyHeaderCallback:
    @convention(c) (
        UnsafeRawPointer?,
        Int,
        Int,
        UnsafeMutableRawPointer?
    ) -> Int =
{
    ptr,
    size,
    nmemb,
    userdata in

    let bytes =
        size * nmemb

    guard
        let ptr = ptr,
        let userdata = userdata
    else {
        return bytes
    }

    let conn =
        Unmanaged<ProxyConnection>
            .fromOpaque(
                userdata
            )
            .takeUnretainedValue()

    let line =
        String(
            bytes:
                Data(
                    bytes:
                        ptr,
                    count:
                        bytes
                ),
            encoding:
                .isoLatin1
        ) ?? ""

    let lower =
        line.lowercased()

    if lower.hasPrefix(
        "http/"
    ) {
        conn.responseHead =
            line
    } else if
        line == "\r\n" ||
        line == "\n" ||
        line.isEmpty
    {

    } else if
        lower.hasPrefix(
            "transfer-encoding:"
        ) ||
        lower.hasPrefix(
            "connection:"
        )
    {

    } else {
        conn.responseHead +=
            line
    }

    return bytes
}

private let proxyBodyCallback:
    @convention(c) (
        UnsafeRawPointer?,
        Int,
        Int,
        UnsafeMutableRawPointer?
    ) -> Int =
{
    ptr,
    size,
    nmemb,
    userdata in

    let bytes =
        size * nmemb

    guard
        let ptr = ptr,
        let userdata = userdata
    else {
        return 0
    }

    let conn =
        Unmanaged<ProxyConnection>
            .fromOpaque(
                userdata
            )
            .takeUnretainedValue()

    if conn.aborted {
        return 0
    }

    if !conn.headersSent {
        var head =
            conn.responseHead

        if head.isEmpty {
            head =
                "HTTP/1.1 200 OK\r\n" +
                "Content-Type: video/mp4\r\n" +
                "Accept-Ranges: bytes\r\n"
        } else if
            head.lowercased()
                .range(
                    of:
                        "accept-ranges:"
                ) == nil
        {
            head +=
                "Accept-Ranges: bytes\r\n"
        }

        head +=
            "Connection: close\r\n\r\n"

        if !StreamProxy
            .sendAll(
                conn.clientFd,
                Array(
                    head.utf8
                )
            )
        {
            conn.aborted = true
            return 0
        }

        conn.headersSent = true
    }

    let ok =
        StreamProxy
            .sendAll(
                conn.clientFd,
                ptr.assumingMemoryBound(
                    to:
                        UInt8.self
                ),
                bytes
            )

    if !ok {
        conn.aborted = true
        return 0
    }

    return bytes
}

private let proxyProgressCallback:
    @convention(c) (
        UnsafeMutableRawPointer?,
        Int64,
        Int64,
        Int64,
        Int64
    ) -> Int32 =
{
    clientp,
    _,
    _,
    _,
    _ in

    guard
        let clientp = clientp
    else {
        return 0
    }

    let conn =
        Unmanaged<ProxyConnection>
            .fromOpaque(
                clientp
            )
            .takeUnretainedValue()

    if conn.aborted {
        return 1
    }

    if conn.owner
        .isSuperseded(
            conn.gen
        )
    {
        conn.aborted = true
        return 1
    }

    return 0
}

final class StreamProxy:
    NSObject
{
    static let shared =
        StreamProxy()

    private struct Route {
        let url: String
        let caPath: String
        let userAgent: String
        var gen: UInt64
    }

    private var listenFd:
        Int32 = -1

    private var port:
        UInt16 = 0

    private var started =
        false

    private var routes:
        [String: Route] = [:]

    private var routeSeq:
        UInt64 = 0

    private var currentGen:
        UInt64 = 0

    private let lock =
        NSLock()

    func localURL(
        for remote: String,
        caPath: String,
        userAgent: String,
        prepareForNextReel: Bool = false
    ) -> URL? {
        guard
            start()
        else {
            return nil
        }

        lock.lock()

        routeSeq += 1

        let gen: UInt64
        if prepareForNextReel {
            gen = currentGen + 1
        } else {
            currentGen += 1
            gen = currentGen
        }

        let token =
            "\(routeSeq).mp4"

        routes[token] =
            Route(
                url:
                    remote,
                caPath:
                    caPath,
                userAgent:
                    userAgent,
                gen:
                    gen
            )

        lock.unlock()

        return URL(
            string:
                "http://127.0.0.1:" +
                "\(port)/\(token)"
        )
    }

    func isSuperseded(
        _ gen: UInt64
    ) -> Bool {
        lock.lock()

        let result =
            gen < currentGen

        lock.unlock()

        return result
    }

    func closeCurrentStream() {
        lock.lock()

        currentGen += 1

        if self === StreamProxy.shared {
            let retiredRoutes = routes.count
            routes.removeAll(keepingCapacity: true)
            lock.unlock()
            NSLog("MAGNISTRA_SHARED_VIDEO_PROXY_RETIRED_ROUTES=%ld", retiredRoutes)
            return
        }

        let bumped =
            currentGen

        let keys =
            Array(
                routes.keys
            )

        for key in keys {
            if var route =
                routes[key]
            {
                route.gen =
                    bumped

                routes[key] =
                    route
            }
        }

        lock.unlock()
    }

    @discardableResult
    private func start()
        -> Bool
    {
        lock.lock()
        defer {
            lock.unlock()
        }

        if started {
            return true
        }

        signal(
            SIGPIPE,
            SIG_IGN
        )

        let fd =
            socket(
                AF_INET,
                SOCK_STREAM,
                IPPROTO_TCP
            )

        guard
            fd >= 0
        else {
            return false
        }

        var yes:
            Int32 = 1

        setsockopt(
            fd,
            SOL_SOCKET,
            SO_REUSEADDR,
            &yes,
            socklen_t(
                MemoryLayout<Int32>
                    .size
            )
        )

        var addr =
            sockaddr_in()

        addr.sin_family =
            sa_family_t(
                AF_INET
            )

        addr.sin_addr.s_addr =
            inet_addr(
                "127.0.0.1"
            )

        addr.sin_port = 0

        let bindOK =
            withUnsafePointer(
                to:
                    &addr
            ) {
                pointer in

                pointer
                    .withMemoryRebound(
                        to:
                            sockaddr.self,
                        capacity:
                            1
                    ) {
                        rebound in

                        bind(
                            fd,
                            rebound,
                            socklen_t(
                                MemoryLayout<
                                    sockaddr_in
                                >.size
                            )
                        )
                    }
            }

        guard
            bindOK == 0,
            listen(
                fd,
                8
            ) == 0
        else {
            close(
                fd
            )

            return false
        }

        var bound =
            sockaddr_in()

        var length =
            socklen_t(
                MemoryLayout<
                    sockaddr_in
                >.size
            )

        let nameOK =
            withUnsafeMutablePointer(
                to:
                    &bound
            ) {
                pointer in

                pointer
                    .withMemoryRebound(
                        to:
                            sockaddr.self,
                        capacity:
                            1
                    ) {
                        rebound in

                        getsockname(
                            fd,
                            rebound,
                            &length
                        )
                    }
            }

        guard
            nameOK == 0
        else {
            close(
                fd
            )

            return false
        }

        port =
            UInt16(
                bigEndian:
                    bound.sin_port
            )

        listenFd =
            fd

        started =
            true

        let thread =
            Thread(
                target:
                    self,
                selector:
                    #selector(
                        acceptLoop
                    ),
                object:
                    nil
            )

        thread.stackSize =
            512 * 1024

        thread.start()

        return true
    }

    @objc private func acceptLoop() {
        while true {
            let client =
                accept(
                    listenFd,
                    nil,
                    nil
                )

            if client < 0 {
                if errno == EINTR { continue }
                if self === StreamProxy.shared {
                    let error = errno
                    if error == ECONNABORTED || error == EAGAIN ||
                       error == ENOBUFS || error == EMFILE || error == ENFILE {
                        Thread.sleep(forTimeInterval: 0.15)
                        continue
                    }
                    NSLog("MAGNISTRA_SHARED_PROXY_LISTENER_ERRNO=%d", error)
                }
                break
            }

            var yes:
                Int32 = 1

            setsockopt(
                client,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &yes,
                socklen_t(
                    MemoryLayout<Int32>
                        .size
                )
            )

            let thread =
                Thread(
                    target:
                        self,
                    selector:
                        #selector(
                            handleConnection(
                                _:
                            )
                        ),
                    object:
                        NSNumber(
                            value:
                                client
                        )
                )

            thread.stackSize =
                512 * 1024

            thread.start()
        }

        if self === StreamProxy.shared {
            lock.lock()
            let oldListener = listenFd
            listenFd = -1
            port = 0
            started = false
            routes.removeAll(keepingCapacity: true)
            lock.unlock()
            if oldListener >= 0 { close(oldListener) }
        }
    }

    @objc private func handleConnection(
        _ object: Any
    ) {
        guard
            let number =
                object as? NSNumber
        else {
            return
        }

        let clientFd =
            number.int32Value

        if self === StreamProxy.shared {
            var socketTimeout = timeval(tv_sec: 10, tv_usec: 0)
            _ = setsockopt(clientFd, SOL_SOCKET, SO_SNDTIMEO,
                           &socketTimeout,
                           socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO,
                           &socketTimeout,
                           socklen_t(MemoryLayout<timeval>.size))
        }

        defer {
            close(
                clientFd
            )
        }

        guard
            let request =
                readRequestHead(
                    clientFd
                )
        else {
            return
        }

        let lines =
            request.components(
                separatedBy:
                    "\r\n"
            )

        guard
            let requestLine =
                lines.first
        else {
            return
        }

        let parts =
            requestLine.components(
                separatedBy:
                    " "
            )

        guard
            parts.count >= 2
        else {
            _ =
                StreamProxy
                    .sendAll(
                        clientFd,
                        Array(
                            (
                                "HTTP/1.1 400 Bad Request\r\n" +
                                "Connection: close\r\n\r\n"
                            ).utf8
                        )
                    )

            return
        }

        var token =
            parts[1]

        if token.hasPrefix(
            "/"
        ) {
            token.removeFirst()
        }

        if let queryIndex =
            token.firstIndex(
                of:
                    "?"
            )
        {
            token =
                String(
                    token[
                        ..<queryIndex
                    ]
                )
        }

        lock.lock()

        let route =
            routes[token]

        lock.unlock()

        guard
            let route = route
        else {
            _ =
                StreamProxy
                    .sendAll(
                        clientFd,
                        Array(
                            (
                                "HTTP/1.1 404 Not Found\r\n" +
                                "Connection: close\r\n\r\n"
                            ).utf8
                        )
                    )

            return
        }

        var rangeHeader:
            String? = nil

        for line in
            lines.dropFirst()
        {
            if line.lowercased()
                .hasPrefix(
                    "range:"
                )
            {
                rangeHeader =
                    line
            }
        }

        proxy(
            remoteURL:
                route.url,
            caPath:
                route.caPath,
            userAgent:
                route.userAgent,
            gen:
                route.gen,
            rangeHeader:
                rangeHeader,
            clientFd:
                clientFd
        )
    }

    private func readRequestHead(
        _ fd: Int32
    ) -> String? {
        var data =
            Data()

        var buffer =
            [UInt8](
                repeating:
                    0,
                count:
                    2048
            )

        let terminator =
            Data(
                "\r\n\r\n".utf8
            )

        while data.range(
            of:
                terminator
        ) == nil
        {
            let count =
                recv(
                    fd,
                    &buffer,
                    buffer.count,
                    0
                )

            if count <= 0 {
                if data.isEmpty {
                    return nil
                }

                return String(
                    data:
                        data,
                    encoding:
                        .isoLatin1
                )
            }

            data.append(
                buffer,
                count:
                    count
            )

            if data.count >
                16 * 1024
            {
                break
            }
        }

        return String(
            data:
                data,
            encoding:
                .isoLatin1
        )
    }

    private func proxy(
        remoteURL: String,
        caPath: String,
        userAgent: String,
        gen: UInt64,
        rangeHeader: String?,
        clientFd: Int32
    ) {
        let conn =
            ProxyConnection(
                clientFd,
                gen:
                    gen,
                owner:
                    self
            )

        let pointer =
            Unmanaged
                .passUnretained(
                    conn
                )
                .toOpaque()

        guard
            let handle =
                magnistra_stream_bridge_init()
        else {
            _ =
                StreamProxy
                    .sendAll(
                        clientFd,
                        Array(
                            (
                                "HTTP/1.1 502 Bad Gateway\r\n" +
                                "Connection: close\r\n\r\n"
                            ).utf8
                        )
                    )

            return
        }

        defer {
            magnistra_stream_bridge_cleanup(
                handle
            )
        }

        remoteURL.withCString {
            magnistra_stream_bridge_set_url(
                handle,
                $0
            )
        }

        caPath.withCString {
            magnistra_stream_bridge_set_verified_ca(
                handle,
                $0
            )
        }

        magnistra_stream_bridge_set_follow_redirects(
            handle
        )

        magnistra_stream_bridge_set_timeout(
            handle,
            0
        )

        if self === StreamProxy.shared {
            magnistra_stream_bridge_set_stall_timeout(handle, 15)
        }

        userAgent.withCString {
            magnistra_stream_bridge_set_useragent(
                handle,
                $0
            )
        }

        if let rangeHeader =
            rangeHeader
        {
            rangeHeader.withCString {
                magnistra_stream_bridge_add_header(
                    handle,
                    $0
                )
            }
        }

        magnistra_stream_bridge_set_header_fn(
            handle,
            proxyHeaderCallback,
            pointer
        )

        magnistra_stream_bridge_set_write_fn(
            handle,
            proxyBodyCallback,
            pointer
        )

        magnistra_stream_bridge_set_progress_fn(
            handle,
            proxyProgressCallback,
            pointer
        )

        _ =
            magnistra_stream_bridge_perform(
                handle
            )

        if
            !conn.headersSent &&
            !conn.aborted
        {
            var head =
                conn.responseHead

            if head.isEmpty {
                head =
                    "HTTP/1.1 502 Bad Gateway\r\n"
            }

            head +=
                "Connection: close\r\n\r\n"

            _ =
                StreamProxy
                    .sendAll(
                        clientFd,
                        Array(
                            head.utf8
                        )
                    )
        }
    }

    @discardableResult
    static func sendAll(
        _ fd: Int32,
        _ bytes: [UInt8]
    ) -> Bool {
        return bytes
            .withUnsafeBufferPointer {
                buffer in

                guard
                    let base =
                        buffer.baseAddress
                else {
                    return true
                }

                return sendAll(
                    fd,
                    base,
                    buffer.count
                )
            }
    }

    @discardableResult
    static func sendAll(
        _ fd: Int32,
        _ pointer:
            UnsafePointer<UInt8>,
        _ count: Int
    ) -> Bool {
        var sent = 0

        while sent < count {
            let amount =
                send(
                    fd,
                    pointer + sent,
                    count - sent,
                    0
                )

            if amount <= 0 {
                if
                    amount < 0 &&
                    errno == EINTR
                {
                    continue
                }

                return false
            }

            sent +=
                amount
        }

        return true
    }
}
