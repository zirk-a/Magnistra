# Security

Magnistra is an experimental client for legacy iOS. This document describes
security mechanisms present in the source and their practical limits. It is not
a security certification or an independent audit.

## Data and connection protection

- **HTTPS connections.** The Instagram and Matrix transports use libcurl and
  OpenSSL, with certificate and hostname verification configured against the
  bundled CA certificates in `Resources/CACert.pem`. The certificate bundle
  needs maintenance as trust roots change.
- **Imported Instagram sessions.** The session archive is encrypted using
  Argon2id for key derivation and XChaCha20-Poly1305 for authenticated
  encryption. Its protection depends in part on the credentials selected when
  exporting it. Weak credentials can be attacked offline if the file is copied.
- **Local private data.** `PrivateState.c` protects selected local state with
  XChaCha20-Poly1305. The associated key is stored in the iOS Keychain with a
  device-only accessibility setting. The unlocked Instagram session may also
  be cached in the Keychain, associated with the imported encrypted archive.
- **Device-to-device transfer.** The companion transfer implements Curve25519
  key agreement, authenticated encryption and a code-confirmation step before
  accepting the archive.
- **Matrix encryption.** Matrix messaging includes Olm/Megolm support through
  vodozemac. Protection depends on the relevant encryption and verification
  state of each conversation.

## Security considerations

**Legacy operating systems.** Supported iOS versions no longer receive normal
security updates, and many installations rely on a jailbreak. Device security
cannot be guaranteed by the app alone.

**Account sessions.** An imported Instagram session is sensitive account data.
Keep session files, transfer codes and credentials private. Even an encrypted
archive should not be shared publicly. Using a secondary Instagram account is
recommended; see the account warning in [README.md](README.md).

**Local media playback.** Some video and story streams are fetched through
libcurl and exposed to AVFoundation through an HTTP endpoint on the device
(`127.0.0.1`). On **iOS 9**, `NSAllowsArbitraryLoads` is enabled under App
Transport Security (ATS) so AVFoundation can access that local HTTP stream.
On **iOS 10 and later**, `NSAllowsLocalNetworking` is also configured for local
connections. These settings concern the local playback connection; they do not
replace libcurl's certificate and hostname checks for remote HTTPS requests.

## Reporting security issues

Please report suspected vulnerabilities privately through the repository's
GitHub security reporting feature, when available, or contact the maintainer
privately. Do not include passwords, session archives or other credentials in
public issues.
