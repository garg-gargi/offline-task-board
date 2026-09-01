import UIKit

final class TaskFormViewController: UIViewController {
    private let task: Task?
    private let defaultStatus: TaskStatus
    var onSave: ((String, String?, TaskStatus) -> Bool)?

    private let titleField = UITextField()
    private let descriptionView = UITextView()
    private let statusControl = UISegmentedControl(items: TaskStatus.allCases.map(\.title))
    private let errorLabel = UILabel()

    init(task: Task?, defaultStatus: TaskStatus) {
        self.task = task
        self.defaultStatus = defaultStatus
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = task == nil ? "New Task" : "Edit Task"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        configureFields()
    }

    private func configureFields() {
        let titleLabel = label("Title")
        titleField.borderStyle = .roundedRect
        titleField.placeholder = "Task title"
        titleField.text = task?.title
        titleField.autocapitalizationType = .sentences
        titleField.returnKeyType = .done
        titleField.delegate = self

        let descriptionLabel = label("Description")
        descriptionView.text = task?.description
        descriptionView.font = .preferredFont(forTextStyle: .body)
        descriptionView.layer.borderColor = UIColor.separator.cgColor
        descriptionView.layer.borderWidth = 1
        descriptionView.layer.cornerRadius = 8
        descriptionView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        descriptionView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let statusLabel = label("Status")
        statusControl.selectedSegmentIndex = TaskStatus.allCases.firstIndex(of: task?.status ?? defaultStatus) ?? 0

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, titleField, descriptionLabel, descriptionView, statusLabel, statusControl, errorLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(22, after: titleField)
        stack.setCustomSpacing(22, after: descriptionView)
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
    }

    private func label(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func save() {
        let status = TaskStatus.allCases[statusControl.selectedSegmentIndex]
        guard onSave?(titleField.text ?? "", descriptionView.text, status) == true else {
            errorLabel.text = "A task title is required."
            errorLabel.isHidden = false
            return
        }
        dismiss(animated: true)
    }
}

extension TaskFormViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        save()
        return true
    }
}
