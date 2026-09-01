import Foundation

enum TaskStatus: String, CaseIterable, Equatable {
    case todo
    case inProgress
    case done

    var title: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }
}

struct Task: Identifiable, Equatable {
    let id: UUID
    var title: String
    var description: String?
    var status: TaskStatus
    let createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    var serverVersion: Int
}
