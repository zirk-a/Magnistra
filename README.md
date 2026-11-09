# Magnistra

An unofficial Instagram client for older iPhones, built to bring a usable social experience back to legacy iOS.

Magnistra is an independent, native application targeting **iOS 5.0 through iOS 10** on 32-bit devices. It includes Instagram browsing and messaging alongside an optional **Matrix** messaging integration.

> [!WARNING]
> **Alpha software — please use a secondary account.** Magnistra is experimental and may stop working when Instagram changes its services. Use of an unofficial client can result in account restrictions or a ban. Do not test with an account you cannot afford to lose.

## Features

- Home feed, Explore, profiles, posts, Reels and Stories
- Likes, comments, follows and saved posts
- Instagram Direct conversations and media attachments
- Matrix rooms and direct messages, with Olm/Megolm encryption support

Some features are still experimental, and availability may vary by device, iOS version and service changes.

## Supported devices

The ARMv7 release targets **iOS 5.0–10.3.3** on compatible iPhones; iOS 11 and later cannot run 32-bit iOS apps. Development and testing have primarily focused on **iPhone 4 and later**. iPhone 3GS is not a verified target; its memory constraints may require a separate build.

## Installation (jailbroken devices)

**Recommended installation methods (personally tested by the developer):**

- **iFunBox** — working; Magnistra retains the Instagram login after closing and reopening the app.
- **Filza + AppSync** — working; install the IPA on the jailbroken device with AppSync installed.

**Sideloadly and Impactor may not work correctly with this build.**
The exact signing/Keychain cause of the Sideloadly behavior has not been established.

## Signing in

Instagram authentication is handled by a companion on a modern device. The companion signs in using a modern browser environment and exports the session information required by Magnistra. Importing it on the legacy iPhone lets Magnistra connect directly to Instagram; the companion is not a permanent proxy.

A companion app and valid session are required for Instagram access. The companion is a separate project and is not included in this source archive.

Matrix uses its own account login and connection and does not depend on the Instagram session.

## Building from source

Magnistra was built using a personal, Swift-based development tool running directly on an **iPhone SE with iOS 13**. This tool is not publicly available.

The repository includes the application's source code, resources, headers, prebuilt libraries and its original build manifest. **It is not an Xcode project and cannot be compiled directly with Xcode in its current form.**

Adapting the source for Xcode is theoretically possible for **iOS 7 and later**. Building for **iOS 6** may also be possible using the legacy compatibility approach outlined in the **[JWI tutorial](https://j-w-i.org/swiftonios6guidepart1.html)**. Neither route has been verified with this source release.

An Xcode port would require creating and configuring an Xcode project, adapting its build settings and dependencies, and addressing compatibility with the required Swift toolchain, runtime and target iOS versions. The included prebuilt libraries may also need compatibility checks or rebuilding.

## Repository structure

| Directory | Contents |
| --- | --- |
| `Sources/` | Swift, C and Objective-C application code and bundled source dependencies |
| `Resources/` | App icons, interface artwork, configuration and CA certificates |
| `ThirdParty/` | Headers and libraries used by the build |
| `LICENSES/` | License texts for included open-source components |

`icode.plist` in the repository root defines the build inputs. For a tour of the code, see [ARCHITECTURE.md](ARCHITECTURE.md); for security notes, see [SECURITY.md](SECURITY.md).

## License

Magnistra is free software, licensed under the **GNU General Public License,
version 3 or (at your option) any later version** (GPL-3.0-or-later). See
[LICENSE](LICENSE).

Portions of the Matrix implementation are adapted from
[ElementOld](https://github.com/RousseAddict/elementold) (GPL-3.0-or-later).
Bundled third-party libraries keep their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), [LICENSES/](LICENSES/) and
[ThirdParty/UPSTREAM_SOURCES.md](ThirdParty/UPSTREAM_SOURCES.md) for where each
prebuilt library comes from.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.

## Credits

See [CREDITS.md](CREDITS.md).

Magnistra is not affiliated with, sponsored by or endorsed by Meta, Instagram or the Matrix.org Foundation. Instagram and related names are trademarks of their respective owners.
