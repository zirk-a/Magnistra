// Overview: Settings screens: keyboard preferences and photo quality.
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

enum KeyboardPreferences {
    private static let predictiveKey = "MagnistraKeyboardPredictiveEnabled"
    private static let spellingKey = "MagnistraKeyboardSpellingEnabled"

    static var predictiveEnabled: Bool {
        guard let stored = UserDefaults.standard.object(forKey: predictiveKey) as? Bool else { return true }
        return stored
    }
    static var spellingEnabled: Bool {
        guard let stored = UserDefaults.standard.object(forKey: spellingKey) as? Bool else { return true }
        return stored
    }
    static func setPredictive(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: predictiveKey)
    }
    static func setSpelling(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: spellingKey)
    }
    static func apply(to view: UITextView) {
        view.autocorrectionType = predictiveEnabled ? .default : .no
        view.spellCheckingType = spellingEnabled ? .default : .no
    }
}

final class KeyboardSettingsViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Keyboard"
        tableView.backgroundView = nil
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { return 1 }
    override func tableView(_ tableView: UITableView,
                            numberOfRowsInSection section: Int) -> Int { return 2 }
    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "MagnistraKeyboardOverrideSwitchCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
        let predictive = indexPath.row == 0
        cell.textLabel?.text = predictive ? "Predictive Text" : "Check Spelling"
        cell.selectionStyle = .none
        cell.accessoryType = .none
        let toggle = UISwitch(frame: CGRect.zero)
        toggle.tag = indexPath.row
        toggle.isOn = predictive
            ? KeyboardPreferences.predictiveEnabled
            : KeyboardPreferences.spellingEnabled
        toggle.addTarget(self, action: #selector(keyboardOverrideChanged(_:)),
                         for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }
    @objc private func keyboardOverrideChanged(_ control: UISwitch) {
        if control.tag == 0 {
            KeyboardPreferences.setPredictive(control.isOn)
        } else if control.tag == 1 {
            KeyboardPreferences.setSpelling(control.isOn)
        }
    }
    override func tableView(_ tableView: UITableView,
                            heightForFooterInSection section: Int) -> CGFloat {
        return 60.0
    }
    override func tableView(_ tableView: UITableView,
                            viewForFooterInSection section: Int) -> UIView? {
        let footer = UIView(frame: CGRect(x: 0, y: 0,
            width: tableView.bounds.width, height: 60.0))
        footer.backgroundColor = UIColor.clear
        let caption = UILabel(frame: CGRect(x: 16.0, y: 6.0,
            width: max(1.0, tableView.bounds.width - 32.0), height: 48.0))
        caption.autoresizingMask = [.flexibleWidth]
        caption.backgroundColor = UIColor.clear
        caption.numberOfLines = 0
        caption.lineBreakMode = .byWordWrapping
        caption.font = UIFont.systemFont(ofSize: 12.0)
        caption.textColor = UIColor(white: 0.44, alpha: 1.0)
        caption.text = "Disable these only if Magnistra crashes while typing in certain keyboard languages."
        footer.addSubview(caption)
        return footer
    }
}

final class SettingsViewController:
    UITableViewController
{
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Settings"

        tableView.backgroundView = nil
    }

    override func numberOfSections(
        in tableView: UITableView
    ) -> Int {
        return 3
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        if section == 2 { return 1 }
        if section == 1 { return 1 }
        return 1
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        if section == 2 { return "Override" }
        if section == 1 { return "Direct" }
        return "Media"
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if indexPath.section == 2 {
            let identifier = "MagnistraKeyboardNavigationCell"
            let result = tableView.dequeueReusableCell(withIdentifier: identifier)
                ?? UITableViewCell(style: .value1, reuseIdentifier: identifier)
            result.textLabel?.text = "Keyboard"
            result.detailTextLabel?.text = nil
            result.accessoryView = nil
            result.accessoryType = .disclosureIndicator
            result.selectionStyle = .blue
            return result
        }
        if indexPath.section == 1 {
            let identifier =
                "MagnistraMatrixSettingsEntryCell"

            var cell =
                tableView.dequeueReusableCell(
                    withIdentifier:
                        identifier
                )

            if cell == nil {
                cell =
                    UITableViewCell(
                        style:
                            .value1,
                        reuseIdentifier:
                            identifier
                    )
            }

            guard let result = cell else {
                return UITableViewCell()
            }

            result.textLabel?.text =
                "Matrix / Beeper"

            result.detailTextLabel?.text =
                MagnistraMatrixAccountStore
                    .matrixReady
                    ? "Ready"
                    : "Not Ready"

            result.accessoryType =
                .disclosureIndicator

            result.selectionStyle =
                .blue

            return result
        }

        let identifier =
            "MediaSettingsCell"

        var cell =
            tableView.dequeueReusableCell(
                withIdentifier:
                    identifier
            )

        if cell == nil {
            cell =
                UITableViewCell(
                    style: .value1,
                    reuseIdentifier:
                        identifier
                )
        }

        guard let result = cell else {
            return UITableViewCell()
        }

        result.textLabel?.text = nil
        result.detailTextLabel?.text = nil
        result.accessoryType = .none
        result.selectionStyle = .default

        if indexPath.row == 0 {
            result.textLabel?.text =
                "Photo Quality"

            result.detailTextLabel?.text =
                MagnistraMediaPreferences
                    .photoQuality
                    .displayName

            result.accessoryType =
                .disclosureIndicator
        }

        return result
    }

    override func viewWillAppear(
        _ animated: Bool
    ) {
        super.viewWillAppear(animated)

        tableView.reloadData()
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        if indexPath.section == 2 {
            tableView.deselectRow(at: indexPath, animated: true)
            navigationController?.pushViewController(
                KeyboardSettingsViewController(style: .grouped),
                animated: true
            )
            return
        }
        if indexPath.section == 1 {
            tableView.deselectRow(
                at:
                    indexPath,
                animated:
                    true
            )

            let controller =
                MagnistraMatrixSettingsViewController(style: .grouped)

            navigationController?
                .pushViewController(
                    controller,
                    animated:
                        true
                )

            return
        }

        tableView.deselectRow(
            at: indexPath,
            animated: true
        )

        guard indexPath.row == 0 else {
            return
        }

        let controller =
            PhotoQualityViewController(
                style: .grouped
            )

        navigationController?
            .pushViewController(
                controller,
                animated: true
            )
    }

}

func magnistraUseIOS7GroupedSettingsBackdrop(_ tableView: UITableView) {
    let systemGroupedGrey = UIColor(red: 239.0 / 255.0,
                                    green: 239.0 / 255.0,
                                    blue: 244.0 / 255.0,
                                    alpha: 1.0)
    tableView.backgroundColor = systemGroupedGrey
    let flatBackground = UIView(frame: tableView.bounds)
    flatBackground.backgroundColor = systemGroupedGrey
    flatBackground.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    tableView.backgroundView = flatBackground
}

final class PhotoQualityViewController:
    UITableViewController
{
    private let qualities:
        [MagnistraPhotoQuality] =
            [
                .standard,
                .retina,
                .highest
            ]

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Photo Quality"
        tableView.backgroundView = nil
        if UIDevice.current.systemVersion.hasPrefix("7.") {
            magnistraUseIOS7GroupedSettingsBackdrop(tableView)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        return qualities.count
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        return "Feed Photos"
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        return
            "Standard uses about 320 px. Retina targets about 640 px. " +
            "Highest chooses the largest image offered for each post."
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier =
            "PhotoQualityCell"

        var cell =
            tableView.dequeueReusableCell(
                withIdentifier:
                    identifier
            )

        if cell == nil {
            cell =
                UITableViewCell(
                    style: .subtitle,
                    reuseIdentifier:
                        identifier
                )
        }

        guard let result = cell else {
            return UITableViewCell()
        }

        let quality =
            qualities[
                indexPath.row
            ]

        result.textLabel?.text =
            quality.displayName

        switch quality {
        case .standard:
            result.detailTextLabel?.text =
                "About 320 px - fastest"
        case .retina:
            result.detailTextLabel?.text =
                "About 640 px - sharper on Retina"
        case .highest:
            result.detailTextLabel?.text =
                "Largest available image"
        }

        if quality.rawValue ==
            MagnistraMediaPreferences
                .photoQuality
                .rawValue
        {
            result.accessoryType =
                .checkmark
        } else {
            result.accessoryType =
                .none
        }

        return result
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(
            at: indexPath,
            animated: true
        )

        let quality =
            qualities[
                indexPath.row
            ]

        MagnistraMediaPreferences
            .setPhotoQuality(
                quality
            )

        tableView.reloadData()

        navigationController?
            .popViewController(
                animated: true
            )
    }
}

