// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: HTTP client used by Magnistra's Matrix-backed Direct (see HTTPClientCore.swift).
import Foundation

class MagnistraMatrixHTTPClient: MagnistraHTTPClientCore<MagnistraMatrixCurlFetcher> {
    override class var errorDomain: String { "MagnistraMatrixHTTPClient" }
}
