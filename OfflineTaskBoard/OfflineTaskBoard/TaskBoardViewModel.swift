import Foundation

final class TaskBoardViewModel {
    private let repository: TaskRepository
    private(set) var selectedStatus: TaskStatus = .todo
    private(set) var allTasks: [Task] = []
    var onChange: (() -> Void)?

    init(repository: TaskRepository = InMemoryTaskRepository()) {
        self.repository = repository
    }

    var visibleTasks: [Task] { allTasks.filter { $0.status == selectedStatus }.sorted { $0.sortOrder < $1.sortOrder } }
    var defaultNewTaskStatus: TaskStatus { .todo }
    var counts: [TaskStatus: Int] {
        Dictionary(uniqueKeysWithValues: TaskStatus.allCases.map { status in
            (status, allTasks.filter { $0.status == status }.count)
        })
    }

    func loadTasks() { reload() }
    func select(status: TaskStatus) { selectedStatus = status; onChange?() }

    @discardableResult
    func createTask(title: String, description: String?) -> Bool {
        createTask(title: title, description: description, status: defaultNewTaskStatus)
    }

    @discardableResult
    func createTask(title: String, description: String?, status: TaskStatus) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        repository.create(title: trimmedTitle, description: cleanedDescription(description), status: status)
        reload()
        return true
    }

    @discardableResult
    func updateTask(id: UUID, title: String, description: String?, status: TaskStatus) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        let didUpdate = repository.update(id: id, title: trimmedTitle, description: cleanedDescription(description), status: status) != nil
        if didUpdate { reload() }
        return didUpdate
    }

    func deleteTask(id: UUID) { repository.delete(id: id); reload() }
    func moveTask(id: UUID, to status: TaskStatus) { repository.move(id: id, to: status); reload() }
    func reorderTask(id: UUID, to index: Int) { repository.reorder(id: id, to: index); reload() }

    private func reload() { allTasks = repository.fetchTasks(); onChange?() }
    private func cleanedDescription(_ description: String?) -> String? {
        guard let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty else { return nil }
        return description
    }
}
