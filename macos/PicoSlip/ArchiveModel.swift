import AppKit
import PicoKit

/// Year, month or day of the Date sidebar; year 0 means every date.
nonisolated struct DateFilter: Hashable, Sendable {
    var year: Int
    var month: Int?
    var day: Int?

    static let all = DateFilter(year: 0)

    func matches(_ created: DateComponents?) -> Bool {
        guard year != 0 else { return true }
        guard let created, created.year == year else { return false }
        if let month, created.month != month { return false }
        if let day, created.day != day { return false }
        return true
    }
}

/// A node of the Date sidebar tree.
nonisolated struct DateNode: Identifiable, Hashable, Sendable {
    let id: DateFilter
    let label: String
    let count: Int
    var children: [DateNode]?
}

/// Part of a note around the first text hit.
nonisolated struct Excerpt: Hashable, Sendable {
    let before: String, match: String, after: String

    init(_ text: String, _ hit: Range<String.Index>) {
        let start = text.index(hit.lowerBound, offsetBy: -80, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(hit.upperBound, offsetBy: 320, limitedBy: text.endIndex) ?? text.endIndex
        before = (start > text.startIndex ? "…" : "") + text[start..<hit.lowerBound]
        match = String(text[hit])
        after = String(text[hit.upperBound..<end])
    }
}

nonisolated struct ArchiveResult: Identifiable, Hashable, Sendable {
    let note: ArchivedNote
    let excerpt: Excerpt?
    var id: String { note.id }
}

nonisolated enum SidebarMode: String, CaseIterable, Sendable {
    case tags = "Tags"
    case date = "Date"
}

/// State of the archive browser.
@Observable
final class ArchiveModel {
    var notes: [ArchivedNote] = [] { didSet { rebuildSidebar(); refilter() } }
    var query = "" { didSet { refilter() } }
    var mode = SidebarMode.tags { didSet { refilter() } }
    /// Each sidebar view keeps its own selection.
    var tag: String? { didSet { refilter() } }
    var date: DateFilter? = .all { didSet { refilter() } }
    private(set) var results: [ArchiveResult] = []
    private(set) var catalog: [TagCount] = []
    private(set) var dates: [DateNode] = []
    private(set) var error: String?
    var selection: Set<String> = []
    var focusRequest = 0

    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var monitor: DispatchSourceFileSystemObject?

    /// Reloads every note (F5 / ⌘R, external edits, changes from notes).
    func reload() {
        loadTask?.cancel()
        let folder = NoteStore.shared.folder
        loadTask = Task {
            do {
                let loaded = try await ArchiveReader.load(folder)
                guard !Task.isCancelled else { return }
                notes = loaded
                selection.formIntersection(loaded.map(\.id))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func rebuildSidebar() {
        catalog = Tags.catalog(notes.map(\.tags))
        let calendar = Calendar.current
        var tree: [Int: [Int: [Int: Int]]] = [:]
        for note in notes {
            guard let created = note.created, let year = created.year, let month = created.month, let day = created.day else { continue }
            tree[year, default: [:]][month, default: [:]][day, default: 0] += 1
        }
        let years = tree.keys.sorted(by: >).map { year in
            let months = tree[year]!.keys.sorted(by: >).map { month in
                let days = tree[year]![month]!.keys.sorted(by: >).map { day in
                    DateNode(id: DateFilter(year: year, month: month, day: day), label: String(day),
                             count: tree[year]![month]![day]!, children: nil)
                }
                return DateNode(id: DateFilter(year: year, month: month), label: calendar.monthSymbols[month - 1],
                                count: days.reduce(0) { $0 + $1.count }, children: days)
            }
            return DateNode(id: DateFilter(year: year), label: String(year), count: months.reduce(0) { $0 + $1.count },
                            children: months)
        }
        dates = [DateNode(id: .all, label: "All dates", count: notes.count, children: nil)] + years
    }

    private func refilter() {
        filterTask?.cancel()
        let notes = notes, query = query, tag = mode == .tags ? tag : nil, date = mode == .date ? date : nil
        filterTask = Task {
            let outcome = await Self.filter(notes, query: query, tag: tag, date: date)
            guard !Task.isCancelled else { return }
            results = outcome.results
            error = outcome.error
        }
    }

    @concurrent
    nonisolated private static func filter(_ notes: [ArchivedNote], query: String, tag: String?, date: DateFilter?) async
        -> (results: [ArchiveResult], error: String?) {
        var search: SearchQuery?
        if !query.allSatisfy(Tags.isSpace) {
            guard let parsed = SearchQuery(query) else { return ([], SearchQuery.invalidMessage) }
            search = parsed
        }
        var results: [ArchiveResult] = []
        for note in notes {
            if Task.isCancelled { break }
            if let tag, !Tags.contains(note.tags, tag) { continue }
            if let date, !date.matches(note.created) { continue }
            var excerpt: Excerpt?
            if let search {
                let match = search.match(text: note.text, tags: note.tags)
                guard match.matches else { continue }
                excerpt = match.hit.map { Excerpt(note.text, $0) }
            }
            results.append(ArchiveResult(note: note, excerpt: excerpt))
        }
        return (results, nil)
    }

    // MARK: Watching the folder for external edits

    func startWatching() {
        stopWatching()
        let descriptor = open(NoteStore.shared.folder.url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reload() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        monitor = source
    }

    func stopWatching() {
        monitor?.cancel()
        monitor = nil
    }
}
