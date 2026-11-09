// Overview: Lazy image loading transport and connection slots.
import Foundation

private final class MagnistraLazyImageBuffer {
    var data = Data()
}

private let magnistraLazyImageWriteCallback:
    @convention(c) (
        UnsafeRawPointer?,
        Int,
        Int,
        UnsafeMutableRawPointer?
    ) -> Int =
{
    pointer,
    size,
    nmemb,
    userdata in

    let count =
        size * nmemb

    guard
        count > 0,
        let pointer = pointer,
        let userdata = userdata
    else {
        return count
    }

    let box =
        Unmanaged<MagnistraLazyImageBuffer>
            .fromOpaque(
                userdata
            )
            .takeUnretainedValue()

    box.data.append(
        Data(
            bytes:
                pointer,
            count:
                count
        )
    )

    return count
}

private final class MagnistraImageConnectionSlot {
    let lock = NSLock()
    var handle: UnsafeMutableRawPointer? = nil

    deinit {
        if let retained = handle {
            magnistra_stream_bridge_cleanup(retained)
        }
    }
}

enum MagnistraLazyImageTransport {
    private static let slots = [
        MagnistraImageConnectionSlot(),
        MagnistraImageConnectionSlot(),
        MagnistraImageConnectionSlot()
    ]
    private static let selectionLock = NSLock()
    private static var nextSlot = 0

    private static func nextConnection() -> MagnistraImageConnectionSlot {
        selectionLock.lock()
        let slot = slots[nextSlot]
        nextSlot = (nextSlot + 1) % slots.count
        selectionLock.unlock()
        return slot
    }
    static func fetch(
        url: String,
        caPath: String,
        userAgent: String
    ) -> Data? {
        guard
            !url.isEmpty,
            !caPath.isEmpty,
            !userAgent.isEmpty
        else {
            return nil
        }

        let slot = nextConnection()
        slot.lock.lock()
        defer { slot.lock.unlock() }
        if slot.handle == nil {
            slot.handle = magnistra_stream_bridge_init()
        }
        guard let handle = slot.handle else { return nil }
        magnistra_stream_bridge_reset_for_image_reuse(handle)

        let box =
            MagnistraLazyImageBuffer()

        let opaque =
            Unmanaged
                .passUnretained(
                    box
                )
                .toOpaque()

        url.withCString {
            pointer in

            magnistra_stream_bridge_set_url(
                handle,
                pointer
            )
        }

        caPath.withCString {
            pointer in

            magnistra_stream_bridge_set_verified_ca(
                handle,
                pointer
            )
        }

        magnistra_stream_bridge_set_follow_redirects(
            handle
        )

        magnistra_stream_bridge_set_timeout(
            handle,
            20
        )

        userAgent.withCString {
            pointer in

            magnistra_stream_bridge_set_useragent(
                handle,
                pointer
            )
        }

        magnistra_stream_bridge_set_write_fn(
            handle,
            magnistraLazyImageWriteCallback,
            opaque
        )

        let rc =
            magnistra_stream_bridge_perform(
                handle
            )

        let status =
            magnistra_stream_bridge_response_code(
                handle
            )

        guard
            rc == 0,
            status >= 200,
            status < 300,
            !box.data.isEmpty
        else {

            magnistra_stream_bridge_cleanup(handle)
            slot.handle = nil
            return nil
        }

        return box.data
    }
}
