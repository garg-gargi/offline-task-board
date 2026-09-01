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

    private func makeViewModel(tasks: [Task] = []) -> TaskBoardViewModel {
        let repository = InMemoryTaskRepository(tasks: tasks, now: { Date(timeIntervalSince1970: 42) })
        let viewModel = TaskBoardViewModel(repository: repository)
        viewModel.loadTasks()
        return viewModel
    }

    private func makeTask(title: String, status: TaskStatus = .todo, sortOrder: Int = 0) -> Task {
        Task(id: UUID(), title: title, description: nil, status: status, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0), sortOrder: sortOrder, serverVersion: 0)
    }
}
