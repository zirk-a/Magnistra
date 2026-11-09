// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Matrix user directory search and MXID helpers.
import Foundation
import UIKit

struct UserDirectory {
    typealias Result = (userId: String, name: String, avatarMxc: String?)

    static func search(client: MatrixAPIClient, term: String,
                       completion: @escaping ([Result]) -> Void) {
        let mxidRow: [Result] = looksLikeMXID(term) ? [(userId: term, name: term, avatarMxc: nil)] : []
        guard term.count >= 2 else { completion(mxidRow); return }
        client.post("/_matrix/client/v3/user_directory/search",
                    body: ["search_term": term, "limit": 20]) { json, _ in
            DispatchQueue.main.async {
                var found: [Result] = []
                if let arr = json?["results"] as? [[String: Any]] {
                    for r in arr {
                        guard let uid = r["user_id"] as? String else { continue }
                        let dn = (r["display_name"] as? String) ?? uid
                        found.append((userId: uid, name: dn, avatarMxc: r["avatar_url"] as? String))
                    }
                }
                for m in mxidRow where !found.contains(where: { $0.userId == m.userId }) {
                    found.insert(m, at: 0)
                }
                completion(found)
            }
        }
    }

    static func looksLikeMXID(_ s: String) -> Bool {
        return s.hasPrefix("@") && s.firstIndex(of: ":") != nil && s.count >= 4
    }
}

func makeRoundedField(placeholder: String) -> UITextField {
    let f = UITextField()
    f.borderStyle = .none
    f.backgroundColor = .white
    f.layer.cornerRadius = 8
    f.layer.masksToBounds = true
    f.layer.borderWidth = 0.5
    f.layer.borderColor = UIColor(white: 0.8, alpha: 1.0).cgColor
    f.font = UIFont.systemFont(ofSize: 16)
    f.contentVerticalAlignment = .center
    f.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
    f.leftViewMode = .always
    f.placeholder = placeholder
    f.clearButtonMode = .whileEditing
    return f
}

extension String {
        func trimmed() -> String {
            let ws: Set<Character> = [" ", "\t", "\n", "\r"]
            var chars = Array(self)
            while let f = chars.first, ws.contains(f) { chars.removeFirst() }
            while let l = chars.last, ws.contains(l) { chars.removeLast() }
            return String(chars)
        }
}
