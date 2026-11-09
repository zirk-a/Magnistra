# Building for iOS 5

Magnistra is written in Swift, but a standard modern Xcode build cannot make it run on iOS 5 simply by lowering the deployment target. The original ARMv7 build uses a modified Swift compiler, an adapted runtime and legacy linking fixes to bridge the differences between modern Swift and the frameworks available on iOS 5.

## What changes compared with Xcode?

**Swift compilation and runtime.** Modern Swift expects runtime support that iOS 5 does not provide. The build uses a modified Swift 5.6.3 compiler and bundles an adapted Swift runtime based on Swift 5.1.5. Swift code is initially generated with an intermediate iOS 7 target, then linked and adjusted to produce an executable compatible with iOS 5. This is not equivalent to changing `MinimumOSVersion` in an Xcode project.

**Swift class metadata.** Swift marks certain Objective-C class metadata using low-order bits in `class->data`. The iOS 5 Objective-C loader does not handle these flags like newer versions do, which can cause crashes while loading classes. Simply clearing the bits also breaks Swift's own metadata checks. The build applies coordinated compatibility fixes so both runtimes can interpret the classes correctly.

**Grand Central Dispatch.** Modern Swift assumes different ownership rules for Dispatch objects than those used by iOS 5. A modified compiler and matching runtime support the older `dispatch_retain` / `dispatch_release` behavior, avoiding incorrect retain/release operations.

**Executable format and linking.** Modern Xcode produces startup and linking arrangements intended for newer iOS versions. The legacy build uses the appropriate ARMv7 startup support and Mach-O load commands, including an iOS 5 minimum version and the older `LC_UNIXTHREAD` startup path. It also embeds Swift libraries and adjusts their load paths so iOS 5 can find them.

**Unavailable system APIs.** Newer Swift libraries and app code may reference Foundation, UIKit or Objective-C runtime symbols that do not exist on iOS 5. Compatibility implementations and targeted linking adjustments cover required symbols such as `NSUUID`, selected UIKit functionality and Objective-C runtime helpers. APIs that cannot be safely provided still need alternatives or availability checks in the app's source.

**Native dependencies.** C libraries must also be built for ARMv7 and the older operating system. That includes handling missing compiler helpers or atomics rather than assuming a modern library built by Xcode will run unchanged. Magnistra bundles native networking libraries built specifically for its legacy target.

These changes make the **ARMv7 iOS 5 build** possible without rewriting the entire application in Objective-C. They do not mean that ordinary Xcode can reproduce the build unmodified, or that every API introduced after iOS 5 becomes available automatically.
