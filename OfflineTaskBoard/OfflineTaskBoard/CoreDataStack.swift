import CoreData

final class CoreDataStack {
    let persistentContainer: NSPersistentContainer

    init(inMemory: Bool = false) throws {
        persistentContainer = NSPersistentContainer(name: "OfflineTaskBoard", managedObjectModel: Self.managedObjectModel)
        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            persistentContainer.persistentStoreDescriptions = [description]
        }

        var loadError: Error?
        persistentContainer.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func makeBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    private static let managedObjectModel: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        let task = NSEntityDescription()
        task.name = "TaskEntity"
        task.managedObjectClassName = NSStringFromClass(TaskEntity.self)
        task.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("taskDescription", .stringAttributeType, optional: true),
            attribute("status", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("sortOrder", .doubleAttributeType),
            attribute("serverVersion", .integer64AttributeType)
        ]

        let operation = NSEntityDescription()
        operation.name = "PendingOperationEntity"
        operation.managedObjectClassName = NSStringFromClass(PendingOperationEntity.self)
        operation.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("taskId", .UUIDAttributeType),
            attribute("operationType", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType, optional: true),
            attribute("baseVersion", .integer64AttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("retryCount", .integer32AttributeType)
        ]
        model.entities = [task, operation]
        return model
    }()

    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}

@objc(TaskEntity)
final class TaskEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var taskDescription: String?
    @NSManaged var status: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var sortOrder: Double
    @NSManaged var serverVersion: Int64
}

@objc(PendingOperationEntity)
final class PendingOperationEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var taskId: UUID
    @NSManaged var operationType: String
    @NSManaged var payload: Data?
    @NSManaged var baseVersion: Int64
    @NSManaged var createdAt: Date
    @NSManaged var retryCount: Int32
}
