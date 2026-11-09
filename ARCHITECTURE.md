# Architecture

A guide to the main components of Magnistra and the source files involved in
each part of the app.

## The big picture

Magnistra is a native iOS 5.0–10.x (armv7) app written mostly in Swift with a
UIKit interface built in code. Everything that touches the network goes through
small **C transports** built on libcurl and OpenSSL, because the system
networking stack on the oldest iOS versions cannot talk to current servers.

```
Screens (Swift/UIKit)
   │
Services (Swift, Sources/Networking, Sources/Matrix)
   │
C transports (Sources/*.c)  ──  libcurl + OpenSSL  ──  Instagram / Matrix servers
   │
Parsing (Swift) → models → back to the screens
```

Swift has no module map for the C code. Headers are exposed through
`Sources/Bridging-Header.h`, and a few C functions are bound directly with
`@_silgen_name` (for example in `Auth/PrivateState.swift`).

## Sources/ folders

| Folder | What lives there |
| --- | --- |
| `App/` | `AppDelegate`, `RootViewController` (the root container and tabs) |
| `Auth/` | Login screen, session unlock, `PrivateState` (encrypted local storage) |
| `Home/` | Home feed |
| `Explore/` | Explore, search, tag feeds and grids |
| `Posts/` | Post cells and rendering, comments, inline video, photo music, sharing |
| `Profile/` | Profile screens, media grids |
| `Reels/` | Reels |
| `Stories/` | Story tray and viewer |
| `Activity/` | Activity screen |
| `Direct/` | Instagram Direct: inbox, threads, message cells, backend providers |
| `Matrix/` | Matrix client: session, sync, rooms, end-to-end encryption, media cache |
| `Networking/` | Instagram service layer: requests, parsing, caches, stream proxy |
| `Transfer/` | Receiving a session from the companion app |
| `Settings/` | Settings screen |
| `Shared/` | Legacy-iOS UI helpers, image loading, JSON adapter |
| `ThirdParty/` | Bundled source dependencies (JSONKit, libwebp) |

The C and Objective-C files sit directly in `Sources/`.

## How an Instagram request flows

1. A screen asks `MagnistraHomeService` (spread over many files in
   `Networking/`, one area per file: `Feed`, `Comments`, `DirectInbox`, …).
2. The service calls a C function such as `magnistra_transport_fetch_feed`
   (`InstagramTransport.c`; similar files exist for Explore, Reels, Activity and
   profile media). These use libcurl with the CA bundle from `Resources/`.
3. The response body is parsed in Swift (`*Parsing.swift`, `PostMetadata.swift`,
   `InstagramModels.swift`) using the bundled JSONKit through `Shared/JSONKitAdapter.swift`.
4. The result goes back to the screen. Images go through
   `Shared/ImageLoading.swift` and `Networking/ImageCache.swift`; video and
   story media are served to AVFoundation through the local `StreamProxy`
   (libcurl-backed, see `StreamBridge.c`).

`Networking/InstagramCompatibility.swift` holds the switches that choose between
different request strategies when Instagram changes something.

## Session and local storage

Instagram sign-in takes place through a separate companion on a modern device.
Magnistra receives the exported encrypted session through `Transfer/`
(`TransferViewController.swift`, `TransferQR.c`, `TransferReceiver.c`).

`Auth/LoginFlow.swift` and `SessionCryptoV2.c` handle unlocking the imported
session. `MagnistraV2SessionCache` uses a Keychain item bound to the encrypted
archive's fingerprint, allowing the session to be restored on subsequent
launches without importing it again.

Other private app data is handled by `Auth/PrivateState.swift` and
`PrivateState.c`, using libsodium for authenticated encryption and the iOS
Keychain for key storage.

## Matrix

`Matrix/` is a separate client with its own account and connection:
`MatrixSession`, `SyncEngine`, `MatrixAPIClient`, rooms and timelines
(`Room*`, `RoomTimelineVC`), and `MediaCache`. Network I/O goes through
`MatrixBridge.c` and `RoomBridge.c`. End-to-end encryption uses vodozemac
through a small Rust bridge (`ThirdParty/Vodozemac/`, driven from
`MatrixE2EEManager.swift` and `MatrixE2EEMedia.swift`). Parts of this code are
adapted from ElementOld (GPL-3.0-or-later); see `CREDITS.md`.

`Direct/DirectBackendProviders.swift` is where Direct can be backed by either
Instagram or Matrix.

## Media and compatibility shims

- WebP: `WebPThumbnail.c`, `GridFastDecode.c`, animated WebP in
  `ThirdParty/MediaSupport/source/`.
- Voice messages: `opus_bridge.c` (Ogg/Opus to WAV).
- Lottie: legacy Objective-C renderer plus `MagnistraLottieLegacyCompat.m`.
- iOS 5 / armv7 gaps: `IOS5MemsetCompat.c`, `atomic_stubs.S`.

## Build

There is no Xcode project. `icode.plist` lists every Swift, C and Objective-C
source, the libraries to link, the bridging header and the resources. Anyone
porting the app to another build system can start from that file.

## Where to start

- Fixing a feed or profile bug: the matching file in `Networking/` plus its
  screen in `Home/`, `Profile/` or `Explore/`.
- Instagram changed an endpoint: `Networking/InstagramCompatibility.swift` and
  the relevant `*Transport.c`.
- Matrix issue: `Matrix/MatrixSession.swift` and `Matrix/SyncEngine.swift`.

## Code organization notes

The Matrix implementation has two client interfaces: `HTTPClient` and
`CurlFetcher` support the ElementOld-derived Matrix client, while
`MagnistraMatrixHTTPClient` and `MagnistraMatrixCurlFetcher` support the
Matrix-backed Direct integration. Their common HTTP implementation lives in
`Matrix/HTTPClientCore.swift` and `Matrix/CurlCallbacks.swift`.

For Instagram features, UI controllers, service logic and C transports are
organized separately. Changes to network behavior should be checked across
those layers, particularly on the older supported iOS versions.

See [SECURITY.md](SECURITY.md) for security-related details.
