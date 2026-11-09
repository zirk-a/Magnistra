#!/bin/sh
# Retrieve third-party source archives; no compilation or installation.
# Run from inside the extracted Magnistra/ThirdParty directory or pass a source-archive destination.
set -eu
command -v curl >/dev/null 2>&1 || { echo 'curl required' >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo 'shasum required' >&2; exit 1; }
BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEST="${1:-$BASE/UpstreamSourceArchives}"
CRATES="$BASE/Vodozemac/source/cargo-registry-cache"
mkdir -p "$DEST" "$CRATES"
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
fetch() {
  directory="$1"; name="$2"; url="$3"; expected="${4:-}"
  path="$directory/$name"
  if [ -s "$path" ]; then
    if [ -n "$expected" ] && [ "$(sha "$path")" != "$expected" ]; then
      echo "ERROR: checksum mismatch for existing $path" >&2; exit 2
    fi
    echo "VERIFIED_OR_PRESENT $name"
    return
  fi
  temp="$path.part.$$"
  trap 'rm -f "$temp"' EXIT HUP INT TERM
  echo "FETCH $name"
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 600 --proto '=https' --tlsv1.2 --output "$temp" "$url"
  [ -s "$temp" ] || { echo "ERROR: empty download $name" >&2; exit 3; }
  if [ -n "$expected" ]; then
    actual=$(sha "$temp")
    [ "$actual" = "$expected" ] || {
      echo "ERROR: bad SHA256 for $name: $actual (expected $expected)" >&2; exit 4;
    }
  fi
  mv "$temp" "$path"
  trap - EXIT HUP INT TERM
}
# Rust packages pinned by Cargo.lock.
fetch "$CRATES" curve25519-dalek-derive-0.1.1.crate \
  https://static.crates.io/crates/curve25519-dalek-derive/curve25519-dalek-derive-0.1.1.crate \
  f46882e17999c6cc590af592290432be3bce0428cb0d5f8b6715e4dc7b383eb3
fetch "$CRATES" fiat-crypto-0.3.0.crate \
  https://static.crates.io/crates/fiat-crypto/fiat-crypto-0.3.0.crate \
  64cd1e32ddd350061ae6edb1b082d7c54915b5c672c389143b9a63403a109f24
fetch "$CRATES" r-efi-6.0.0.crate \
  https://static.crates.io/crates/r-efi/r-efi-6.0.0.crate \
  f8dcc9c7d52a811697d2151c701e0d08956f92b0e24136cf4cf27b57a6a0d9bf
# Third-party upstream sources.
fetch "$DEST" curl-8.23.0.tar.xz https://curl.se/download/curl-8.23.0.tar.xz \
  8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5
fetch "$DEST" openssl-3.4.8.tar.gz https://github.com/openssl/openssl/releases/download/openssl-3.4.8/openssl-3.4.8.tar.gz \
  9de9ce2f29e584044ae07ab93fc601637be01fdc91d109c5a655ec7419e6022b
fetch "$DEST" libsodium-1.0.20.tar.gz https://download.libsodium.org/libsodium/releases/libsodium-1.0.20.tar.gz
fetch "$DEST" libwebp-1.3.2.tar.gz https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.3.2.tar.gz
fetch "$DEST" lottie-ios-2.5.3.tar.gz https://github.com/airbnb/lottie-ios/archive/refs/tags/2.5.3.tar.gz
echo 'Source archive downloads complete.'
