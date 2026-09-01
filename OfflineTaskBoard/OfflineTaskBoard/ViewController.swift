//
//  ViewController.swift
//  OfflineTaskBoard
//
//  Created by Gargi Garg on 01/09/26.
//

import UIKit

final class ViewController: UIViewController {

    private let viewModel: TaskBoardViewModel

    private let statusControl = UISegmentedControl(
        items: TaskStatus.allCases.map(\.title)
    )

    private let dragTargetHighlight = UIView()
    private let collectionView: UICollectionView
    private let syncLabel = UILabel()

    private var dragSnapshot: UIView?
    private var draggedTask: Task?

    init(viewModel: TaskBoardViewModel = TaskBoardViewModel()) {
        self.viewModel = viewModel

        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.backgroundColor = .clear

        configuration.trailingSwipeActionsConfigurationProvider = { indexPath in
            guard indexPath.section == 0,
                  indexPath.item < viewModel.visibleTasks.count else {
                return nil
            }

            let taskID = viewModel.visibleTasks[indexPath.item].id

            let deleteAction = UIContextualAction(
                style: .destructive,
                title: "Delete"
            ) { _, _, completion in
                viewModel.deleteTask(id: taskID)
                completion(true)
            }

            return UISwipeActionsConfiguration(actions: [deleteAction])
        }

        let layout = UICollectionViewCompositionalLayout { _, environment in
            let section = NSCollectionLayoutSection.list(
                using: configuration,
                layoutEnvironment: environment
            )

            section.contentInsets = NSDirectionalEdgeInsets(
                top: 16,
                leading: 20,
                bottom: 16,
                trailing: 20
            )

            section.interGroupSpacing = 10

            return section
        }

        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureView()

        viewModel.onChange = { [weak self] in
            self?.render()
        }

        viewModel.onError = { [weak self] error in
            self?.presentPersistenceError(error)
        }

        viewModel.loadTasks()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "Tasks"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)

        let addButton = UIButton(type: .system)
        addButton.setImage(
            UIImage(systemName: "plus.circle.fill"),
            for: .normal
        )
        addButton.accessibilityLabel = "Create task"
        addButton.addTarget(
            self,
            action: #selector(createTask),
            for: .touchUpInside
        )

        let header = UIStackView(
            arrangedSubviews: [titleLabel, UIView(), addButton]
        )
        header.alignment = .center

        statusControl.selectedSegmentIndex = 0
        statusControl.addTarget(
            self,
            action: #selector(statusChanged),
            for: .valueChanged
        )
        statusControl.accessibilityLabel = "Task status"

        dragTargetHighlight.backgroundColor =
            .systemBlue.withAlphaComponent(0.18)
        dragTargetHighlight.layer.cornerRadius = 5
        dragTargetHighlight.isHidden = true
        statusControl.insertSubview(dragTargetHighlight, at: 0)

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            TaskCell.self,
            forCellWithReuseIdentifier: TaskCell.reuseIdentifier
        )

        let longPressGesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        )
        collectionView.addGestureRecognizer(longPressGesture)

        syncLabel.text = "✓ All changes synced"
        syncLabel.textColor = .secondaryLabel
        syncLabel.font = .preferredFont(forTextStyle: .footnote)
        syncLabel.textAlignment = .center

        [header, statusControl, collectionView, syncLabel].forEach {
            view.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 12
            ),
            header.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            header.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            ),

            statusControl.topAnchor.constraint(
                equalTo: header.bottomAnchor,
                constant: 16
            ),
            statusControl.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            statusControl.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            ),

            collectionView.topAnchor.constraint(
                equalTo: statusControl.bottomAnchor,
                constant: 2
            ),
            collectionView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            collectionView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            collectionView.bottomAnchor.constraint(
                equalTo: syncLabel.topAnchor,
                constant: -4
            ),

            syncLabel.leadingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.leadingAnchor
            ),
            syncLabel.trailingAnchor.constraint(
                equalTo: view.layoutMarginsGuide.trailingAnchor
            ),
            syncLabel.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -8
            )
        ])
    }

    private func render() {
        let counts = viewModel.counts

        for (index, status) in TaskStatus.allCases.enumerated() {
            statusControl.setTitle(
                "\(status.title) \(counts[status, default: 0])",
                forSegmentAt: index
            )
        }

        statusControl.selectedSegmentIndex =
            TaskStatus.allCases.firstIndex(of: viewModel.selectedStatus) ?? 0

        switch viewModel.syncStatus {
        case .idle:
            syncLabel.text = ""

        case .syncing:
            syncLabel.text = "Syncing…"

        case .changesPending:
            syncLabel.text = "Changes pending"

        case .synced:
            syncLabel.text = "✓ All changes synced"

        case .failed:
            syncLabel.text = "Sync failed • Tap to retry"
        }

        collectionView.reloadData()
    }

    private func presentPersistenceError(_ error: Error) {
        let alert = UIAlertController(
            title: "Could Not Save Changes",
            message: error.localizedDescription,
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(title: "OK", style: .default)
        )

        present(alert, animated: true)
    }

    @objc
    private func statusChanged() {
        viewModel.select(
            status: TaskStatus.allCases[statusControl.selectedSegmentIndex]
        )
    }

    @objc
    private func createTask() {
        presentForm(task: nil)
    }

    private func presentForm(task: Task?) {
        let form = TaskFormViewController(
            task: task,
            defaultStatus: task?.status ?? viewModel.defaultNewTaskStatus
        )

        form.onSave = { [weak self] title, description, status in
            guard let self else {
                return false
            }

            if let task {
                return self.viewModel.updateTask(
                    id: task.id,
                    title: title,
                    description: description,
                    status: status
                )
            }

            return self.viewModel.createTask(
                title: title,
                description: description,
                status: status
            )
        }

        present(
            UINavigationController(rootViewController: form),
            animated: true
        )
    }

    @objc
    private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: view)

        switch recognizer.state {
        case .began:
            beginDrag(at: location)

        case .changed:
            updateDrag(at: location)

        case .ended:
            finishDrag(at: location)

        default:
            cancelDrag()
        }
    }

    private func beginDrag(at location: CGPoint) {
        let listPoint = view.convert(location, to: collectionView)

        guard
            let indexPath = collectionView.indexPathForItem(at: listPoint),
            let cell = collectionView.cellForItem(at: indexPath),
            indexPath.item < viewModel.visibleTasks.count
        else {
            return
        }

        draggedTask = viewModel.visibleTasks[indexPath.item]

        let snapshot = cell.snapshotView(afterScreenUpdates: false)
            ?? UIView(frame: cell.bounds)

        snapshot.frame = cell.convert(cell.bounds, to: view)
        snapshot.layer.shadowColor = UIColor.black.cgColor
        snapshot.layer.shadowOpacity = 0.22
        snapshot.layer.shadowRadius = 8
        snapshot.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)

        view.addSubview(snapshot)
        dragSnapshot = snapshot

        cell.alpha = 0.25

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func updateDrag(at location: CGPoint) {
        dragSnapshot?.center = location
        updateSegmentHighlight(at: location)
    }

    private func finishDrag(at location: CGPoint) {
        guard let task = draggedTask else {
            cancelDrag()
            return
        }

        if let targetStatus = status(at: location) {
            if targetStatus != task.status {
                viewModel.moveTask(id: task.id, to: targetStatus)
                viewModel.select(status: targetStatus)
            }
        } else {
            let listPoint = view.convert(location, to: collectionView)

            if collectionView.bounds.contains(listPoint),
               let destination = nearestIndex(to: listPoint) {
                viewModel.reorderTask(
                    id: task.id,
                    to: destination
                )
            }
        }

        cancelDrag()
    }

    private func cancelDrag() {
        dragSnapshot?.removeFromSuperview()
        dragSnapshot = nil
        draggedTask = nil
        dragTargetHighlight.isHidden = true

        collectionView.visibleCells.forEach {
            $0.alpha = 1
        }
    }

    private func status(at location: CGPoint) -> TaskStatus? {
        let point = view.convert(location, to: statusControl)

        guard statusControl.bounds.contains(point) else {
            return nil
        }

        let segmentWidth =
            statusControl.bounds.width /
            CGFloat(TaskStatus.allCases.count)

        let index = min(
            Int(point.x / segmentWidth),
            TaskStatus.allCases.count - 1
        )

        return TaskStatus.allCases[index]
    }

    private func updateSegmentHighlight(at location: CGPoint) {
        guard
            let status = status(at: location),
            let index = TaskStatus.allCases.firstIndex(of: status)
        else {
            dragTargetHighlight.isHidden = true
            return
        }

        let segmentWidth =
            statusControl.bounds.width /
            CGFloat(TaskStatus.allCases.count)

        dragTargetHighlight.frame = CGRect(
            x: segmentWidth * CGFloat(index) + 2,
            y: 2,
            width: segmentWidth - 4,
            height: statusControl.bounds.height - 4
        )

        dragTargetHighlight.isHidden = false
    }

    private func nearestIndex(to point: CGPoint) -> Int? {
        let visible = collectionView.indexPathsForVisibleItems

        guard !visible.isEmpty else {
            return viewModel.visibleTasks.isEmpty ? nil : 0
        }

        return visible.min { lhs, rhs in
            let left = abs(
                (collectionView.layoutAttributesForItem(at: lhs)?.center.y ?? 0)
                    - point.y
            )

            let right = abs(
                (collectionView.layoutAttributesForItem(at: rhs)?.center.y ?? 0)
                    - point.y
            )

            return left < right
        }?.item
    }
}

// MARK: - UICollectionViewDataSource & Delegate

extension ViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        viewModel.visibleTasks.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: TaskCell.reuseIdentifier,
            for: indexPath
        ) as! TaskCell

        cell.configure(with: viewModel.visibleTasks[indexPath.item])

        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        presentForm(task: viewModel.visibleTasks[indexPath.item])
    }
}

// MARK: - Task Cell

private final class TaskCell: UICollectionViewCell {

    static let reuseIdentifier = "TaskCell"

    private let handle = UIImageView(
        image: UIImage(systemName: "line.3.horizontal")
    )

    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 12
        contentView.layoutMargins = UIEdgeInsets(
            top: 14,
            left: 14,
            bottom: 14,
            right: 14
        )

        handle.tintColor = .tertiaryLabel
        handle.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0

        descriptionLabel.font = .preferredFont(forTextStyle: .subheadline)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0

        let textStack = UIStackView(
            arrangedSubviews: [titleLabel, descriptionLabel]
        )
        textStack.axis = .vertical
        textStack.spacing = 4

        let row = UIStackView(
            arrangedSubviews: [handle, textStack]
        )
        row.alignment = .top
        row.spacing = 12

        contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.leadingAnchor
            ),
            row.trailingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.trailingAnchor
            ),
            row.topAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.topAnchor
            ),
            row.bottomAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.bottomAnchor
            )
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with task: Task) {
        titleLabel.text = task.title
        descriptionLabel.text = task.description
        descriptionLabel.isHidden = task.description == nil

        accessibilityLabel = [
            task.title,
            task.description
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
