// Contains code adapted from ElementOld (Copyright (C) 2026 RousseAddict; GPL-3.0-or-later), modified for Magnistra. See CREDITS.md.
// Overview: Simple text editing screen.
import Foundation
import UIKit

class TextEditVC: UIViewController, UITextFieldDelegate {
    var onSave: ((String) -> Void)?
    private let current: String
    private let placeholder: String
    private let multiline: Bool
    private var field: UITextField?
    private var textView: UITextView?

    init(screenTitle: String, placeholder: String, current: String, multiline: Bool) {
        self.current = current
        self.placeholder = placeholder
        self.multiline = multiline
        super.init(nibName: nil, bundle: nil)
        title = screenTitle
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.95, alpha: 1.0)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save", style: .done, target: self, action: #selector(saveTapped))

        if multiline {
            let tv = UITextView(frame: .zero)
            tv.backgroundColor = .white
            tv.textColor = .black
            tv.text = current
            tv.font = UIFont.systemFont(ofSize: 15)
            tv.autocorrectionType = .no
            view.addSubview(tv)
            textView = tv
            return
        }

        let f = UITextField(frame: .zero)
        f.borderStyle = .none
        f.backgroundColor = .white
        f.textColor = .black
        f.text = current
        f.placeholder = placeholder
        f.clearButtonMode = .whileEditing
        f.autocorrectionType = .no
        f.returnKeyType = .done
        f.delegate = self

        let pad = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        f.leftView = pad
        f.leftViewMode = .always
        f.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        f.rightViewMode = .always
        view.addSubview(f)
        field = f
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        field?.frame = CGRect(x: 0, y: 76, width: view.bounds.width, height: 44)
        textView?.frame = CGRect(x: 0, y: 76, width: view.bounds.width, height: 132)
    }

    @objc private func saveTapped() {
        onSave?(textView?.text ?? field?.text ?? "")
        navigationController?.popViewController(animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        saveTapped()
        return true
    }
}
