# Third-party source references

Magnistra uses the following third-party libraries. Their copyright and license
notices are provided in `../THIRD_PARTY_NOTICES.md` and `../LICENSES/`.

| Component | Source | Included material |
| --- | --- | --- |
| curl 8.23.0 | https://curl.se/download/curl-8.23.0.tar.xz | `curl/lib/libcurl.a` and headers |
| OpenSSL 3.4.8 | https://github.com/openssl/openssl/releases/download/openssl-3.4.8/openssl-3.4.8.tar.gz | `curl/lib/libssl.a`, `curl/lib/libcrypto.a` and headers |
| libsodium 1.0.20 (ARMv7) | https://download.libsodium.org/libsodium/releases/libsodium-1.0.20.tar.gz | `libsodium/libsodium.a` |
| libwebp 1.3.2 | https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.3.2.tar.gz | `MediaSupport/libwebp*.a`, `MediaSupport/libsharpyuv.a`, and `../Sources/ThirdParty/libwebp/` |
| Lottie for iOS 2.5.3 | https://github.com/airbnb/lottie-ios/tree/2.5.3 | `MediaSupport/liblottieobjc.a` |
| vodozemac 0.11.0 | https://crates.io/crates/vodozemac/0.11.0 | `Vodozemac/libvodozemac_ios5_bridge.a` and `Vodozemac/source/` |
| Opus | https://opus-codec.org/downloads/ | `opus/lib/libopus.a`; upstream source archive in `opus/source/` |
| Ogg | https://xiph.org/downloads/ | `opus/lib/libogg.a`; upstream source archive in `opus/source/` |
| JSONKit | https://github.com/johnezang/JSONKit | `../Sources/libJSONKit.a` and `../Sources/ThirdParty/JSONKit/` |

Magnistra's legacy media integration sources are in `MediaSupport/source/`:
`MagnistraAnimatedWebPBridge.m`, `MagnistraAnimatedWebPDisplay.c`,
`MagnistraLottieLegacyCompat.m` and `media_alias.c`.

The Vodozemac bridge's Rust source, `Cargo.toml`, `Cargo.lock`, target specification
and available dependency source archives are in `Vodozemac/source/`.
The `fetch-upstream-sources.sh` script retrieves additional upstream source
archives and verifies the Rust package checksums recorded in `Cargo.lock`.

Precompiled libraries are included for the project's original build configuration.
The source references above do not guarantee a bit-for-bit rebuild of those archives.
