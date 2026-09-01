import Foundation

protocol TaskRepository: AnyObject {
    func fetchTasks() -> [Task]
    @discardableResult func create(title: String, description: String?, status: TaskStatus) -> Task
    @discardableResult func update(id: UUID, title: String, description: String?, status: TaskStatus) -> Task?
    func delete(id: UUID)
    func move(id: UUID, to status: TaskStatus)
    func reorder(id: UUID, to index: Int)
}

final class InMemoryTaskRepository: TaskRepository {
    private var storedTasks: [Task]
    private let now: () -> Date

    init(tasks: [Task] = SampleTasks.all, now: @escaping () -> Date = Date.init) {
        self.storedTasks = tasks
        self.now = now
        normalizeAllSortOrders()
    }

    func fetchTasks() -> [Task] {
        storedTasks.sorted { lhs, rhs in
            lhs.status == rhs.status ? lhs.sortOrder < rhs.sortOrder : lhs.status.rawValue < rhs.status.rawValue
        }
    }

    func create(title: String, description: String?, status: TaskStatus) -> Task {
        let timestamp = now()
        let task = Task(
            id: UUID(), title: title, description: description, status: status,
            createdAt: timestamp, updatedAt: timestamp,
            sortOrder: tasks(in: status).count, serverVersion: 0
        )
        storedTasks.append(task)
        return task
    }

    func update(id: UUID, title: String, description: String?, status: TaskStatus) -> Task? {
        guard let index = storedTasks.firstIndex(where: { $0.id == id }) else { return nil }
        let originalStatus = storedTasks[index].status
        storedTasks[index].title = title
        storedTasks[index].description = description
        storedTasks[index].updatedAt = now()
        if originalStatus != status {
            storedTasks[index].status = status
            storedTasks[index].sortOrder = tasks(in: status).count - 1
            normalizeSortOrders(for: originalStatus)
            normalizeSortOrders(for: status)
        }
        return storedTasks[index]
    }

    func delete(id: UUID) {
        guard let index = storedTasks.firstIndex(where: { $0.id == id }) else { return }
        let status = storedTasks[index].status
        storedTasks.remove(at: index)
        normalizeSortOrders(for: status)
    }

    func move(id: UUID, to status: TaskStatus) {
        guard let index = storedTasks.firstIndex(where: { $0.id == id }) else { return }
        let previousStatus = storedTasks[index].status
        guard previousStatus != status else { return }
        storedTasks[index].status = status
        storedTasks[index].sortOrder = tasks(in: status).count - 1
        storedTasks[index].updatedAt = now()
        normalizeSortOrders(for: previousStatus)
        normalizeSortOrders(for: status)
    }

    func reorder(id: UUID, to index: Int) {
        guard let sourceIndex = storedTasks.firstIndex(where: { $0.id == id }) else { return }
        let status = storedTasks[sourceIndex].status
        var section = tasks(in: status)
        guard let currentIndex = section.firstIndex(where: { $0.id == id }) else { return }
        let task = section.remove(at: currentIndex)
        section.insert(task, at: min(max(index, 0), section.count))
        for (sortOrder, task) in section.enumerated() {
            guard let storedIndex = storedTasks.firstIndex(where: { $0.id == task.id }) else { continue }
            storedTasks[storedIndex].sortOrder = sortOrder
            if task.id == id { storedTasks[storedIndex].updatedAt = now() }
        }
    }

    private func tasks(in status: TaskStatus) -> [Task] {
        storedTasks.filter { $0.status == status }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func normalizeAllSortOrders() {
        TaskStatus.allCases.forEach(normalizeSortOrders)
    }

    private func normalizeSortOrders(for status: TaskStatus) {
        for (sortOrder, task) in tasks(in: status).enumerated() {
            guard let index = storedTasks.firstIndex(where: { $0.id == task.id }) else { continue }
            storedTasks[index].sortOrder = sortOrder
        }
    }
}

enum SampleTasks {
    static let all: [Task] = [
        task("00000000-0000-0000-0000-000000000001", "Fix login bug", "Authentication timeout on slower connections", .todo, 0),
        task("00000000-0000-0000-0000-000000000002", "Update documentation", "Add API setup notes for new developers", .todo, 1),
        task("00000000-0000-0000-0000-000000000003", "Investigate API issue", nil, .todo, 2),
        task("00000000-0000-0000-0000-000000000004", "Review accessibility labels", "Check VoiceOver navigation in account settings", .todo, 3),
        task("00000000-0000-0000-0000-000000000005", "Refine onboarding", "Align copy with the latest product brief", .inProgress, 0),
        task("00000000-0000-0000-0000-000000000006", "Prepare release notes", "Draft highlights for version 1.0", .inProgress, 1),
        task("00000000-0000-0000-0000-000000000007", "Set up project", "Create the initial UIKit app shell", .done, 0),
        task("00000000-0000-0000-0000-000000000008", "Confirm requirements", nil, .done, 1)
    ]

    private static func task(_ id: String, _ title: String, _ description: String?, _ status: TaskStatus, _ sortOrder: Int) -> Task {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return Task(id: UUID(uuidString: id)!, title: title, description: description, status: status, createdAt: date, updatedAt: date, sortOrder: sortOrder, serverVersion: 0)
    }
}
