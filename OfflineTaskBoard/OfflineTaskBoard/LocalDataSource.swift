import CoreData
import Foundation

enum PendingOperationType: String, Codable {
    case create
    case update
    case delete
}

struct PendingOperation: Equatable {
    let id: UUID
    let taskId: UUID
    let type: PendingOperationType
    let payload: Data?
    let baseVersion: Int64
    let createdAt: Date
    let retryCount: Int32

    func decodedTask() throws -> Task? {
        guard let payload else { return nil }
        return try JSONDecoder().decode(TaskPayload.self, from: payload).task
    }
}

enum LocalDataSourceError: Error {
    case taskNotFound
    case invalidStoredStatus(String)
    case invalidStoredOperation(String)
}

protocol LocalDataSource: AnyObject {
    func fetchTasks() throws -> [Task]
    func create(title: String, description: String?, status: TaskStatus) throws -> Task
    func update(id: UUID, title: String, description: String?, status: TaskStatus) throws -> Task?
    func delete(id: UUID) throws
    func move(id: UUID, to status: TaskStatus) throws
    func reorder(id: UUID, to index: Int) throws
}

final class CoreDataLocalDataSource: LocalDataSource {
    private let stack: CoreDataStack
    private let now: () -> Date

    init(stack: CoreDataStack, now: @escaping () -> Date = Date.init) {
        self.stack = stack
        self.now = now
    }

    func fetchTasks() throws -> [Task] {
        try perform { context in
            try self.fetchTaskEntities(in: context).map(self.task(from:))
        }
    }

    func fetchPendingOperations() throws -> [PendingOperation] {
        try perform { context in
            let request = NSFetchRequest<PendingOperationEntity>(entityName: "PendingOperationEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(request).map { entity in
                guard let type = PendingOperationType(rawValue: entity.operationType) else {
                    throw LocalDataSourceError.invalidStoredOperation(entity.operationType)
                }
                return PendingOperation(id: entity.id, taskId: entity.taskId, type: type, payload: entity.payload, baseVersion: entity.baseVersion, createdAt: entity.createdAt, retryCount: entity.retryCount)
            }
        }
    }

    func seed(tasks: [Task]) throws {
        try performMutation { context in
            guard try self.fetchTaskEntities(in: context).isEmpty else { return }
            for task in tasks { _ = self.insert(task, in: context) }
        }
    }

    func create(title: String, description: String?, status: TaskStatus) throws -> Task {
        try performMutation { context in
            let timestamp = self.now()
            let task = Task(id: UUID(), title: title, description: description, status: status, createdAt: timestamp, updatedAt: timestamp, sortOrder: Double(try self.taskEntities(status: status, in: context).count), serverVersion: 0)
            let entity = self.insert(task, in: context)
            try self.coalesce(.create, for: entity, in: context)
            return task
        }
    }

    func update(id: UUID, title: String, description: String?, status: TaskStatus) throws -> Task? {
        try performMutation { context in
            guard let entity = try self.taskEntity(id: id, in: context) else { return nil }
            let previousStatus = try self.status(of: entity)
            entity.title = title
            entity.taskDescription = description
            entity.updatedAt = self.now()
            var changed = [entity]
            if previousStatus != status {
                entity.status = status.rawValue
                entity.sortOrder = Double(try self.taskEntities(status: status, in: context).filter { $0.id != id }.count)
                changed += try self.normalize(status: previousStatus, in: context)
                changed += try self.normalize(status: status, in: context)
            }
            try self.coalesceUpdates(for: changed, in: context)
            return try self.task(from: entity)
        }
    }

    func delete(id: UUID) throws {
        try performMutation { context in
            guard let entity = try self.taskEntity(id: id, in: context) else { return }
            let task = try self.task(from: entity)
            context.delete(entity)
            try self.coalesceDelete(for: task, in: context)
            let reorderedTasks = try self.normalize(status: task.status, in: context)
            try self.coalesceUpdates(for: reorderedTasks, in: context)
        }
    }

    func move(id: UUID, to status: TaskStatus) throws {
        try performMutation { context in
            guard let entity = try self.taskEntity(id: id, in: context) else { return }
            let previousStatus = try self.status(of: entity)
            guard previousStatus != status else { return }
            entity.status = status.rawValue
            entity.sortOrder = Double(try self.taskEntities(status: status, in: context).filter { $0.id != id }.count)
            entity.updatedAt = self.now()
            var changed = [entity]
            changed += try self.normalize(status: previousStatus, in: context)
            changed += try self.normalize(status: status, in: context)
            try self.coalesceUpdates(for: changed, in: context)
        }
    }

    func reorder(id: UUID, to index: Int) throws {
        try performMutation { context in
            guard let entity = try self.taskEntity(id: id, in: context) else { return }
            let status = try self.status(of: entity)
            var tasks = try self.taskEntities(status: status, in: context)
            guard let current = tasks.firstIndex(where: { $0.id == id }) else { throw LocalDataSourceError.taskNotFound }
            let dragged = tasks.remove(at: current)
            tasks.insert(dragged, at: min(max(index, 0), tasks.count))
            var changed: [TaskEntity] = []
            for (order, task) in tasks.enumerated() where task.sortOrder != Double(order) {
                task.sortOrder = Double(order)
                if task.id == id { task.updatedAt = self.now() }
                changed.append(task)
            }
            try self.coalesceUpdates(for: changed, in: context)
        }
    }

    private func perform<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) throws -> T {
        let context = stack.makeBackgroundContext()
        var result: Result<T, Error>!
        context.performAndWait { result = Result { try block(context) } }
        return try result.get()
    }

    private func performMutation<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) throws -> T {
        try perform { context in
            do {
                let value = try block(context)
                if context.hasChanges { try context.save() }
                return value
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func fetchTaskEntities(in context: NSManagedObjectContext) throws -> [TaskEntity] {
        let request = NSFetchRequest<TaskEntity>(entityName: "TaskEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "status", ascending: true), NSSortDescriptor(key: "sortOrder", ascending: true)]
        return try context.fetch(request)
    }

    private func taskEntities(status: TaskStatus, in context: NSManagedObjectContext) throws -> [TaskEntity] {
        let request = NSFetchRequest<TaskEntity>(entityName: "TaskEntity")
        request.predicate = NSPredicate(format: "status == %@", status.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return try context.fetch(request)
    }

    private func taskEntity(id: UUID, in context: NSManagedObjectContext) throws -> TaskEntity? {
        let request = NSFetchRequest<TaskEntity>(entityName: "TaskEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private func insert(_ task: Task, in context: NSManagedObjectContext) -> TaskEntity {
        let entity = TaskEntity(entity: NSEntityDescription.entity(forEntityName: "TaskEntity", in: context)!, insertInto: context)
        entity.id = task.id
        entity.title = task.title
        entity.taskDescription = task.description
        entity.status = task.status.rawValue
        entity.createdAt = task.createdAt
        entity.updatedAt = task.updatedAt
        entity.sortOrder = task.sortOrder
        entity.serverVersion = task.serverVersion
        return entity
    }

    private func task(from entity: TaskEntity) throws -> Task {
        guard let status = TaskStatus(rawValue: entity.status) else { throw LocalDataSourceError.invalidStoredStatus(entity.status) }
        return Task(id: entity.id, title: entity.title, description: entity.taskDescription, status: status, createdAt: entity.createdAt, updatedAt: entity.updatedAt, sortOrder: entity.sortOrder, serverVersion: entity.serverVersion)
    }

    private func status(of entity: TaskEntity) throws -> TaskStatus {
        guard let status = TaskStatus(rawValue: entity.status) else { throw LocalDataSourceError.invalidStoredStatus(entity.status) }
        return status
    }

    private func normalize(status: TaskStatus, in context: NSManagedObjectContext) throws -> [TaskEntity] {
        var changed: [TaskEntity] = []
        for (order, task) in try taskEntities(status: status, in: context).enumerated() where task.sortOrder != Double(order) {
            task.sortOrder = Double(order)
            changed.append(task)
        }
        return changed
    }

    private func coalesceUpdates(for entities: [TaskEntity], in context: NSManagedObjectContext) throws {
        var seen = Set<UUID>()
        for entity in entities where seen.insert(entity.id).inserted {
            try coalesce(.update, for: entity, in: context)
        }
    }

    private func coalesce(_ requestedType: PendingOperationType, for task: TaskEntity, in context: NSManagedObjectContext) throws {
        let existing = try pendingOperation(taskId: task.id, in: context)
        let operation: PendingOperationEntity
        if let existing {
            operation = existing
        } else {
            operation = PendingOperationEntity(entity: NSEntityDescription.entity(forEntityName: "PendingOperationEntity", in: context)!, insertInto: context)
            operation.id = UUID()
            operation.taskId = task.id
            operation.createdAt = now()
            operation.retryCount = 0
            operation.baseVersion = task.serverVersion
        }
        let existingType = PendingOperationType(rawValue: operation.operationType)
        operation.operationType = (existingType == .create ? PendingOperationType.create : requestedType).rawValue
        operation.payload = try TaskPayload(task: try self.task(from: task)).encoded()
    }

    private func coalesceDelete(for task: Task, in context: NSManagedObjectContext) throws {
        if let existing = try pendingOperation(taskId: task.id, in: context), PendingOperationType(rawValue: existing.operationType) == .create {
            context.delete(existing)
            return
        }
        let operation = try pendingOperation(taskId: task.id, in: context) ?? PendingOperationEntity(entity: NSEntityDescription.entity(forEntityName: "PendingOperationEntity", in: context)!, insertInto: context)
        if operation.isInserted {
            operation.id = UUID()
            operation.taskId = task.id
            operation.createdAt = now()
            operation.retryCount = 0
        }
        operation.operationType = PendingOperationType.delete.rawValue
        operation.payload = nil
        operation.baseVersion = task.serverVersion
    }

    private func pendingOperation(taskId: UUID, in context: NSManagedObjectContext) throws -> PendingOperationEntity? {
        let request = NSFetchRequest<PendingOperationEntity>(entityName: "PendingOperationEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "taskId == %@", taskId as CVarArg)
        return try context.fetch(request).first
    }
}

struct TaskPayload: Codable {
    let id: UUID
    let title: String
    let description: String?
    let status: String
    let createdAt: Date
    let updatedAt: Date
    let sortOrder: Double
    let serverVersion: Int64

    init(task: Task) {
        id = task.id; title = task.title; description = task.description; status = task.status.rawValue
        createdAt = task.createdAt; updatedAt = task.updatedAt; sortOrder = task.sortOrder; serverVersion = task.serverVersion
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    var task: Task {
        Task(id: id, title: title, description: description, status: TaskStatus(rawValue: status)!, createdAt: createdAt, updatedAt: updatedAt, sortOrder: sortOrder, serverVersion: serverVersion)
    }
}
