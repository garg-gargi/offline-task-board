import Foundation

final class TaskBoardViewModel {

    private let repository: TaskRepository
    private let syncManager: SyncManager?

    private(set) var selectedStatus: TaskStatus = .todo
    private(set) var allTasks: [Task] = []

    var onChange: (() -> Void)?
    var onError: ((Error) -> Void)?

    init(repository: TaskRepository = PersistentTaskRepository()) {

        self.repository = repository

        if let persistentRepository = repository as? PersistentTaskRepository {
            self.syncManager = persistentRepository.makeSyncManager()
        } else {
            self.syncManager = nil
        }

        self.syncManager?.onStatusChange = { [weak self] _ in
            self?.reload()
        }
    }

    // MARK: - Derived State

    var visibleTasks: [Task] {
        allTasks
            .filter { $0.status == selectedStatus }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var defaultNewTaskStatus: TaskStatus {
        .todo
    }

    var counts: [TaskStatus: Int] {
        Dictionary(
            uniqueKeysWithValues: TaskStatus.allCases.map { status in
                (
                    status,
                    allTasks.filter { $0.status == status }.count
                )
            }
        )
    }

    var syncStatus: SyncStatus {
        syncManager?.status ?? .idle
    }

    // MARK: - Loading

    func loadTasks() {

        reload()

        syncManager?.sync()
    }

    // MARK: - Selection

    func select(status: TaskStatus) {

        guard selectedStatus != status else {
            return
        }

        selectedStatus = status
        onChange?()
    }

    // MARK: - Create

    @discardableResult
    func createTask(
        title: String,
        description: String?
    ) -> Bool {

        createTask(
            title: title,
            description: description,
            status: defaultNewTaskStatus
        )
    }

    @discardableResult
    func createTask(
        title: String,
        description: String?,
        status: TaskStatus
    ) -> Bool {

        let trimmedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedTitle.isEmpty else {
            return false
        }

        do {

            _ = try repository.create(
                title: trimmedTitle,
                description: cleanedDescription(description),
                status: status
            )

            reload()
            syncManager?.sync()

            return true

        } catch {
            report(error)
            return false
        }
    }

    // MARK: - Update

    @discardableResult
    func updateTask(
        id: UUID,
        title: String,
        description: String?,
        status: TaskStatus
    ) -> Bool {

        let trimmedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedTitle.isEmpty else {
            return false
        }

        do {

            try repository.update(
                id: id,
                title: trimmedTitle,
                description: cleanedDescription(description),
                status: status
            )

            reload()
            syncManager?.sync()

            return true

        } catch {
            report(error)
            return false
        }
    }

    // MARK: - Delete

    func deleteTask(id: UUID) {

        performMutation {
            try repository.delete(id: id)
        }
    }

    // MARK: - Move

    func moveTask(
        id: UUID,
        to status: TaskStatus
    ) {

        performMutation {
            try repository.move(
                id: id,
                to: status
            )
        }
    }

    // MARK: - Reorder

    func reorderTask(
        id: UUID,
        to index: Int
    ) {

        performMutation {
            try repository.reorder(
                id: id,
                to: index
            )
        }
    }

    // MARK: - Sync

    func retrySync() {
        syncManager?.sync()
    }

    // MARK: - Private

    private func reload() {

        do {

            allTasks = try repository.fetchTasks()

            onChange?()

        } catch {
            report(error)
        }
    }

    private func performMutation(
        _ mutation: () throws -> Void
    ) {

        do {

            try mutation()

            reload()
            syncManager?.sync()

        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        onError?(error)
    }

    private func cleanedDescription(
        _ description: String?
    ) -> String? {

        guard let description else {
            return nil
        }

        let trimmed = description.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? nil : trimmed
    }
}
