//
//  RemoteDataSource.swift
//  OfflineTaskBoard
//
//  Created by Gargi Garg on 02/09/26.
//

import Foundation
import FirebaseDatabase

enum RemoteDataSourceError: Error {
    case invalidSnapshot
    case taskNotFound
}

protocol RemoteDataSource: AnyObject {
    func fetchTasks(completion: @escaping (Result<[Task], Error>) -> Void)

    func create(
        task: Task,
        completion: @escaping (Result<Task, Error>) -> Void
    )

    func update(
        task: Task,
        baseVersion: Int64,
        completion: @escaping (Result<Task, Error>) -> Void
    )

    func delete(
        taskId: UUID,
        baseVersion: Int64,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

final class FirebaseRemoteDataSource: RemoteDataSource {

    private let tasksReference: DatabaseReference

    init(
        tasksReference: DatabaseReference = Database.database().reference().child("tasks")
    ) {
        self.tasksReference = tasksReference
    }

    func fetchTasks(
        completion: @escaping (Result<[Task], Error>) -> Void
    ) {
        tasksReference.getData { error, snapshot in
            if let error {
                completion(.failure(error))
                return
            }

            guard let snapshot else {
                completion(.failure(RemoteDataSourceError.invalidSnapshot))
                return
            }

            do {
                let tasks = try snapshot.children.allObjects
                    .compactMap { child -> Task? in
                        guard let child = child as? DataSnapshot else {
                            return nil
                        }

                        return try Self.task(from: child)
                    }

                completion(.success(tasks))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func create(
        task: Task,
        completion: @escaping (Result<Task, Error>) -> Void
    ) {
        var taskToSave = task
        taskToSave.serverVersion = 1

        tasksReference
            .child(task.id.uuidString)
            .setValue(Self.dictionary(from: taskToSave)) { error, _ in

                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(taskToSave))
                }
            }
    }

    func update(
        task: Task,
        baseVersion: Int64,
        completion: @escaping (Result<Task, Error>) -> Void
    ) {
        let reference = tasksReference.child(task.id.uuidString)

        reference.getData { error, snapshot in

            if let error {
                completion(.failure(error))
                return
            }

            // The task does not exist remotely yet.
            // Treat this as an initial upload.
            guard let snapshot, snapshot.exists() else {

                var createdTask = task
                createdTask.serverVersion = 1

                reference.setValue(
                    Self.dictionary(from: createdTask)
                ) { error, _ in

                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(createdTask))
                    }
                }

                return
            }

            do {
                let remoteTask = try Self.task(from: snapshot)

                guard remoteTask.serverVersion == baseVersion else {

                    // Conflict.
                    //
                    // Deterministic resolution:
                    // the task with the newer updatedAt wins.
                    let winner =
                        task.updatedAt >= remoteTask.updatedAt
                        ? task
                        : remoteTask

                    var resolved = winner
                    resolved.serverVersion =
                        remoteTask.serverVersion + 1

                    reference.setValue(
                        Self.dictionary(from: resolved)
                    ) { error, _ in

                        if let error {
                            completion(.failure(error))
                        } else {
                            completion(.success(resolved))
                        }
                    }

                    return
                }

                var updated = task
                updated.serverVersion =
                    remoteTask.serverVersion + 1

                reference.setValue(
                    Self.dictionary(from: updated)
                ) { error, _ in

                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(updated))
                    }
                }

            } catch {
                completion(.failure(error))
            }
        }
    }

    func delete(
        taskId: UUID,
        baseVersion: Int64,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let reference = tasksReference.child(taskId.uuidString)

        reference.getData { error, snapshot in
            if let error {
                completion(.failure(error))
                return
            }

            guard let snapshot, snapshot.exists() else {
                completion(.success(()))
                return
            }

            do {
                let remoteTask = try Self.task(from: snapshot)

                guard remoteTask.serverVersion == baseVersion else {
                    // A remote change happened after this delete was created.
                    //
                    // For this take-home we resolve the conflict in favour
                    // of the remote version rather than deleting it.
                    completion(.success(()))
                    return
                }

                reference.removeValue { error, _ in
                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }

            } catch {
                completion(.failure(error))
            }
        }
    }
}
private extension FirebaseRemoteDataSource {

    static func dictionary(from task: Task) -> [String: Any] {
        var dictionary: [String: Any] = [
            "id": task.id.uuidString,
            "title": task.title,
            "status": task.status.rawValue,
            "createdAt": task.createdAt.timeIntervalSince1970,
            "updatedAt": task.updatedAt.timeIntervalSince1970,
            "sortOrder": task.sortOrder,
            "serverVersion": task.serverVersion
        ]

        dictionary["description"] = task.description ?? NSNull()

        return dictionary
    }

    static func task(from snapshot: DataSnapshot) throws -> Task {
        guard
            let value = snapshot.value as? [String: Any],
            let idString = value["id"] as? String,
            let id = UUID(uuidString: idString),
            let title = value["title"] as? String,
            let statusString = value["status"] as? String,
            let status = TaskStatus(rawValue: statusString),
            let createdAt = value["createdAt"] as? TimeInterval,
            let updatedAt = value["updatedAt"] as? TimeInterval,
            let sortOrder = value["sortOrder"] as? Double,
            let serverVersion = value["serverVersion"] as? Int
        else {
            throw RemoteDataSourceError.invalidSnapshot
        }

        let description = value["description"] as? String

        return Task(
            id: id,
            title: title,
            description: description,
            status: status,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            sortOrder: sortOrder,
            serverVersion: Int64(serverVersion)
        )
    }
}
