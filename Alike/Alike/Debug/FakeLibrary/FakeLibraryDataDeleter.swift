#if DEBUG
import Storage

/// "Delete all data" for a fake session: there is no local data to delete.
///
/// `LocalAppDataDeletionService()` opens the real Core Data store as soon as it is
/// made, so a fake session must not make one.
nonisolated struct FakeLibraryDataDeleter: LocalAppDataDeleting {
    func deleteAllData() async throws {}
}
#endif
