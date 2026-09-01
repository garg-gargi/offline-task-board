# Offline Task Board

A UIKit-based task board designed around an offline-first architecture.

The application supports creating, editing, deleting, moving and reordering tasks across To Do, In Progress and Done states. Local changes are persisted immediately and synchronized with a remote Firebase Realtime Database when connectivity is available.

The implementation focuses on predictable state, durable offline changes, separation of concerns and testable business logic.

---

## Features

### Core task management

- Create tasks
- Edit tasks
- Delete tasks
- Move tasks between To Do, In Progress and Done
- Reorder tasks within a status
- Persist tasks across app launches

### Offline-first behavior

- Local changes are applied immediately
- Changes remain available across app relaunches
- Pending changes are stored durably until synchronization succeeds
- Network failures do not discard local work
- Sync is triggered when connectivity becomes available

### Synchronization

- Firebase Realtime Database is used as the remote data source
- Local changes are represented as durable pending operations
- Multiple local changes to the same task are coalesced
- Remote changes are reconciled with local state
- Sync status is surfaced in the UI

### Conflict handling

- Optimistic concurrency using a server version
- Task-level conflict detection
- Deterministic last-write-wins resolution using `updatedAt`

---

## Architecture

The application uses:

**UIKit + MVVM + Repository + Data Sources + Sync Manager**

```text
                    ┌──────────────────────┐
                    │    ViewController    │
                    └──────────┬───────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │   TaskBoardViewModel │
                    └──────────┬───────────┘
                               │
                    ┌──────────┴───────────┐
                    │                      │
                    ▼                      ▼
             ┌──────────────┐      ┌──────────────┐
             │TaskRepository│      │ SyncManager  │
             └──────┬───────┘      └──────┬───────┘
                    │                     │
                    ▼                     ▼
             ┌──────────────┐      ┌──────────────┐
             │LocalDataSource│     │RemoteDataSource│
             │  Core Data   │      │   Firebase   │
             └──────────────┘      └──────────────┘
```

### Components

#### ViewController

- Handles UIKit presentation and user interactions
- Displays tasks and sync status
- Does not contain persistence or synchronization logic

#### TaskBoardViewModel

- Coordinates presentation state and user actions
- Coordinates user actions with the repository
- Exposes task and synchronization state to the UI
- Reloads local state after synchronization changes

#### TaskRepository

- Provides the application-facing task API
- Hides persistence details from the ViewModel
- Allows the repository implementation to be replaced for testing

#### LocalDataSource

- Handles Core Data persistence
- Applies local task mutations
- Maintains the durable pending-operation outbox
- Handles task ordering and normalization
- Coalesces pending operations for the same task

#### RemoteDataSource

- Handles Firebase Realtime Database operations
- Performs remote create, update and delete operations
- Performs server-version checks
- Handles the remote side of conflict resolution

#### SyncManager

- Coordinates local and remote synchronization
- Processes pending operations
- Reconciles remote changes with local state
- Tracks synchronization state
- Triggers synchronization when connectivity is restored

---

## Offline-first approach

The local database is treated as the source of truth for the UI.

When a user performs a mutation:

1. The local task is updated immediately
2. A pending synchronization operation is persisted
3. The UI reflects the local change immediately
4. `SyncManager` attempts synchronization when connectivity is available
5. The pending operation is removed after successful synchronization

This ensures that network failures do not result in lost user changes.

---

## Pending operations

Pending synchronization operations are stored persistently in Core Data.

Each operation contains:

- Task ID
- Operation type
- Latest desired task state
- Base server version
- Creation timestamp
- Retry count

The outbox represents pending synchronization intent rather than an audit history.

---

## Operation coalescing

Multiple local changes to the same task are combined into a single pending operation where possible.

Examples:

- Create + multiple updates → Create with final state
- Multiple updates → Update with final state
- Update + delete → Delete
- Create + delete → No remote operation required

This reduces unnecessary network requests while preserving the user's final intent.

---

## Ordering

Each task has a `sortOrder` within its status.

A `Double` is used so that an item can usually be inserted between two existing items without immediately rewriting every task.

For example:

```text
1.0
2.0

Insert between them:

1.0
1.5
2.0
```

When ordering values become too close, the affected status is normalized.

When a task is moved between statuses:

- The task receives a position in the destination status
- The source status is normalized
- The destination status is normalized
- Changed tasks are included in synchronization

---

## Synchronization

Synchronization is handled by `SyncManager`.

The general flow is:

1. Check network availability
2. Fetch pending local operations
3. Process pending create, update and delete operations
4. Remove successfully synchronized operations
5. Update the local server version
6. Fetch and reconcile remote tasks
7. Preserve local changes that are still pending
8. Persist remote-only changes locally
9. Update the synchronization state shown in the UI

Pending local operations are processed before remote reconciliation so that unsynchronized local intent is not accidentally overwritten by a remote snapshot.

---

## Conflict resolution

The remote task contains a `serverVersion`.

Each local update stores the server version it was based on.

`serverVersion` is used for conflict detection, while `updatedAt` is used to determine the winning state.

During synchronization:

- If the local base version matches the remote version, the local change can be applied
- If the versions differ, a conflict is detected
- If `local.updatedAt > remote.updatedAt`, the local state wins
- Otherwise, the remote state wins

The winning state receives the next server version.

This provides deterministic conflict resolution without requiring a conflict-resolution UI.

---

## Conflict resolution trade-off

The current implementation resolves conflicts at the task level.

It does not perform field-level merging.

For example, if two clients modify different fields of the same task at the same time, the winning task version replaces the other version.

This approach was chosen because it is:

- Deterministic
- Simple to reason about
- Easy to test
- Appropriate for the scope of this assignment

The trade-off is that independent changes to different fields can be lost when the task versions conflict.

A production implementation could use:

- Field-level merging
- A user-facing conflict-resolution flow
- More sophisticated versioning

These were intentionally kept out of scope for this assignment.

---

## Sync status

The UI exposes the current synchronization state:

- All changes synced
- Syncing
- Changes pending
- Sync failed

The user can continue working with local data even when synchronization fails.

---

## Key design decisions & trade-offs

### Core Data

**Decision:** Core Data was chosen for durable local persistence.

It also provides a suitable place to persist the synchronization outbox so pending work survives application termination.

**Trade-off:** Core Data introduces more implementation complexity than a lightweight JSON or `UserDefaults` approach, but provides structured persistence suitable for an offline-first task board.

### Repository abstraction

**Decision:** The repository keeps the ViewModel independent of Core Data and Firebase implementation details.

It also allows an in-memory implementation to be used for testing.

**Trade-off:** The abstraction adds protocols and an additional layer for a relatively small application, but improves separation of concerns and testability.

### Separate SyncManager

**Decision:** Synchronization is kept separate from both the UI and persistence layers.

This keeps the responsibilities of the repository and ViewModel focused and makes the synchronization workflow easier to reason about.

**Trade-off:** This introduces another coordination layer, but avoids placing synchronization state and network orchestration inside the ViewModel or local data source.

### Durable outbox

**Decision:** Pending operations are persisted instead of being kept only in memory.

This ensures that pending changes survive application termination.

**Trade-off:** The application has to maintain synchronization metadata in addition to task state, but this is necessary to avoid losing unsynchronized user work.

### Operation coalescing

**Decision:** Only the latest meaningful synchronization state of a task needs to be synchronized.

Coalescing avoids sending unnecessary intermediate changes to the remote service.

**Trade-off:** The outbox represents the latest synchronization intent rather than a complete history of user actions. An audit history would require a separate event/history model.

### Double-based ordering

**Decision:** `Double` sort orders allow a task to usually be inserted between two existing tasks without immediately rewriting the entire list.

**Trade-off:** Repeated insertions can cause ordering values to become too close, so normalization is required when necessary.

### Task-level last-write-wins

**Decision:** Use `serverVersion` for conflict detection and `updatedAt` for deterministic last-write-wins resolution.

**Trade-off:** The approach is simple and predictable, but concurrent changes to different fields cannot be merged independently.

### Lightweight synchronization triggers

**Decision:** Synchronization is triggered on application launch, after local mutations, and when network connectivity is restored.

**Trade-off:** This is simpler than implementing a full background synchronization scheduler, but synchronization is not as comprehensive as a production implementation with background execution and sophisticated retry policies.

### Firebase Realtime Database

**Decision:** Firebase Realtime Database is used as the remote data source.

**Trade-off:** It avoids the need to build a custom backend for the assignment, but introduces Firebase-specific infrastructure and provides less control over server-side concurrency and business logic than a dedicated backend.

---

## Error handling

- Local persistence errors are surfaced to the UI
- Remote synchronization failures do not remove pending operations
- Local changes are therefore not lost when synchronization fails
- Pending operations can be retried during a later synchronization attempt
- Network connectivity is monitored using `NWPathMonitor`

---

## Assumptions

- The application represents a single logical task board
- Authentication is out of scope
- User-specific task ownership is out of scope
- Firebase Realtime Database is used as the remote API
- Tasks are uniquely identified using UUIDs
- Conflict resolution is performed at task level
- Background synchronization is out of scope
- Initial sample data is seeded only when the local store is empty
- The task board is treated as a single-user scenario for the assignment
- Firebase security and access control are handled outside the scope of the implementation

---

## Limitations

- Authentication and authorization are not implemented
- Firebase test-mode database rules are used for the assignment
- Background synchronization is not implemented
- Conflict resolution is task-level rather than field-level
- Remote version checking currently uses a read-then-write flow rather than an atomic server-side transaction
- There is no dedicated conflict-resolution UI
- The implementation targets a single-user task-board scenario
- Retry handling is intentionally lightweight and does not implement exponential backoff
- Synchronization currently operates on the task set rather than using incremental change feeds

---

## What I would improve with more time

- Add authentication and user-specific task ownership
- Use Firebase transactions for stronger server-side concurrency guarantees
- Add background synchronization
- Add exponential backoff for retries
- Support field-level conflict merging
- Increase automated unit and UI test coverage
- Add structured synchronization logging and observability
- Add incremental synchronization for larger datasets
- Add a dedicated conflict-resolution UI where user intervention is valuable

---

## Setup

### Requirements

- Xcode
- iOS Simulator or physical iOS device
- Firebase project
- Firebase Realtime Database enabled

### Firebase configuration

1. Clone the repository
2. Open the project in Xcode
3. Resolve Swift Package Manager dependencies
4. Create or configure a Firebase project
5. Add an iOS application using the application's bundle identifier
6. Enable Firebase Realtime Database
7. Download `GoogleService-Info.plist`
8. Add it to the `OfflineTaskBoard` target
9. Configure the Realtime Database rules for the environment
10. Build and run

Firebase dependencies are managed using Swift Package Manager.

`GoogleService-Info.plist` is intentionally excluded from source control and must be provided locally.

> The Firebase rules used for this assignment are intended for development/testing only and are not production-safe.

---

## Testing

The following scenarios were manually verified:

### Task operations

- Create task
- Edit task
- Delete task
- Move task between statuses
- Reorder tasks
- Persistence across app launches

### Offline behavior

- Create, update and delete while offline
- Relaunch the application while offline
- Verify pending changes survive application termination
- Restore connectivity and verify synchronization

### Conflict handling

- Simulate a remote version change
- Verify version mismatch is detected
- Verify deterministic conflict resolution
- Verify resolved state is persisted locally
- Verify resolved state is reflected in the UI

### Failure handling

- Verify local changes are retained when synchronization fails
- Verify pending synchronization state remains available for retry

---

## Time spent

Approximately 9 hours, including implementation, debugging, testing, Firebase setup and documentation.

---

## AI tools used

AI assistance was used during development for:

- Architecture discussions
- Evaluating implementation approaches
- Debugging
- Reasoning about synchronization and conflict handling
- Documentation

All implementation decisions were reviewed and validated through testing.
