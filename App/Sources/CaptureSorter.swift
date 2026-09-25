import Foundation

struct CaptureEntry: Identifiable, Hashable {
    var id: String { "\(captureFolder)|\(object)|\(year)-\(month)" }
    var captureFolder: String
    var year: String
    var month: String
    var object: String
    var imageFolders: Int
    var files: Int
    var formats: [String]
    var targetDirectory: URL
    var targetExists: Bool
    var sourceFiles: [URL]
}

struct SortPlanItem: Identifiable {
    var id: String { source.path }
    var source: URL
    var destination: URL
    var action: Action

    enum Action: String {
        case move, replace, keep
    }
}

struct SortSummary {
    var move = 0
    var replace = 0
    var keep = 0
    var createTargets: [String] = []
    var removedFolders = 0
}

struct BackupSummary {
    var folders = 0
    var files = 0
    var destination: URL
}

enum CaptureSorter {
    static let defaultSource = URL(fileURLWithPath: "/Volumes/Astronomy/Captures")
    private static let imageExtensions: Set<String> = ["tif", "tiff", "fit", "fits"]

    // Vaonis / Singularity
    private static let datedCapture = try! NSRegularExpression(pattern: #"^(\d{4})-(\d{2})-"#)
    private static let observation = try! NSRegularExpression(
        pattern: #"^(?:\d+-)?observation[-_](.+)$"#,
        options: .caseInsensitive
    )
    private static let datedObservationCapture = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_observation[-_](.+)$"#,
        options: .caseInsensitive
    )
    private static let imagesFolder = try! NSRegularExpression(
        pattern: #"^(?:\d+-)?images(?:[-_].+)?$"#,
        options: .caseInsensitive
    )

    // Origin: M31_2024-06-15 or M31-2024-06-15
    private static let originDatedObject = try! NSRegularExpression(
        pattern: #"^(.+?)[_-](\d{4})-(\d{2})-(\d{2})(?:$|[_-].*)"#,
        options: .caseInsensitive
    )
    // Generic leading date YYYY-MM-DD or YYYYMMDD
    private static let leadingISODate = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})"#
    )
    private static let leadingCompactDate = try! NSRegularExpression(
        pattern: #"^(\d{4})(\d{2})(\d{2})(?:[_-].*)?$"#
    )

    static func scan(
        kind: TelescopeKind,
        sourceRoot: URL = defaultSource,
        year: String? = nil,
        month: String? = nil
    ) throws -> (entries: [CaptureEntry], years: [String], excluded: String) {
        switch kind {
        case .vaonis:
            return try scanVaonis(sourceRoot: sourceRoot, year: year, month: month)
        case .seestar, .dwarf, .origin:
            return try scanGenericSessions(kind: kind, sourceRoot: sourceRoot, year: year, month: month)
        }
    }

    // MARK: - Vaonis (existing rules)

    private static func scanVaonis(
        sourceRoot: URL,
        year: String?,
        month: String?
    ) throws -> (entries: [CaptureEntry], years: [String], excluded: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceRoot.path) else {
            return ([], [], "Targets …")
        }

        var entries: [CaptureEntry] = []
        var years = Set<String>()
        let children = try fm.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for capture in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: capture.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let name = capture.lastPathComponent
            if name.lowercased().hasPrefix("targets ") { continue }

            guard let match = firstMatch(datedCapture, in: name) else { continue }
            let captureYear = substring(match.range(at: 1), in: name)
            let captureMonth = substring(match.range(at: 2), in: name)
            guard !captureYear.isEmpty, !captureMonth.isEmpty else { continue }
            years.insert(captureYear)
            if let year, year != "all", captureYear != year { continue }
            if let month, month != "all", captureMonth != month { continue }

            var byObject: [String: (folders: Int, files: [URL])] = [:]
            for (observationURL, objectName) in observationFolders(in: capture) {
                let imageDirs = imagesFolders(under: observationURL)
                let files = imageFiles(from: imageDirs, alsoUnder: observationURL)
                let prior = byObject[objectName] ?? (0, [])
                let folderCount = max(imageDirs.count, 1)
                byObject[objectName] = (prior.folders + folderCount, prior.files + files)
            }

            let targetRoot = sourceRoot.appendingPathComponent("Targets \(captureYear)", isDirectory: true)
            var targetIsDir: ObjCBool = false
            let targetExists = fm.fileExists(atPath: targetRoot.path, isDirectory: &targetIsDir) && targetIsDir.boolValue

            for (objectName, bundle) in byObject.sorted(by: { $0.key < $1.key }) {
                let uniqueFiles = dedupeFiles(bundle.files)
                entries.append(
                    CaptureEntry(
                        captureFolder: name,
                        year: captureYear,
                        month: captureMonth,
                        object: objectName,
                        imageFolders: bundle.folders,
                        files: uniqueFiles.count,
                        formats: formats(of: uniqueFiles),
                        targetDirectory: targetRoot.appendingPathComponent(objectName, isDirectory: true),
                        targetExists: targetExists,
                        sourceFiles: uniqueFiles
                    )
                )
            }
        }

        entries.sort {
            ($0.year, $0.month, $0.captureFolder, $0.object) < ($1.year, $1.month, $1.captureFolder, $1.object)
        }
        return (entries, years.sorted(by: >), "Targets …")
    }

    // MARK: - Seestar / DWARF / Origin

    /// Top-level session/object folders under Captures. Year/month from folder name
    /// when possible, otherwise from newest TIFF/FITS modification date.
    private static func scanGenericSessions(
        kind: TelescopeKind,
        sourceRoot: URL,
        year: String?,
        month: String?
    ) throws -> (entries: [CaptureEntry], years: [String], excluded: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceRoot.path) else {
            return ([], [], "Targets …")
        }

        var entries: [CaptureEntry] = []
        var years = Set<String>()
        let children = try fm.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for capture in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: capture.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let name = capture.lastPathComponent
            if name.lowercased().hasPrefix("targets ") { continue }

            let groups = sessionObjectGroups(kind: kind, captureRoot: capture)
            guard !groups.isEmpty else { continue }

            for group in groups {
                let (y, m) = yearMonth(for: group, captureName: name, kind: kind)
                years.insert(y)
                if let year, year != "all", y != year { continue }
                if let month, month != "all", m != month { continue }

                let uniqueFiles = dedupeFiles(group.files)

                let targetRoot = sourceRoot.appendingPathComponent("Targets \(y)", isDirectory: true)
                var targetIsDir: ObjCBool = false
                let targetExists = fm.fileExists(atPath: targetRoot.path, isDirectory: &targetIsDir) && targetIsDir.boolValue

                entries.append(
                    CaptureEntry(
                        captureFolder: name,
                        year: y,
                        month: m,
                        object: group.object,
                        imageFolders: group.imageFolders,
                        files: uniqueFiles.count,
                        formats: formats(of: uniqueFiles),
                        targetDirectory: targetRoot.appendingPathComponent(group.object, isDirectory: true),
                        targetExists: targetExists,
                        sourceFiles: uniqueFiles
                    )
                )
            }
        }

        entries.sort {
            ($0.year, $0.month, $0.captureFolder, $0.object) < ($1.year, $1.month, $1.captureFolder, $1.object)
        }
        return (entries, years.sorted(by: >), "Targets …")
    }

    private struct SessionGroup {
        var object: String
        var files: [URL]
        var imageFolders: Int
        var hintYear: String?
        var hintMonth: String?
    }

    private static func sessionObjectGroups(kind: TelescopeKind, captureRoot: URL) -> [SessionGroup] {
        switch kind {
        case .vaonis:
            return []
        case .origin:
            return originGroups(captureRoot: captureRoot)
        case .seestar:
            return seestarGroups(captureRoot: captureRoot)
        case .dwarf:
            return dwarfGroups(captureRoot: captureRoot)
        }
    }

    /// Origin: folder often `Object_YYYY-MM-DD` (or nested). All FITS under that folder → one DSO.
    private static func originGroups(captureRoot: URL) -> [SessionGroup] {
        let name = captureRoot.lastPathComponent
        if let match = firstMatch(originDatedObject, in: name) {
            let object = dsoName(substring(match.range(at: 1), in: name))
            let y = substring(match.range(at: 2), in: name)
            let m = substring(match.range(at: 3), in: name)
            let files = imageFiles(under: captureRoot)
            guard !object.isEmpty else { return [] }
            return [SessionGroup(object: object, files: files, imageFolders: 1, hintYear: y, hintMonth: m)]
        }
        // Nested object+date folders one level down
        var groups: [SessionGroup] = []
        let kids = (try? FileManager.default.contentsOfDirectory(
            at: captureRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for kid in kids {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: kid.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let leaf = kid.lastPathComponent
            if let match = firstMatch(originDatedObject, in: leaf) {
                let object = dsoName(substring(match.range(at: 1), in: leaf))
                let y = substring(match.range(at: 2), in: leaf)
                let m = substring(match.range(at: 3), in: leaf)
                let files = imageFiles(under: kid)
                if !object.isEmpty {
                    groups.append(SessionGroup(object: object, files: files, imageFolders: 1, hintYear: y, hintMonth: m))
                }
            }
        }
        if !groups.isEmpty { return groups }

        // Fallback: whole tree as one object named from folder
        let files = imageFiles(under: captureRoot)
        guard !files.isEmpty else { return [] }
        return [SessionGroup(object: dsoName(stripVendorNoise(name)), files: files, imageFolders: 1, hintYear: nil, hintMonth: nil)]
    }

    /// Seestar: object albums (M31, NGC7023) or a dump of FIT files under one transfer folder.
    private static func seestarGroups(captureRoot: URL) -> [SessionGroup] {
        let name = captureRoot.lastPathComponent
        let kids = (try? FileManager.default.contentsOfDirectory(
            at: captureRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var subDirs: [URL] = []
        var loose: [URL] = []
        for kid in kids {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: kid.path, isDirectory: &isDir), isDir.boolValue {
                let lower = kid.lastPathComponent.lowercased()
                // Skip Seestar UI noise folders if present
                if lower == "thumbnail" || lower == "thumbnails" || lower.hasSuffix("_thumbnail") { continue }
                subDirs.append(kid)
            } else if imageExtensions.contains(kid.pathExtension.lowercased()) {
                loose.append(kid)
            }
        }

        // If children look like object albums, one group per child that has images.
        let albumGroups: [SessionGroup] = subDirs.compactMap { dir in
            let files = imageFiles(under: dir)
            guard !files.isEmpty else { return nil }
            let object = dsoName(stripVendorNoise(dir.lastPathComponent))
            guard !object.isEmpty else { return nil }
            let (hy, hm) = dateHints(fromFolderName: dir.lastPathComponent)
            return SessionGroup(object: object, files: files, imageFolders: 1, hintYear: hy, hintMonth: hm)
        }
        if albumGroups.count >= 1, loose.isEmpty {
            return albumGroups
        }
        if !albumGroups.isEmpty, !loose.isEmpty {
            // Mixed: albums + loose at root → albums + one UNKNOWN for loose
            var all = albumGroups
            if !loose.isEmpty {
                let (hy, hm) = dateHints(fromFolderName: name)
                all.append(SessionGroup(object: dsoName(stripVendorNoise(name)), files: loose, imageFolders: 1, hintYear: hy, hintMonth: hm))
            }
            return all
        }

        let files = imageFiles(under: captureRoot)
        guard !files.isEmpty else { return [] }
        let (hy, hm) = dateHints(fromFolderName: name)
        return [SessionGroup(object: dsoName(stripVendorNoise(name)), files: files, imageFolders: max(subDirs.count, 1), hintYear: hy, hintMonth: hm)]
    }

    /// DWARF: each top-level transfer is usually one session; object from folder name.
    private static func dwarfGroups(captureRoot: URL) -> [SessionGroup] {
        let name = captureRoot.lastPathComponent
        let files = imageFiles(under: captureRoot)
        guard !files.isEmpty else { return [] }
        let (hy, hm) = dateHints(fromFolderName: name)
        // Prefer a nested folder that looks like an object if the root is only a date stamp
        if looksLikeDateOnly(name) {
            let kids = (try? FileManager.default.contentsOfDirectory(
                at: captureRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            var nested: [SessionGroup] = []
            for kid in kids {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: kid.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let nestedFiles = imageFiles(under: kid)
                guard !nestedFiles.isEmpty else { continue }
                let object = dsoName(stripVendorNoise(kid.lastPathComponent))
                guard !object.isEmpty, !looksLikeDateOnly(kid.lastPathComponent) else { continue }
                nested.append(SessionGroup(object: object, files: nestedFiles, imageFolders: 1, hintYear: hy, hintMonth: hm))
            }
            if !nested.isEmpty { return nested }
        }
        return [SessionGroup(object: dsoName(stripVendorNoise(name)), files: files, imageFolders: 1, hintYear: hy, hintMonth: hm)]
    }

    private static func yearMonth(for group: SessionGroup, captureName: String, kind: TelescopeKind) -> (String, String) {
        if let y = group.hintYear, let m = group.hintMonth, y.count == 4, m.count == 2 {
            return (y, m)
        }
        let (hy, hm) = dateHints(fromFolderName: captureName)
        if let hy, let hm { return (hy, hm) }

        // Newest image mtime
        var newest = Date.distantPast
        for url in group.files {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if date > newest { newest = date }
        }
        if newest == .distantPast { newest = Date() }
        let cal = Calendar.current
        let y = String(cal.component(.year, from: newest))
        let m = String(format: "%02d", cal.component(.month, from: newest))
        _ = kind
        return (y, m)
    }

    private static func dateHints(fromFolderName name: String) -> (String?, String?) {
        if let match = firstMatch(leadingISODate, in: name) {
            return (substring(match.range(at: 1), in: name), substring(match.range(at: 2), in: name))
        }
        if let match = firstMatch(leadingCompactDate, in: name) {
            return (substring(match.range(at: 1), in: name), substring(match.range(at: 2), in: name))
        }
        if let match = firstMatch(originDatedObject, in: name) {
            return (substring(match.range(at: 2), in: name), substring(match.range(at: 3), in: name))
        }
        return (nil, nil)
    }

    private static func looksLikeDateOnly(_ name: String) -> Bool {
        if firstMatch(leadingCompactDate, in: name) != nil { return true }
        if firstMatch(leadingISODate, in: name) != nil,
           name.count <= 12 { return true }
        return false
    }

    private static func stripVendorNoise(_ raw: String) -> String {
        var s = raw
        let prefixes = ["seestar_", "seestar-", "dwarf_", "dwarf-", "dwarf3_", "origin_", "origin-"]
        let lower = s.lowercased()
        for p in prefixes where lower.hasPrefix(p) {
            s = String(s.dropFirst(p.count))
            break
        }
        // Drop trailing _stacked / _fit noise
        if let r = s.range(of: #"(?i)[_-](stacked|stack|fit|fits|tiff?)$"#, options: .regularExpression) {
            s.removeSubrange(r)
        }
        return s
    }

    // MARK: - Shared sort / backup / cleanup (unchanged behavior)

    static func preview(entries: [CaptureEntry]) -> (plans: [SortPlanItem], summary: SortSummary) {
        var plans: [SortPlanItem] = []
        var summary = SortSummary()
        summary.createTargets = Array(Set(entries.filter { !$0.targetExists }.map(\.year))).sorted()

        var bestByDestination: [String: (source: URL, destination: URL)] = [:]
        for entry in entries {
            for source in entry.sourceFiles {
                let destination = entry.targetDirectory.appendingPathComponent(source.lastPathComponent)
                let key = destination.standardizedFileURL.path
                if let existing = bestByDestination[key] {
                    let existingDate = (try? existing.source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let sourceDate = (try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    if sourceDate > existingDate {
                        bestByDestination[key] = (source, destination)
                    }
                } else {
                    bestByDestination[key] = (source, destination)
                }
            }
        }

        for item in bestByDestination.values.sorted(by: { $0.destination.path < $1.destination.path }) {
            let action: SortPlanItem.Action
            if FileManager.default.fileExists(atPath: item.destination.path) {
                let sourceDate = (try? item.source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let destDate = (try? item.destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                action = sourceDate > destDate ? .replace : .keep
            } else {
                action = .move
            }
            switch action {
            case .move: summary.move += 1
            case .replace: summary.replace += 1
            case .keep: summary.keep += 1
            }
            plans.append(SortPlanItem(source: item.source, destination: item.destination, action: action))
        }
        return (plans, summary)
    }

    @discardableResult
    static func createTargetsFolder(year: String, sourceRoot: URL = defaultSource) throws -> URL {
        guard year.range(of: #"^\d{4}$"#, options: .regularExpression) != nil else {
            throw NSError(domain: "SmartTelescopeSort", code: 1, userInfo: [NSLocalizedDescriptionKey: "A target year must be four digits."])
        }
        let target = sourceRoot.appendingPathComponent("Targets \(year)", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    static func performSort(entries: [CaptureEntry], sourceRoot: URL = defaultSource) throws -> SortSummary {
        let (plans, summary) = preview(entries: entries)
        for year in summary.createTargets {
            try createTargetsFolder(year: year, sourceRoot: sourceRoot)
        }
        var result = SortSummary(createTargets: summary.createTargets)
        let fm = FileManager.default
        for item in plans {
            try fm.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            switch item.action {
            case .keep:
                if fm.fileExists(atPath: item.source.path) {
                    try fm.removeItem(at: item.source)
                }
                result.keep += 1
            case .replace:
                _ = try fm.replaceItemAt(item.destination, withItemAt: item.source)
                result.replace += 1
            case .move:
                try fm.moveItem(at: item.source, to: item.destination)
                result.move += 1
            }
        }
        result.removedFolders = removeSpentCaptureFolders(
            captureNames: Array(Set(entries.map(\.captureFolder))),
            sourceRoot: sourceRoot.standardizedFileURL
        )
        return result
    }

    static func backupCaptureFolders(
        entries: [CaptureEntry],
        sourceRoot: URL,
        destinationParent: URL
    ) throws -> BackupSummary {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let folderName = "SmartTelescopeSort-Backup-\(stamp.string(from: Date()).replacingOccurrences(of: ":", with: "-"))"
        let destination = destinationParent.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        var folders = 0
        var files = 0
        let names = Array(Set(entries.map(\.captureFolder))).sorted()
        for name in names {
            if name.lowercased().hasPrefix("targets ") { continue }
            let source = sourceRoot.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let target = destination.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: source, to: target)
            folders += 1
            files += imageFiles(under: target).count
        }
        return BackupSummary(folders: folders, files: files, destination: destination)
    }

    @discardableResult
    static func removeSpentCaptureFolders(captureNames: [String], sourceRoot: URL) -> Int {
        let fm = FileManager.default
        var removed = 0
        for name in captureNames.sorted() {
            let lower = name.lowercased()
            if lower.hasPrefix("targets ") { continue }
            let capture = sourceRoot.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: capture.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if !imageFiles(under: capture).isEmpty { continue }
            do {
                try fm.removeItem(at: capture)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }

    // MARK: - Vaonis helpers

    private static func observationFolders(in captureFolder: URL) -> [(URL, String)] {
        var result: [(URL, String)] = []
        let captureName = captureFolder.lastPathComponent

        if let match = firstMatch(datedObservationCapture, in: captureName) {
            result.append((captureFolder, dsoName(substring(match.range(at: 1), in: captureName))))
        } else if let match = firstMatch(observation, in: captureName) {
            result.append((captureFolder, dsoName(substring(match.range(at: 1), in: captureName))))
        }

        guard let enumerator = FileManager.default.enumerator(
            at: captureFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let name = url.lastPathComponent
            if let match = firstMatch(observation, in: name) {
                result.append((url, dsoName(substring(match.range(at: 1), in: name))))
            }
        }
        return result
    }

    private static func imagesFolders(under observationFolder: URL) -> [URL] {
        var folders: [URL] = []
        let observationPath = observationFolder.standardizedFileURL.path

        guard let enumerator = FileManager.default.enumerator(
            at: observationFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let name = url.lastPathComponent
            if firstMatch(observation, in: name) != nil,
               url.deletingLastPathComponent().standardizedFileURL.path != observationPath {
                enumerator.skipDescendants()
                continue
            }
            if firstMatch(imagesFolder, in: name) != nil {
                folders.append(url)
            }
        }
        return folders.sorted { $0.path < $1.path }
    }

    private static func imageFiles(from imageFolders: [URL], alsoUnder observationFolder: URL) -> [URL] {
        if imageFolders.isEmpty {
            return imageFiles(under: observationFolder)
        }
        var files: [URL] = []
        for folder in imageFolders {
            files.append(contentsOf: imageFiles(under: folder))
        }
        return files
    }

    private static func imageFiles(under folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if imageExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func dedupeFiles(_ files: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [URL] = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            let key = file.standardizedFileURL.path
            if seen.insert(key).inserted {
                unique.append(file)
            }
        }
        return unique
    }

    private static func formats(of files: [URL]) -> [String] {
        guard !files.isEmpty else { return [] }
        return Array(Set(files.map { $0.pathExtension.uppercased() })).sorted()
    }

    private static func dsoName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .uppercased()
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func substring(_ range: NSRange, in text: String) -> String {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }
}
