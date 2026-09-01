//
//  SyncManager.swift
//  OfflineTaskBoard
//
//  Created by Gargi Garg on 02/09/26.
//

import Foundation

enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced
    case changesPending
    case failed
}

final class SyncManager {

    private let local: LocalDataSource
    private let remote: RemoteDataSource
    private let networkMonitor: NetworkMonitor

    private(set) var status: SyncStatus = .idle

    var onStatusChange: ((SyncStatus) -> Void)?

    // If a sync request comes in while another sync is running,
    // we remember it and run another sync after the current one finishes.
    private var syncRequestedWhileRunning = false
    private var isSyncing = false

    init(
        local: LocalDataSource,
        remote: RemoteDataSource,
        networkMonitor: NetworkMonitor = NetworkMonitor()
    ) {
        self.local = local
        self.remote = remote
        self.networkMonitor = networkMonitor

        self.networkMonitor.onConnectionChange = { [weak self] isConnected in
            guard let self, isConnected else { return }

            self.sync()
        }
    }

    func sync() {
        guard networkMonitor.isConnected else {
            setStatus(.changesPending)
            return
        }
        guard !isSyncing else {
            syncRequestedWhileRunning = true
            return
        }

        isSyncing = true
        syncRequestedWhileRunning = false

        do {
            let operations = try local.fetchPendingOperations()

            if operations.isEmpty {
                setStatus(.syncing)
                pullRemoteTasks()
            } else {
                setStatus(.syncing)
                processOperations(operations)
            }

        } catch {
            finishSync(with: .failed)
        }
    }
}

private extension SyncManager {

    // MARK: - Operation Processing

    func processOperations(_ operations: [PendingOperation]) {

        processOperation(
            operations,
            at: 0
        )
    }

    func processOperation(
        _ operations: [PendingOperation],
        at index: Int
    ) {

        guard index < operations.count else {
            pullRemoteTasks()
            return
        }

        let operation = operations[index]

        switch operation.type {

        case .create:
            processCreate(
                operation,
                operations: operations,
                index: index
            )

        case .update:
            processUpdate(
                operation,
                operations: operations,
                index: index
            )

        case .delete:
            processDelete(
                operation,
                operations: operations,
                index: index
            )
        }
    }

    func processCreate(
        _ operation: PendingOperation,
        operations: [PendingOperation],
        index: Int
    ) {

        guard let task = try? operation.decodedTask() else {
            finishSync(with: .failed)
            return
        }

        remote.create(task: task) { [weak self] result in

            guard let self else {
                return
            }

            switch result {

            case .success(let syncedTask):

                do {
                    try self.local.markSynced(
                        task: syncedTask,
                        operationId: operation.id
                    )

                    self.processOperation(
                        operations,
                        at: index + 1
                    )

                } catch {
                    self.finishSync(with: .failed)
                }

            case .failure:
                self.finishSync(with: .failed)
            }
        }
    }

    func processUpdate(
        _ operation: PendingOperation,
        operations: [PendingOperation],
        index: Int
    ) {

        guard let task = try? operation.decodedTask() else {
            finishSync(with: .failed)
            return
        }

        remote.update(
            task: task,
            baseVersion: operation.baseVersion
        ) { [weak self] result in

            guard let self else {
                return
            }

            switch result {

            case .success(let syncedTask):

                do {
                    try self.local.markSynced(
                        task: syncedTask,
                        operationId: operation.id
                    )

                    self.processOperation(
                        operations,
                        at: index + 1
                    )

                } catch {
                    self.finishSync(with: .failed)
                }

            case .failure:
                self.finishSync(with: .failed)
            }
        }
    }

    func processDelete(
        _ operation: PendingOperation,
        operations: [PendingOperation],
        index: Int
    ) {

        remote.delete(
            taskId: operation.taskId,
            baseVersion: operation.baseVersion
        ) { [weak self] result in

            guard let self else {
                return
            }

            switch result {

            case .success:

                do {
                    try self.local.removePendingOperation(
                        id: operation.id
                    )

                    self.processOperation(
                        operations,
                        at: index + 1
                    )

                } catch {
                    self.finishSync(with: .failed)
                }

            case .failure:
                self.finishSync(with: .failed)
            }
        }
    }

    // MARK: - Remote Pull

    func pullRemoteTasks() {

        remote.fetchTasks { [weak self] result in

            guard let self else {
                return
            }

            switch result {

            case .success(let remoteTasks):

                if remoteTasks.isEmpty {
                    self.bootstrapRemoteStore()
                } else {

                    do {
                        try self.reconcile(remoteTasks)
                        self.finishSync(with: .synced)
                    } catch {
                        self.finishSync(with: .failed)
                    }
                }

            case .failure:
                self.finishSync(with: .failed)
            }
        }
    }

    // MARK: - Reconciliation

    func reconcile(_ remoteTasks: [Task]) throws {

        let pendingOperations = try local.fetchPendingOperations()

        let pendingTaskIDs = Set(
            pendingOperations.map(\.taskId)
        )

        for remoteTask in remoteTasks {

            // Never overwrite a local task that still has
            // an unsynchronised mutation.
            guard !pendingTaskIDs.contains(remoteTask.id) else {
                continue
            }

            try local.upsertRemoteTask(remoteTask)
        }
    }

    // MARK: - Initial Bootstrap

    func bootstrapRemoteStore() {

        do {

            let localTasks = try local.fetchTasks()

            guard !localTasks.isEmpty else {
                finishSync(with: .synced)
                return
            }

            bootstrap(
                localTasks,
                at: 0
            )

        } catch {
            finishSync(with: .failed)
        }
    }

    func bootstrap(
        _ tasks: [Task],
        at index: Int
    ) {

        guard index < tasks.count else {
            finishSync(with: .synced)
            return
        }

        let task = tasks[index]

        remote.create(task: task) { [weak self] result in

            guard let self else {
                return
            }

            switch result {

            case .success(let syncedTask):

                do {

                    try self.local.upsertRemoteTask(
                        syncedTask
                    )

                    self.bootstrap(
                        tasks,
                        at: index + 1
                    )

                } catch {
                    self.finishSync(with: .failed)
                }

            case .failure:
                self.finishSync(with: .failed)
            }
        }
    }

    // MARK: - Sync Completion

    func finishSync(with status: SyncStatus) {

        isSyncing = false

        do {

            let pendingOperations = try local.fetchPendingOperations()

            if !pendingOperations.isEmpty {

                setStatus(.changesPending)

                // A newer local operation may have been created
                // while the previous sync was in flight.
                if syncRequestedWhileRunning {
                    syncRequestedWhileRunning = false
                    sync()
                }

                return
            }

        } catch {
            setStatus(.failed)
            return
        }

        setStatus(status)

        // Handle a sync request that arrived while the current
        // sync was still running.
        if syncRequestedWhileRunning {

            syncRequestedWhileRunning = false
            sync()
        }
    }

    // MARK: - Status

    func setStatus(_ status: SyncStatus) {

        self.status = status
        onStatusChange?(status)
    }
}
