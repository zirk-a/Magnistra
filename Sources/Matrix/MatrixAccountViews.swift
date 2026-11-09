// Overview: Matrix login screen, password authentication and space discovery.
import UIKit
import Security
import QuartzCore
import CoreText
import ImageIO
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import SystemConfiguration

private enum MagnistraMatrixPasswordAuth {
    struct Session {
        let homeserverURL: String
        let userId: String
        let accessToken: String
        let deviceId: String?
    }

    private static func makeError(
        _ message: String,
        code: Int
    ) -> NSError {
        return NSError(
            domain: "MagnistraMatrixLogin",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: message
            ]
        )
    }

    static func login(
        homeserverURL: String,
        username: String,
        password: String
    ) throws -> Session {
        guard
            let caPath = Bundle.main.path(
                forResource: "CACert",
                ofType: "pem"
            )
        else {
            throw makeError(
                "Secure connection support is unavailable.",
                code: 8201
            )
        }

        let body: [String: Any] = [
            "type": "m.login.password",
            "identifier": [
                "type": "m.id.user",
                "user": username
            ],
            "password": password,
            "initial_device_display_name": "Magnistra"
        ]

        let data = try MagnistraJSONKit.data(
            withJSONObject: body,
            options: []
        )

        guard
            let jsonBody = String(
                data: data,
                encoding: .utf8
            )
        else {
            throw makeError(
                "Could not prepare the login request.",
                code: 8202
            )
        }

        let endpoint =
            homeserverURL +
            "/_matrix/client/v3/login"

        let userAgent = "Magnistra/1.0"

        let curlCode: Int32 =
            caPath.withCString { ca in
                endpoint.withCString { url in
                    userAgent.withCString { ua in
                        jsonBody.withCString { json in
                            Int32(
                                magnistra_matrix_login_post_json(
                                    ca,
                                    url,
                                    ua,
                                    json
                                )
                            )
                        }
                    }
                }
            }

        let status =
            magnistra_matrix_login_http_status()

        let tls =
            magnistra_matrix_login_tls_verify_result()

        guard curlCode == 0 else {
            throw makeError(
                "Could not connect to the homeserver.",
                code: 8203
            )
        }

        guard tls == 0 else {
            throw makeError(
                "The secure connection could not be verified.",
                code: 8204
            )
        }

        let length =
            Int(
                magnistra_matrix_login_body_length()
            )

        guard
            length > 0,
            let pointer =
                magnistra_matrix_login_body()
        else {
            throw makeError(
                "The homeserver returned an empty response.",
                code: 8205
            )
        }

        let responseData = Data(
            bytes: pointer,
            count: length
        )

        let object = try MagnistraJSONKit.jsonObject(
            with: responseData,
            options: []
        )

        guard
            let root = object as? [String: Any]
        else {
            throw makeError(
                "The homeserver returned an unexpected response.",
                code: 8206
            )
        }

        guard status >= 200 && status < 300 else {
            let message =
                (root["error"] as? String) ??
                "Login failed (HTTP \(status))."

            throw makeError(
                message,
                code: Int(status)
            )
        }

        guard
            let accessToken = root["access_token"] as? String,
            !accessToken.isEmpty,
            let userId = root["user_id"] as? String,
            !userId.isEmpty
        else {
            throw makeError(
                "The homeserver did not return a complete login session.",
                code: 8207
            )
        }

        return Session(
            homeserverURL: homeserverURL,
            userId: userId,
            accessToken: accessToken,
            deviceId: root["device_id"] as? String
        )
    }
}

final class MagnistraMatrixLoginViewController:
    UIViewController,
    UITextFieldDelegate
{
    private var serverField: UITextField!
    private var usernameField: UITextField!
    private var passwordField: UITextField!
    private var loginButton: UIButton!
    private let loginQueue = OperationQueue()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Login"
        view.backgroundColor = UIColor.groupTableViewBackground
        if UIDevice.current.systemVersion.hasPrefix("7.") {
            view.backgroundColor = UIColor(red: 239.0 / 255.0,
                                           green: 239.0 / 255.0,
                                           blue: 244.0 / 255.0,
                                           alpha: 1.0)
        }

        loginQueue.maxConcurrentOperationCount = 1

        let width = view.bounds.size.width
        let left: CGFloat = 20.0
        let fieldWidth = width - 40.0

        serverField = makeField(
            placeholder: "Homeserver URL",
            y: 45.0,
            secure: false
        )
        serverField.keyboardType = .URL
        serverField.text = MagnistraMatrixAccountStore.homeserverURL
        view.addSubview(serverField)

        usernameField = makeField(
            placeholder: "Username",
            y: 105.0,
            secure: false
        )
        view.addSubview(usernameField)

        passwordField = makeField(
            placeholder: "Password",
            y: 165.0,
            secure: true
        )
        view.addSubview(passwordField)

        loginButton = UIButton(type: .roundedRect)
        loginButton.frame = CGRect(
            x: left,
            y: 230.0,
            width: fieldWidth,
            height: 44.0
        )
        loginButton.setTitle("Log In", for: .normal)
        loginButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17.0)
        loginButton.addTarget(
            self,
            action: #selector(loginTapped),
            for: .touchUpInside
        )
        view.addSubview(loginButton)
    }

    private func makeField(
        placeholder: String,
        y: CGFloat,
        secure: Bool
    ) -> UITextField {
        let field = UITextField(
            frame: CGRect(
                x: 20.0,
                y: y,
                width: view.bounds.size.width - 40.0,
                height: 44.0
            )
        )

        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.isSecureTextEntry = secure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .done
        field.delegate = self

        return field
    }

    @objc private func loginTapped() {
        view.endEditing(true)

        guard
            let raw = serverField.text?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            showAlert("Please enter the homeserver URL.")
            return
        }

        guard
            let username = usernameField.text?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !username.isEmpty
        else {
            showAlert("Please enter your username.")
            return
        }

        let password = passwordField.text ?? ""

        let homeserverURL =
            raw.hasSuffix("/")
                ? String(raw.dropLast())
                : raw

        guard MagnistraPrivateState.shared.isReady else {
            showAlert("Secure Matrix storage is unavailable.")
            return
        }

        setLoading(true)

        loginQueue.addOperation {
            do {
                let session =
                    try MagnistraMatrixPasswordAuth.login(
                        homeserverURL: homeserverURL,
                        username: username,
                        password: password
                    )

                OperationQueue.main.addOperation {
                    MagnistraMatrixAccountStore.homeserverURL =
                        session.homeserverURL
                    MagnistraMatrixAccountStore.userId =
                        session.userId
                    MagnistraMatrixAccountStore.accessToken =
                        session.accessToken
                    MagnistraMatrixAccountStore.deviceId =
                        session.deviceId

                    guard MagnistraMatrixAccountStore.homeserverURL == session.homeserverURL,
                          MagnistraMatrixAccountStore.userId == session.userId,
                          MagnistraMatrixAccountStore.accessToken == session.accessToken,
                          MagnistraMatrixAccountStore.deviceId == session.deviceId else {
                        self.setLoading(false)
                        self.showAlert("Could not save the Matrix session securely.")
                        return
                    }
                    self.setLoading(false)
                    self.navigationController?
                        .popViewController(animated: true)
                }
            } catch {
                let message =
                    (error as NSError).localizedDescription

                OperationQueue.main.addOperation {
                    self.setLoading(false)
                    self.showAlert(message)
                }
            }
        }
    }

    private func setLoading(
        _ loading: Bool
    ) {
        loginButton.isEnabled = !loading
        loginButton.setTitle(
            loading ? "Logging In..." : "Log In",
            for: .normal
        )
        serverField.isEnabled = !loading
        usernameField.isEnabled = !loading
        passwordField.isEnabled = !loading
    }

    private func showAlert(
        _ message: String
    ) {
        let alert = UIAlertView(
            title: "Magnistra",
            message: message,
            delegate: nil,
            cancelButtonTitle: "OK"
        )

        alert.show()
    }

    func textFieldShouldReturn(
        _ textField: UITextField
    ) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

private struct MagnistraMatrixSpaceOption {
    let roomId: String
    let name: String
}

private enum MagnistraMatrixSpaceDiscovery {
    private static let userAgent =
        "Magnistra/1.0"

    private static let stateOnlyFilter =
        "%7B%22room%22%3A%7B%22timeline%22%3A%7B%22limit%22%3A0%7D%2C%22ephemeral%22%3A%7B%22types%22%3A%5B%5D%7D%2C%22account_data%22%3A%7B%22types%22%3A%5B%5D%7D%7D%2C%22presence%22%3A%7B%22types%22%3A%5B%5D%7D%7D"

    private static func makeError(
        _ message: String,
        code: Int
    ) -> NSError {
        return NSError(
            domain: "MagnistraMatrixSpace",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey:
                    message
            ]
        )
    }

    static func load() throws -> [MagnistraMatrixSpaceOption] {
        guard
            let homeserver =
                MagnistraMatrixAccountStore.homeserverURL,
            let accessToken =
                MagnistraMatrixAccountStore.accessToken
        else {
            throw makeError(
                "Sign in to Matrix first.",
                code: 8301
            )
        }

        guard
            let caPath =
                Bundle.main.path(
                    forResource:
                        "CACert",
                    ofType:
                        "pem"
                )
        else {
            throw makeError(
                "Secure connection support is unavailable.",
                code: 8302
            )
        }

        let base =
            homeserver.hasSuffix("/")
                ? String(homeserver.dropLast())
                : homeserver

        let url =
            base +
            "/_matrix/client/v3/sync?timeout=0&filter=" +
            stateOnlyFilter

        let curlCode: Int32 =
            caPath.withCString { ca in
                url.withCString { requestURL in
                    accessToken.withCString { token in
                        userAgent.withCString { ua in
                            Int32(
                                magnistra_matrix_space_get_json(
                                    ca,
                                    requestURL,
                                    token,
                                    ua
                                )
                            )
                        }
                    }
                }
            }

        let status =
            magnistra_matrix_space_http_status()

        let tls =
            magnistra_matrix_space_tls_verify_result()

        guard curlCode == 0 else {
            throw makeError(
                "Could not load Matrix spaces.",
                code: 8303
            )
        }

        guard tls == 0 else {
            throw makeError(
                "The secure connection could not be verified.",
                code: 8304
            )
        }

        let length =
            Int(
                magnistra_matrix_space_body_length()
            )

        guard
            length > 0,
            let pointer =
                magnistra_matrix_space_body()
        else {
            throw makeError(
                "The homeserver returned an empty response.",
                code: 8305
            )
        }

        let data =
            Data(
                bytes:
                    pointer,
                count:
                    length
            )

        let object =
            try MagnistraJSONKit
                .jsonObject(
                    with:
                        data,
                    options:
                        []
                )

        guard
            let root =
                object as? [String: Any]
        else {
            throw makeError(
                "The homeserver returned an unexpected response.",
                code: 8306
            )
        }

        guard status >= 200 && status < 300 else {
            let message =
                (root["error"] as? String) ??
                "Could not load spaces (HTTP \(status))."

            throw makeError(
                message,
                code:
                    Int(status)
            )
        }

        guard
            let rooms =
                root["rooms"] as? [String: Any],
            let joined =
                rooms["join"] as? [String: Any]
        else {
            return []
        }

        var result:
            [MagnistraMatrixSpaceOption] = []

        for (roomId, rawRoom) in joined {
            guard
                let room =
                    rawRoom as? [String: Any],
                let state =
                    room["state"] as? [String: Any],
                let events =
                    state["events"] as? [[String: Any]]
            else {
                continue
            }

            var isSpace = false
            var roomName: String?
            var canonicalAlias: String?

            for event in events {
                guard
                    let type =
                        event["type"] as? String,
                    let content =
                        event["content"] as? [String: Any]
                else {
                    continue
                }

                if
                    type == "m.room.create",
                    let roomType =
                        content["type"] as? String,
                    roomType == "m.space"
                {
                    isSpace = true
                }

                if
                    type == "m.room.name",
                    let value =
                        content["name"] as? String,
                    !value.isEmpty
                {
                    roomName = value
                }

                if
                    type == "m.room.canonical_alias",
                    let value =
                        content["alias"] as? String,
                    !value.isEmpty
                {
                    canonicalAlias = value
                }
            }

            guard isSpace else {
                continue
            }

            let label =
                roomName ??
                canonicalAlias ??
                roomId

            result.append(
                MagnistraMatrixSpaceOption(
                    roomId:
                        roomId,
                    name:
                        label
                )
            )
        }

        result.sort {
            $0.name.lowercased() <
            $1.name.lowercased()
        }

        return result
    }
}

final class MagnistraMatrixSpacePickerViewController:
    UITableViewController
{
    private let pullRefreshGesture = MagnistraPullRefreshGesture()
    private let pullRefreshIndicator = MagnistraNavigationPullIndicator()

    private var spaces:
        [MagnistraMatrixSpaceOption] = []

    private var loading = false

    private let loadQueue:
        OperationQueue = {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            return queue
        }()

    override func viewDidLoad() {
        super.viewDidLoad()
        pullRefreshGesture.install(on: tableView) { [weak self] in
            self?.refreshTapped()
        }

        title = "Instagram Space"
        if UIDevice.current.systemVersion.hasPrefix("7.") {
            magnistraUseIOS7GroupedSettingsBackdrop(tableView)
        }

        navigationItem.rightBarButtonItem = nil

        loadSpaces()
    }

    override func viewWillAppear(
        _ animated: Bool
    ) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    @objc private func refreshTapped() {
        guard !loading else { return }
        pullRefreshIndicator.begin(on: navigationItem, label: "Updating Instagram Space")
        loadSpaces()
    }

    private func loadSpaces() {
        guard !loading else {
            return
        }

        loading = true
        spaces.removeAll()
        tableView.reloadData()

        loadQueue.addOperation {
            do {
                let loaded =
                    try MagnistraMatrixSpaceDiscovery
                        .load()

                OperationQueue.main.addOperation {
                    self.spaces = loaded
                    self.loading = false
                    self.pullRefreshIndicator.end(on: self.navigationItem)
                    self.tableView.reloadData()
                }
            } catch {
                let message =
                    (error as NSError)
                        .localizedDescription

                OperationQueue.main.addOperation {
                    self.loading = false
                    self.pullRefreshIndicator.end(on: self.navigationItem)
                    self.spaces.removeAll()
                    self.tableView.reloadData()

                    let alert =
                        UIAlertView(
                            title:
                                "Matrix",
                            message:
                                message,
                            delegate:
                                nil,
                            cancelButtonTitle:
                                "OK"
                        )

                    alert.show()
                }
            }
        }
    }

    override func numberOfSections(
        in tableView: UITableView
    ) -> Int {
        return 1
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        if loading || spaces.isEmpty {
            return 1
        }

        return spaces.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier =
            "MagnistraMatrixSpaceCell"

        let cell =
            tableView.dequeueReusableCell(
                withIdentifier:
                    identifier
            ) ??
            UITableViewCell(
                style:
                    .subtitle,
                reuseIdentifier:
                    identifier
            )

        cell.accessoryType = .none
        cell.selectionStyle = .blue
        cell.detailTextLabel?.text = nil

        if loading {
            cell.textLabel?.text =
                "Loading Spaces..."
            cell.textLabel?.textColor =
                UIColor.gray
            cell.selectionStyle = .none
            return cell
        }

        if spaces.isEmpty {
            cell.textLabel?.text =
                "No Spaces Found"
            cell.textLabel?.textColor =
                UIColor.gray
            cell.selectionStyle = .none
            return cell
        }

        let space =
            spaces[indexPath.row]

        cell.textLabel?.text =
            space.name

        cell.textLabel?.textColor =
            UIColor.black

        cell.detailTextLabel?.text =
            space.roomId

        if
            MagnistraMatrixAccountStore
                .instagramSpaceId ==
            space.roomId
        {
            cell.accessoryType =
                .checkmark
        }

        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(
            at:
                indexPath,
            animated:
                true
        )

        guard
            !loading,
            !spaces.isEmpty,
            indexPath.row < spaces.count
        else {
            return
        }

        let selected =
            spaces[indexPath.row]

        MagnistraMatrixAccountStore
            .selectInstagramSpace(
                id:
                    selected.roomId,
                name:
                    selected.name
            )

        navigationController?
            .popViewController(
                animated:
                    true
            )
    }
}

enum MagnistraMatrixAccountStore {
    private static let defaults = MagnistraPrivateState.shared
    private static let prefix = "magnistra.matrix."

    private static func string(_ key: String) -> String? {
        guard
            let value = defaults.string(forKey: prefix + key)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private static func setString(_ value: String?, key: String) {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalized = normalized, !normalized.isEmpty {
            defaults.set(normalized, forKey: prefix + key)
        } else {
            defaults.removeObject(forKey: prefix + key)
        }
        defaults.synchronize()
    }

    static var homeserverURL: String? {
        get { return string("homeserverURL") }
        set { setString(newValue, key: "homeserverURL") }
    }

    static var userId: String? {
        get { return string("userId") }
        set { setString(newValue, key: "userId") }
    }

    static var accessToken: String? {
        get { return string("accessToken") }
        set { setString(newValue, key: "accessToken") }
    }

    static var deviceId: String? {
        get { return string("deviceId") }
        set { setString(newValue, key: "deviceId") }
    }

    static var recoveryCode: String? {
        get { return nil }
        set {
            defaults.removeObject(forKey: prefix + "recoveryCode")
            defaults.synchronize()
        }
    }

    static var instagramSpaceId: String? {
        get { return string("instagramSpaceId") }
        set {
            setString(newValue, key: "instagramSpaceId")
            defaults.set(false, forKey: prefix + "instagramSpaceValidated")
            defaults.synchronize()
        }
    }

    static var instagramSpaceName: String? {
        get { return string("instagramSpaceName") }
        set { setString(newValue, key: "instagramSpaceName") }
    }

    static func selectInstagramSpace(
        id: String,
        name: String
    ) {
        setString(
            id,
            key:
                "instagramSpaceId"
        )

        setString(
            name,
            key:
                "instagramSpaceName"
        )

        defaults.set(
            true,
            forKey:
                prefix +
                "instagramSpaceValidated"
        )

        defaults.synchronize()
    }

    static var hasSession: Bool {
        return homeserverURL != nil && userId != nil && accessToken != nil
    }

    static var recoveryConfigured: Bool {
        return MagnistraMegolmKeyStore.shared.count > 0
    }

    static var encryptionReady: Bool {
        return MagnistraMegolmKeyStore.shared.count > 0
    }

    static var instagramSpaceConfigured: Bool {
        return instagramSpaceId != nil
    }

    static var instagramSpaceValidated: Bool {
        return defaults.bool(forKey: prefix + "instagramSpaceValidated")
    }

    static var matrixReady: Bool {
        return hasSession && encryptionReady && instagramSpaceValidated
    }

    static func clearSession() {
        for key in [
            "userId",
            "accessToken",
            "deviceId",
            "recoveryCode",
            "instagramSpaceId",
            "instagramSpaceName",
            "instagramSpaceValidated"
        ] {
            defaults.removeObject(forKey: prefix + key)
        }
        defaults.synchronize()

        MagnistraMegolmKeyStore.shared.discard()
        MagnistraMatrixDecryptor.shared.reset()
}
}

final class MagnistraMatrixSettingsViewController:
    UITableViewController,
    UIAlertViewDelegate
{
    private enum PromptTag: Int {
        case homeserver = 9101
        case recovery = 9102
        case instagramSpace = 9103
        case logout = 9104
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Matrix / Beeper"
        if UIDevice.current.systemVersion.hasPrefix("7.") {
            magnistraUseIOS7GroupedSettingsBackdrop(tableView)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        switch section {
        case 0: return "Account"
        case 1: return "Encryption"
        case 2: return "Instagram"
        case 3: return "Status"
        default: return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        switch section {
        case 0:
            return MagnistraMatrixAccountStore.hasSession ? 2 : 1
        case 1: return 1
        case 2: return 1
        case 3: return 1
        default: return 0
        }
    }

    private func cell(
        _ tableView: UITableView,
        title: String,
        detail: String,
        disclosure: Bool
    ) -> UITableViewCell {
        let identifier = "MagnistraMatrixSettingsCell"
        let cell =
            tableView.dequeueReusableCell(withIdentifier: identifier) ??
            UITableViewCell(style: .value1, reuseIdentifier: identifier)

        cell.textLabel?.text = title
        cell.detailTextLabel?.text = detail
        cell.accessoryType = disclosure ? .disclosureIndicator : .none
        cell.selectionStyle = disclosure ? .blue : .none
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                return cell(
                    tableView,
                    title: "Account",
                    detail: MagnistraMatrixAccountStore.hasSession
                        ? (MagnistraMatrixAccountStore.userId ?? "Signed In")
                        : "Sign In",
                    disclosure: !MagnistraMatrixAccountStore.hasSession
                )
            }

            let logoutCell =
                cell(
                    tableView,
                    title: "Log Out",
                    detail: "",
                    disclosure: false
                )

            logoutCell.textLabel?.textColor = UIColor.red
            logoutCell.selectionStyle = .blue
            return logoutCell
        }

        if indexPath.section == 1 {
            return cell(
                tableView,
                title: "Recovery Code",
                detail: MagnistraMatrixAccountStore.recoveryConfigured
                    ? "Configured"
                    : "Not Configured",
                disclosure: true
            )
        }

        if indexPath.section == 2 {
            return cell(
                tableView,
                title: "Instagram Space",
                detail:
                    MagnistraMatrixAccountStore.instagramSpaceName ??
                    MagnistraMatrixAccountStore.instagramSpaceId ??
                    "Not Set",
                disclosure: true
            )
        }

        return cell(
            tableView,
            title: "Matrix Ready",
            detail: MagnistraMatrixAccountStore.matrixReady ? "Ready" : "Not Ready",
            disclosure: false
        )
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        switch section {
        case 0:
            return "Sign in with your homeserver, username, and password."
        case 1:
            return "Restore encrypted message keys using your Matrix recovery key."
        case 2:
            return "Only rooms belonging to this Instagram Space will be allowed into Magnistra Direct."
        case 3:
            return nil
        default:
            return nil
        }
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 && indexPath.row == 0 {
            if !MagnistraMatrixAccountStore.hasSession {
                let controller = MagnistraMatrixLoginViewController()
                navigationController?.pushViewController(
                    controller,
                    animated: true
                )
            }
            return
        }

        if
            indexPath.section == 0 &&
            indexPath.row == 1 &&
            MagnistraMatrixAccountStore.hasSession
        {
            let alert =
                UIAlertView(
                    title: "Log Out",
                    message: "Sign out of this Matrix account?",
                    delegate: self,
                    cancelButtonTitle: "Cancel",
                    otherButtonTitles: "Log Out"
                )

            alert.tag = PromptTag.logout.rawValue
            alert.show()
            return
        }

        if indexPath.section == 1 {
            guard
                MagnistraMatrixAccountStore.hasSession,
                let homeserver = MagnistraMatrixAccountStore.homeserverURL,
                let token = MagnistraMatrixAccountStore.accessToken
            else {
                let alert = UIAlertView(
                    title: "Matrix",
                    message: "Sign in before restoring message keys.",
                    delegate: nil,
                    cancelButtonTitle: "OK"
                )
                alert.show()
                return
            }

            let client = MagnistraMatrixRecoveryClient(
                homeserver: homeserver,
                accessToken: token
            )

            let controller = MagnistraMatrixRecoveryKeyViewController(
                client: client
            )

            controller.onRestored = { [weak self] in
                self?.tableView.reloadData()
            }

            navigationController?.pushViewController(
                controller,
                animated: true
            )
            return
        }

        if indexPath.section == 2 {
            guard
                MagnistraMatrixAccountStore.hasSession
            else {
                let alert =
                    UIAlertView(
                        title:
                            "Matrix",
                        message:
                            "Sign in before selecting a Space.",
                        delegate:
                            nil,
                        cancelButtonTitle:
                            "OK"
                    )

                alert.show()
                return
            }

            let controller =
                MagnistraMatrixSpacePickerViewController(
                    style:
                        .grouped
                )

            navigationController?
                .pushViewController(
                    controller,
                    animated:
                        true
                )

            return
        }
    }

    private func showPrompt(
        tag: PromptTag,
        title: String,
        current: String?,
        secure: Bool
    ) {
        let alert = UIAlertView(
            title: title,
            message: "",
            delegate: self,
            cancelButtonTitle: "Cancel",
            otherButtonTitles: "Save"
        )

        alert.tag = tag.rawValue
        if secure {
            alert.alertViewStyle =
                UIAlertViewStyle.secureTextInput
        } else {
            alert.alertViewStyle =
                UIAlertViewStyle.plainTextInput
        }

        if !secure {
            alert.textField(at: 0)?.text = current
        }

        alert.show()
    }

    func alertView(
        _ alertView: UIAlertView,
        clickedButtonAt buttonIndex: Int
    ) {
        guard buttonIndex != alertView.cancelButtonIndex else {
            return
        }

        if alertView.tag == PromptTag.logout.rawValue {
            MagnistraMatrixDirectBackend.shared.resetForLogout()
            MagnistraMatrixAccountStore.clearSession()
            tableView.reloadData()
            return
        }
        let value = alertView.textField(at: 0)?.text

        switch alertView.tag {

        case PromptTag.homeserver.rawValue:
            MagnistraMatrixAccountStore.homeserverURL = value
        case PromptTag.recovery.rawValue:
            MagnistraMatrixAccountStore.recoveryCode = value
        case PromptTag.instagramSpace.rawValue:
            MagnistraMatrixAccountStore.instagramSpaceId = value
        default:
            return
        }

        tableView.reloadData()
    }
}

