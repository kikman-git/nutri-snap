import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

/// The app's single source of truth for logged nutrition (PRD §8), backed by Firestore with
/// offline persistence. Calendar + Trends read the tiny per-day **rollup** docs; the day diary
/// loads one day's `entries` on demand — the calendar never queries `entries` (the §8 perf
/// pattern). Single-user for now via **anonymous auth**; that account links to Sign in with Apple
/// at M4, keeping the same uid + all data.
@MainActor
@Observable
final class MealStore {
    /// Per-day rollups, oldest → newest. Drives the calendar grid + Trends.
    private(set) var rollups: [DayRollup] = []
    /// Daily target (seeded default until M5 onboarding writes a personalized one).
    private(set) var target: Nutrients = SampleData.target
    /// Most recent logged meal, for the capture screen's "just logged" card.
    private(set) var recentEntry: Entry?
    /// False until auth + the first snapshot land — screens can show a calm warming state.
    private(set) var ready = false

    enum Backend { case firestore, sample }
    private let backend: Backend
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var startTask: Task<Void, Never>?

    init(backend: Backend = .firestore) {
        self.backend = backend
        switch backend {
        case .sample:
            rollups = SampleData.rollups
            recentEntry = SampleData.recentEntry
            ready = true
        case .firestore:
            startTask = Task { await start() }
        }
    }

    /// Await first-launch sign-in so a write never races ahead of the uid. Without this, a meal
    /// snapped within a second of a cold launch (before anonymous auth restores) would be silently
    /// dropped — `currentUser` is nil, the write bails. No-op once `start()` has finished.
    private func awaitReady() async { await startTask?.value }

    /// Preview/test store seeded from `SampleData` — no Firestore, no network.
    static var sample: MealStore { MealStore(backend: .sample) }

    deinit { listener?.remove() }

    // MARK: - Startup

    private func start() async {
        // Anonymous sign-in needs the network only the first time; afterwards Auth serves the
        // cached user offline, and Firestore serves prior data from its local cache.
        guard let uid = try? await signedInUid() else { ready = true; return }
        let userRef = Firestore.firestore().collection("users").document(uid)
        await loadOrSeedProfile(userRef)
        attachRollupListener(userRef)
        await loadRecentEntry(userRef)
        ready = true
    }

    private func signedInUid() async throws -> String {
        if let user = Auth.auth().currentUser { return user.uid }
        return try await Auth.auth().signInAnonymously().user.uid
    }

    private func loadOrSeedProfile(_ userRef: DocumentReference) async {
        guard let snap = try? await userRef.getDocument() else { return }
        if let profile = try? snap.data(as: UserProfile.self) {
            target = profile.targets
        } else {
            let profile = UserProfile(targets: SampleData.target, createdAt: Date())
            try? userRef.setData(from: profile)
            target = profile.targets
        }
    }

    private func attachRollupListener(_ userRef: DocumentReference) {
        listener = userRef.collection("days").order(by: "date")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                self.rollups = docs.compactMap { try? $0.data(as: DayRollup.self) }
            }
    }

    private func loadRecentEntry(_ userRef: DocumentReference) async {
        let snap = try? await userRef.collection("entries")
            .order(by: "capturedAt", descending: true).limit(to: 1).getDocuments()
        recentEntry = snap?.documents.first.flatMap { try? $0.data(as: Entry.self) }
    }

    // MARK: - Writes

    /// Persist a captured meal: upload the photo (best-effort), then write the entry doc and bump
    /// its day rollup in one atomic, offline-safe batch. A failed photo upload never blocks logging.
    func save(_ entry: Entry, imageData: Data?) async throws {
        await awaitReady()
        guard backend == .firestore, let uid = Auth.auth().currentUser?.uid else {
            recentEntry = entry          // sample mode: just reflect it for previews
            return
        }
        var entry = entry
        let id = entry.id.uuidString
        let userRef = Firestore.firestore().collection("users").document(uid)

        if let imageData {
            // Photos live on-device (free tier; Cloud Storage needs Blaze — M4). Best-effort: a
            // failed write never blocks logging the meal. `photoPath` holds the local filename.
            let name = "\(id).jpg"
            if (try? imageData.write(to: LocalPhotos.url(name), options: .atomic)) != nil {
                entry.photoPath = name
            }
        }

        let dayStart = Calendar.current.startOfDay(for: entry.capturedAt)
        let dayRef = userRef.collection("days").document(DayLog.key(for: entry.capturedAt))
        let entryRef = userRef.collection("entries").document(id)

        // Field increments (not a transaction): they work offline, are commutative, and merge
        // correctly server-side — the right tool for maintaining a rollup. `merge: true` creates
        // the day doc + nested fields on the first meal of the day.
        let batch = Firestore.firestore().batch()
        try batch.setData(from: entry, forDocument: entryRef)
        batch.setData(rollupDelta(for: entry, dayStart: dayStart), forDocument: dayRef, merge: true)
        try await batch.commit()

        recentEntry = entry          // listener refreshes `rollups`
    }

    /// The merge payload that folds one entry's totals into its day rollup via field increments.
    /// `sign` is +1 on save, -1 on delete — increments are commutative, so add/remove both work offline.
    private func rollupDelta(for entry: Entry, dayStart: Date, sign: Double = 1) -> [String: Any] {
        var micros: [String: Any] = [:]
        for (key, value) in entry.micros.values where value != 0 {
            micros[key] = FieldValue.increment(sign * value)
        }
        var delta: [String: Any] = [
            "date": Timestamp(date: dayStart),
            "entryCount": FieldValue.increment(Int64(sign)),
            "totals": [
                "kcal": FieldValue.increment(sign * entry.totals.kcal),
                "protein": FieldValue.increment(sign * entry.totals.protein),
                "carbs": FieldValue.increment(sign * entry.totals.carbs),
                "fat": FieldValue.increment(sign * entry.totals.fat),
            ],
        ]
        if !micros.isEmpty { delta["microTotals"] = micros }
        return delta
    }

    /// Delta payload between two logged entries for the same day, used for edits.
    /// `entryCount` stays unchanged; totals and micros move by the difference.
    private func rollupDelta(from oldEntry: Entry, to newEntry: Entry, dayStart: Date) -> [String: Any] {
        var micros: [String: Any] = [:]
        let keys = Set(oldEntry.micros.values.keys).union(newEntry.micros.values.keys)

        for key in keys {
            let delta = (newEntry.micros.values[key] ?? 0) - (oldEntry.micros.values[key] ?? 0)
            if delta != 0 {
                micros[key] = FieldValue.increment(delta)
            }
        }

        var delta: [String: Any] = [
            "date": Timestamp(date: dayStart),
            "totals": [
                "kcal": FieldValue.increment(newEntry.totals.kcal - oldEntry.totals.kcal),
                "protein": FieldValue.increment(newEntry.totals.protein - oldEntry.totals.protein),
                "carbs": FieldValue.increment(newEntry.totals.carbs - oldEntry.totals.carbs),
                "fat": FieldValue.increment(newEntry.totals.fat - oldEntry.totals.fat),
            ],
        ]
        if !micros.isEmpty { delta["microTotals"] = micros }
        return delta
    }

    /// Delete a logged meal: drop the entry doc, undo its day rollup (or remove the rollup entirely
    /// when it was the day's only meal), and clean up the on-device photo. Offline-safe like `save`.
    func delete(_ entry: Entry) async {
        await awaitReady()
        // Local photo + cache go regardless of backend (no network needed).
        if let path = entry.photoPath {
            try? FileManager.default.removeItem(at: LocalPhotos.url(path))
            PhotoCache.shared.remove(named: path)
        }
        if recentEntry?.id == entry.id { recentEntry = nil }

        guard backend == .firestore, let uid = Auth.auth().currentUser?.uid else { return }
        let userRef = Firestore.firestore().collection("users").document(uid)
        let dayKey = DayLog.key(for: entry.capturedAt)
        let dayRef = userRef.collection("days").document(dayKey)
        let entryRef = userRef.collection("entries").document(entry.id.uuidString)
        let dayStart = Calendar.current.startOfDay(for: entry.capturedAt)

        let batch = Firestore.firestore().batch()
        batch.deleteDocument(entryRef)
        // Last meal of the day → drop the whole rollup so the calendar day goes empty; otherwise
        // decrement. The in-memory count avoids an extra read and works from the offline cache.
        if (rollups.first { $0.id == dayKey }?.entryCount ?? 1) <= 1 {
            batch.deleteDocument(dayRef)
        } else {
            batch.setData(rollupDelta(for: entry, dayStart: dayStart, sign: -1), forDocument: dayRef, merge: true)
        }
        try? await batch.commit()      // listener refreshes `rollups`

        if recentEntry == nil { await loadRecentEntry(userRef) }
    }

    /// Update a logged meal and apply only the delta between old and new values.
    /// Quiet edits stay lightweight and offline-safe through `FieldValue.increment`.
    func update(_ updatedEntry: Entry, replacing oldEntry: Entry) async {
        await awaitReady()
        var updated = updatedEntry
        updated.edited = true

        guard backend == .firestore else {
            if recentEntry?.id == oldEntry.id { recentEntry = updated }
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let userRef = Firestore.firestore().collection("users").document(uid)
        let oldDayKey = DayLog.key(for: oldEntry.capturedAt)
        let newDayKey = DayLog.key(for: updated.capturedAt)
        let oldDayRef = userRef.collection("days").document(oldDayKey)
        let newDayRef = userRef.collection("days").document(newDayKey)
        let entryRef = userRef.collection("entries").document(updated.id.uuidString)
        let batch = Firestore.firestore().batch()

        if oldDayKey == newDayKey {
            let dayStart = Calendar.current.startOfDay(for: updated.capturedAt)
            batch.setData(rollupDelta(from: oldEntry, to: updated, dayStart: dayStart),
                          forDocument: newDayRef, merge: true)
        } else {
            let oldDayStart = Calendar.current.startOfDay(for: oldEntry.capturedAt)
            let newDayStart = Calendar.current.startOfDay(for: updated.capturedAt)

            if (rollups.first { $0.id == oldDayKey }?.entryCount ?? 1) <= 1 {
                batch.deleteDocument(oldDayRef)
            } else {
                batch.setData(rollupDelta(for: oldEntry, dayStart: oldDayStart, sign: -1),
                              forDocument: oldDayRef, merge: true)
            }
            batch.setData(rollupDelta(for: updated, dayStart: newDayStart),
                          forDocument: newDayRef, merge: true)
        }

        do {
            try batch.setData(from: updated, forDocument: entryRef)
            try await batch.commit()
        } catch {
            return
        }

        if recentEntry?.id == oldEntry.id { recentEntry = updated }
    }

    // MARK: - Reads

    /// One day's meals for the photo diary — the only place that queries `entries` (PRD §8).
    func entries(on date: Date) async -> DayLog {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard backend == .firestore, let uid = Auth.auth().currentUser?.uid else {
            return SampleData.day(for: date) ?? DayLog(date: start, entries: [])
        }
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let snap = try? await Firestore.firestore().collection("users").document(uid)
            .collection("entries")
            .whereField("capturedAt", isGreaterThanOrEqualTo: Timestamp(date: start))
            .whereField("capturedAt", isLessThan: Timestamp(date: end))
            .order(by: "capturedAt")
            .getDocuments()
        let entries = snap?.documents.compactMap { try? $0.data(as: Entry.self) } ?? []
        return DayLog(date: start, entries: entries)
    }
}
