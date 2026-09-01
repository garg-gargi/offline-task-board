import Foundation

final class TaskBoardViewModel {
    private let repository: TaskRepository
    private(set) var selectedStatus: TaskStatus = .todo
    private(set) var allTasks: [Task] = []
    var onChange: (() -> Void)?
    var onError: ((Error) -> Void)?

    init(repository: TaskRepository = PersistentTaskRepository()) {
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
        do {
            _ = try repository.create(title: trimmedTitle, description: cleanedDescription(description), status: status)
            reload()
            return true
        } catch {
            report(error)
            return false
        }
    }

    @discardableResult
    func updateTask(id: UUID, title: String, description: String?, status: TaskStatus) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        let didUpdate: Bool
        do {
            didUpdate = try repository.update(id: id, title: trimmedTitle, description: cleanedDescription(description), status: status) != nil
        } catch {
            report(error)
            return false
        }
        if didUpdate { reload() }
        return didUpdate
    }

    func deleteTask(id: UUID) { performMutation { try repository.delete(id: id) } }
    func moveTask(id: UUID, to status: TaskStatus) { performMutation { try repository.move(id: id, to: status) } }
    func reorderTask(id: UUID, to index: Int) { performMutation { try repository.reorder(id: id, to: index) } }

    private func reload() {
        do {
            allTasks = try repository.fetchTasks()
            onChange?()
        } catch {
            report(error)
        }
    }

    private func performMutation(_ mutation: () throws -> Void) {
        do { try mutation(); reload() }
        catch { report(error) }
    }

    private func report(_ error: Error) { onError?(error) }
    private func cleanedDescription(_ description: String?) -> String? {
        guard let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty else { return nil }
        return description
    }
}
