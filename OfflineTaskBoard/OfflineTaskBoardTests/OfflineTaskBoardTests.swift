import XCTest
@testable import OfflineTaskBoard

final class OfflineTaskBoardTests: XCTestCase {
    func testCreateTaskAddsTaskToSelectedStatus() {
        let viewModel = makeViewModel()
        XCTAssertTrue(viewModel.createTask(title: "Write tests", description: "Cover board behavior", status: .todo))
        viewModel.select(status: .todo)
        XCTAssertEqual(viewModel.visibleTasks.map(\.title), ["Write tests"])
    }

    func testNewTaskDefaultsToToDoRegardlessOfSelectedBoardStatus() {
        let viewModel = makeViewModel()
        viewModel.select(status: .done)
        XCTAssertTrue(viewModel.createTask(title: "Starts in To Do", description: nil))
        viewModel.select(status: .todo)
        XCTAssertEqual(viewModel.visibleTasks.map(\.title), ["Starts in To Do"])
    }

    func testUpdateTaskChangesContentAndStatus() {
        let task = makeTask(title: "Draft")
        let viewModel = makeViewModel(tasks: [task])
        XCTAssertTrue(viewModel.updateTask(id: task.id, title: "Published draft", description: "Ready", status: .done))
        viewModel.select(status: .done)
        XCTAssertEqual(viewModel.visibleTasks.first?.title, "Published draft")
        XCTAssertEqual(viewModel.visibleTasks.first?.description, "Ready")
    }

    func testDeleteTaskRemovesIt() {
        let task = makeTask(title: "Remove me")
        let viewModel = makeViewModel(tasks: [task])
        viewModel.deleteTask(id: task.id)
        XCTAssertTrue(viewModel.visibleTasks.isEmpty)
    }

    func testMoveTaskChangesStatusAndAppendsToDestination() {
        let todo = makeTask(title: "To do", status: .todo, sortOrder: 0)
        let progress = makeTask(title: "In progress", status: .inProgress, sortOrder: 0)
        let viewModel = makeViewModel(tasks: [todo, progress])
        viewModel.moveTask(id: todo.id, to: .inProgress)
        viewModel.select(status: .inProgress)
        XCTAssertEqual(viewModel.visibleTasks.map(\.title), ["In progress", "To do"])
    }

    func testReorderTaskUpdatesSortOrder() {
        let first = makeTask(title: "First", sortOrder: 0)
        let second = makeTask(title: "Second", sortOrder: 1)
        let third = makeTask(title: "Third", sortOrder: 2)
        let viewModel = makeViewModel(tasks: [first, second, third])
        viewModel.reorderTask(id: third.id, to: 0)
        XCTAssertEqual(viewModel.visibleTasks.map(\.title), ["Third", "First", "Second"])
    }

    func testEmptyTitleIsRejected() {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.createTask(title: "  ", description: nil, status: .todo))
        XCTAssertTrue(viewModel.visibleTasks.isEmpty)
    }

    func testCoreDataTasksPersistAfterSaveAndFetch() throws {
        let stack = try CoreDataStack(inMemory: true)
        let source = CoreDataLocalDataSource(stack: stack)
        let created = try source.create(title: "Persist me", description: "Stored locally", status: .todo)
        let reloadedSource = CoreDataLocalDataSource(stack: stack)
        XCTAssertEqual(try reloadedSource.fetchTasks().first?.id, created.id)
    }

    func testCreateCreatesCreateOutboxOperation() throws {
        let source = try makeLocalDataSource()
        let task = try source.create(title: "New", description: nil, status: .todo)
        let operation = try XCTUnwrap(source.fetchPendingOperations().first)
        XCTAssertEqual(operation.taskId, task.id)
        XCTAssertEqual(operation.type, .create)
        XCTAssertEqual(try operation.decodedTask()?.title, "New")
    }

    func testCreateThenUpdatesCoalesceToOneCreateWithLatestPayload() throws {
        let source = try makeLocalDataSource()
        let task = try source.create(title: "Original", description: nil, status: .todo)
        _ = try source.update(id: task.id, title: "Latest", description: "Final", status: .done)
        let operations = try source.fetchPendingOperations()
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.type, .create)
        XCTAssertEqual(try operations.first?.decodedTask()?.title, "Latest")
    }

    func testUpdateThenUpdatesCoalesceToOneUpdate() throws {
        let source = try makeSeededLocalDataSource()
        let task = try XCTUnwrap(source.fetchTasks().first)
        _ = try source.update(id: task.id, title: "First update", description: nil, status: .todo)
        _ = try source.update(id: task.id, title: "Second update", description: nil, status: .todo)
        let operations = try source.fetchPendingOperations()
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.type, .update)
        XCTAssertEqual(try operations.first?.decodedTask()?.title, "Second update")
    }

    func testUpdateThenDeleteCoalescesToDelete() throws {
        let source = try makeSeededLocalDataSource()
        let task = try XCTUnwrap(source.fetchTasks().first)
        _ = try source.update(id: task.id, title: "Changed", description: nil, status: .todo)
        try source.delete(id: task.id)
        let operation = try XCTUnwrap(source.fetchPendingOperations().first)
        XCTAssertEqual(operation.type, .delete)
        XCTAssertNil(operation.payload)
    }

    func testCreateThenDeleteRemovesOutboxOperation() throws {
        let source = try makeLocalDataSource()
        let task = try source.create(title: "Temporary", description: nil, status: .todo)
        try source.delete(id: task.id)
        XCTAssertTrue(try source.fetchTasks().isEmpty)
        XCTAssertTrue(try source.fetchPendingOperations().isEmpty)
    }

    func testDeleteNormalizesRemainingTasksAndQueuesTheirUpdates() throws {
        let first = makeTask(title: "First", sortOrder: 0)
        let second = makeTask(title: "Second", sortOrder: 1)
        let third = makeTask(title: "Third", sortOrder: 2)
        let source = try makeLocalDataSource(tasks: [first, second, third])

        try source.delete(id: first.id)

        let remaining = try source.fetchTasks().filter { $0.status == .todo }
        XCTAssertEqual(remaining.map(\.id), [second.id, third.id])
        XCTAssertEqual(remaining.map(\.sortOrder), [0, 1])

        let operations = try source.fetchPendingOperations()
        XCTAssertEqual(operations.first(where: { $0.taskId == first.id })?.type, .delete)
        XCTAssertEqual(operations.first(where: { $0.taskId == second.id })?.type, .update)
        XCTAssertEqual(operations.first(where: { $0.taskId == third.id })?.type, .update)
    }

    func testMoveAndReorderPersistLatestTaskState() throws {
        let source = try makeSeededLocalDataSource()
        let tasks = try source.fetchTasks()
        let first = tasks[0]
        let second = tasks[1]
        try source.move(id: first.id, to: .done)
        try source.reorder(id: second.id, to: 0)
        let persisted = try source.fetchTasks()
        XCTAssertEqual(persisted.first(where: { $0.id == first.id })?.status, .done)
        XCTAssertEqual(persisted.first(where: { $0.id == second.id })?.sortOrder, 0)
        XCTAssertFalse(try source.fetchPendingOperations().isEmpty)
    }

    private func makeViewModel(tasks: [Task] = []) -> TaskBoardViewModel {
        let repository = InMemoryTaskRepository(tasks: tasks, now: { Date(timeIntervalSince1970: 42) })
        let viewModel = TaskBoardViewModel(repository: repository)
        viewModel.loadTasks()
        return viewModel
    }

    private func makeLocalDataSource() throws -> CoreDataLocalDataSource {
        CoreDataLocalDataSource(stack: try CoreDataStack(inMemory: true), now: { Date(timeIntervalSince1970: 42) })
    }

    private func makeLocalDataSource(tasks: [Task]) throws -> CoreDataLocalDataSource {
        let source = try makeLocalDataSource()
        try source.seed(tasks: tasks)
        return source
    }

    private func makeSeededLocalDataSource() throws -> CoreDataLocalDataSource {
        let source = try makeLocalDataSource()
        try source.seed(tasks: [makeTask(title: "First", sortOrder: 0), makeTask(title: "Second", sortOrder: 1)])
        return source
    }

    private func makeTask(title: String, status: TaskStatus = .todo, sortOrder: Double = 0) -> Task {
        Task(id: UUID(), title: title, description: nil, status: status, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0), sortOrder: sortOrder, serverVersion: 0)
    }
}
