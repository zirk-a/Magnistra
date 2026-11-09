// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Screen to search for and invite a user to a room.
import Foundation
import UIKit

class InviteUserVC: UIViewController {

    private let roomId: String
    private let client: MatrixAPIClient
    private var results: [UserDirectory.Result] = []
    private var searchToken = 0
    private var inviting = false

    private var tableView: UITableView!
    private var headerContainer: UIView!
    private var searchField: UITextField!
    private let cellId = "InviteResultCell"

    init(roomId: String, client: MatrixAPIClient) {
        self.roomId = roomId
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Invite"
        view.backgroundColor = .white

        tableView = UITableView(frame: view.bounds, style: .plain)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 58
        view.addSubview(tableView)

        let width = view.bounds.width
        headerContainer = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 58))
        headerContainer.autoresizingMask = [.flexibleWidth]
        searchField = makeRoundedField(placeholder: "Search users or @user:server")
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.returnKeyType = .search
        searchField.frame = CGRect(x: 12, y: 12, width: width - 24, height: 34)
        searchField.addTarget(self, action: #selector(searchEditingChanged), for: .editingChanged)
        searchField.delegate = self
        headerContainer.addSubview(searchField)
        tableView.tableHeaderView = headerContainer
    }

    @objc private func searchEditingChanged() { performSearch() }

    private func performSearch() {
        searchToken += 1
        let token = searchToken
        UserDirectory.search(client: client, term: (searchField.text ?? "").trimmed()) { [weak self] found in
            guard let self = self, token == self.searchToken else { return }
            self.results = found
            self.tableView.reloadData()
        }
    }

    private func invite(userId: String, name: String) {
        guard !inviting else { return }
        inviting = true
        view.endEditing(true)

        client.post("/_matrix/client/v3/rooms/\(roomId)/invite",
                    body: ["user_id": userId]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.inviting = false
                if let error = error {
                    self.showAlert("Couldn't invite", "\(error)")
                } else {

                    _ = name
                    self.navigationController?.popViewController(animated: true)
                }
            }
        }
    }

    private func showAlert(_ title: String, _ message: String) {
#if LEGACY_TARGET
        let alert = UIAlertView()
        alert.title = title
        alert.message = message
        alert.addButton(withTitle: "OK")
        alert.show()
#else
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
#endif
    }
}

extension InviteUserVC: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        performSearch()
        return true
    }
}

extension InviteUserVC: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: cellId)
        let r = results[indexPath.row]
        cell.textLabel?.text = r.name
        cell.detailTextLabel?.text = r.userId
        cell.detailTextLabel?.textColor = .gray
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let r = results[indexPath.row]
        invite(userId: r.userId, name: r.name)
    }
}
