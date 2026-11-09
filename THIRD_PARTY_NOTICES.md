# Third-party licenses

Portions of the Matrix implementation are adapted from
[ElementOld](https://github.com/RousseAddict/elementold) by RousseAddict and
contributors, licensed GPL-3.0-or-later. See the complete
[GPL version 3 text](LICENSES/ElementOld-GPL-3.0-or-later.txt).

Magnistra application code and the modified GPL-covered ElementOld portions
are distributed under GPL-3.0-or-later; see [LICENSE](LICENSE).
Third-party components retain their original copyright and license terms.

The table below identifies the bundled components and their upstream sources.

| Component | Included files | License |
| --- | --- | --- |
| [Lottie for iOS 2.5.3](https://github.com/airbnb/lottie-ios/tree/2.5.3) — Airbnb and contributors (Objective-C renderer) | `ThirdParty/MediaSupport/liblottieobjc.a` | [Apache-2.0](LICENSES/Apache-2.0.txt) |
| [vodozemac 0.11.0](https://crates.io/crates/vodozemac/0.11.0) — Matrix.org contributors | `ThirdParty/Vodozemac/` | [Apache-2.0](LICENSES/Apache-2.0.txt) |
| [libwebp 1.3.2](https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.3.2.tar.gz) — Google and contributors | `Sources/ThirdParty/libwebp/`, WebP libraries in `ThirdParty/MediaSupport/` | [BSD-3-Clause](LICENSES/libwebp-BSD-3-Clause.txt) |
| [JSONKit](https://github.com/johnezang/JSONKit) — John Engelhart | `Sources/ThirdParty/JSONKit/`, `Sources/libJSONKit.a` | [BSD-style](LICENSES/JSONKit-BSD-3-Clause.txt) |
| [curl 8.23.0](https://curl.se/download/curl-8.23.0.tar.xz) — Daniel Stenberg and contributors | `ThirdParty/curl/` | [curl license](LICENSES/curl.txt) |
| [OpenSSL 3.4.8](https://github.com/openssl/openssl/releases/download/openssl-3.4.8/openssl-3.4.8.tar.gz) — OpenSSL Project | `ThirdParty/curl/lib/libssl.a`, `libcrypto.a` and associated headers | [Apache-2.0](LICENSES/Apache-2.0.txt) |
| [Opus](https://opus-codec.org/downloads/) — Xiph.Org, Skype and contributors | `ThirdParty/opus/lib/libopus.a` | [BSD-style](LICENSES/Opus-BSD.txt) |
| [libogg](https://downloads.xiph.org/releases/ogg/) — Xiph.Org | `ThirdParty/opus/lib/libogg.a` | [BSD-3-Clause](LICENSES/Ogg-BSD-3-Clause.txt) |
| [libsodium 1.0.20](https://download.libsodium.org/libsodium/releases/libsodium-1.0.20.tar.gz) — Frank Denis and contributors | `ThirdParty/libsodium/libsodium.a` | [ISC](LICENSES/libsodium-ISC.txt) |
| [Mozilla CA certificates](https://curl.se/docs/caextract.html) | `Resources/CACert.pem` | [MPL-2.0](LICENSES/MPL-2.0.txt) |
| [Rust standard library](https://github.com/rust-lang/rust) — Rust Project Contributors | bundled in `libvodozemac_ios5_bridge.a` | [MIT](LICENSES/Rust-MIT.txt) or [Apache-2.0](LICENSES/Apache-2.0.txt) |
| [curve25519-dalek](https://github.com/dalek-cryptography/curve25519-dalek) | bundled in `libvodozemac_ios5_bridge.a` | [BSD-3-Clause](LICENSES/curve25519-dalek-BSD-3-Clause.txt) |

## Rust dependencies

The Rust bridge dependencies and their exact versions are listed in
[`ThirdParty/Vodozemac/source/Cargo.lock`](ThirdParty/Vodozemac/source/Cargo.lock).
Individual crate sources and their notices are available from
[crates.io](https://crates.io/).
