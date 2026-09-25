import SwiftUI
import AppKit

@MainActor
final class SortViewModel: ObservableObject {
    @Published var telescopeKind: TelescopeKind {
        didSet {
            UserDefaults.standard.set(telescopeKind.rawValue, forKey: TelescopeKind.storageKey)
            refresh()
        }
    }
    @Published var sourcePath = CaptureSorter.defaultSource.path
    @Published var selectedYear = "all"
    @Published var selectedMonth = "all"
    @Published var years: [String] = []
    @Published var entries: [CaptureEntry] = []
    @Published var summary = SortSummary()
    @Published var status = "Ready — pick which smart telescope these Captures came from."
    @Published var sourceAvailable = false
    @Published var excluded = "Targets …"
    @Published var isBusy = false
    @Published var showCreateConfirm = false
    @Published var showSortConfirm = false
    @Published var showBackupOffer = false
    @Published var showPlanSheet = false
    @Published var planItems: [SortPlanItem] = []
    @Published var pendingCreateYear: String?

    let months: [(id: String, title: String)] = [
        ("all", "All months"),
        ("01", "January"), ("02", "February"), ("03", "March"),
        ("04", "April"), ("05", "May"), ("06", "June"),
        ("07", "July"), ("08", "August"), ("09", "September"),
        ("10", "October"), ("11", "November"), ("12", "December"),
    ]

    let lockedKind = TelescopeKind.lockedFromBundle

    init() {
        if let path = ProcessInfo.processInfo.environment["STS_CAPTURES"], !path.isEmpty {
            sourcePath = path
        }
        if let locked = TelescopeKind.lockedFromBundle {
            telescopeKind = locked
        } else if let raw = ProcessInfo.processInfo.environment["STS_KIND"],
                  let kind = TelescopeKind(rawValue: raw) {
            telescopeKind = kind
        } else if let raw = UserDefaults.standard.string(forKey: TelescopeKind.storageKey),
           let kind = TelescopeKind(rawValue: raw) {
            telescopeKind = kind
        } else {
            telescopeKind = .vaonis
        }
    }

    var missingYears: [String] {
        Array(Set(entries.filter { !$0.targetExists }.map(\.year))).sorted()
    }

    var plannedCount: Int { summary.move + summary.replace }
    var actionableCount: Int { summary.move + summary.replace + summary.keep }

    var spentCaptureNames: [String] {
        let grouped = Dictionary(grouping: entries, by: \.captureFolder)
        return grouped.compactMap { name, rows in
            rows.allSatisfy { $0.files == 0 } ? name : nil
        }.sorted()
    }

    var canSortOrCleanup: Bool {
        actionableCount > 0 || !spentCaptureNames.isEmpty
    }

    func refresh() {
        isBusy = true
        defer { isBusy = false }
        let root = URL(fileURLWithPath: sourcePath)
        do {
            let year = selectedYear == "all" ? nil : selectedYear
            let month = selectedMonth == "all" ? nil : selectedMonth
            let result = try CaptureSorter.scan(
                kind: telescopeKind,
                sourceRoot: root,
                year: year,
                month: month
            )
            entries = result.entries
            years = result.years
            excluded = result.excluded
            sourceAvailable = FileManager.default.fileExists(atPath: root.path)
            let preview = CaptureSorter.preview(entries: entries)
            summary = preview.summary
            planItems = preview.plans
            status = sourceAvailable
                ? "Preview ready for \(telescopeKind.menuTitle) — no files have been moved."
                : "Source unavailable."
            if selectedYear != "all", !years.contains(selectedYear), let first = years.first {
                selectedYear = first
            }
        } catch {
            status = error.localizedDescription
            entries = []
            summary = SortSummary()
            planItems = []
        }
    }

    /// Opens the move/replace/keep list (does not move files).
    func reviewFilePlan() {
        refresh()
        if planItems.isEmpty, entries.isEmpty {
            status = "No plan yet — choose the matching telescope type and a Captures folder that holds that brand’s sessions, then try again."
            return
        }
        showPlanSheet = true
    }

    func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: sourcePath)
        panel.message = telescopeKind.chooseFolderMessage
        if panel.runModal() == .OK, let url = panel.url {
            sourcePath = url.path
            refresh()
        }
    }

    func createMissingTarget() {
        guard let year = pendingCreateYear ?? missingYears.first else { return }
        do {
            let created = try CaptureSorter.createTargetsFolder(
                year: year,
                sourceRoot: URL(fileURLWithPath: sourcePath)
            )
            status = "Created \(created.path). No capture files were moved."
            refresh()
        } catch {
            status = error.localizedDescription
        }
    }

    func beginSortFlow() {
        guard canSortOrCleanup else { return }
        showBackupOffer = true
    }

    func chooseBackupLocationAndRun() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Backup Folder"
        panel.message = "Choose where to copy the capture folders before sorting."
        panel.directoryURL = URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else {
            status = "Backup cancelled — nothing was moved."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try CaptureSorter.backupCaptureFolders(
                entries: entries,
                sourceRoot: URL(fileURLWithPath: sourcePath),
                destinationParent: url
            )
            status = "Backup complete: \(result.folders) folders (\(result.files) TIFF/FITS) → \(result.destination.path)"
            showSortConfirm = true
        } catch {
            status = "Backup failed: \(error.localizedDescription)"
        }
    }

    func performSort() {
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try CaptureSorter.performSort(
                entries: entries,
                sourceRoot: URL(fileURLWithPath: sourcePath)
            )
            status = "Sort complete: \(result.move) moved, \(result.replace) replaced, \(result.keep) source duplicates cleared, \(result.removedFolders) capture folders removed."
            refresh()
        } catch {
            status = error.localizedDescription
        }
    }

    func openUserManual() {
        if let url = Bundle.main.url(forResource: "Smart-Telescope-Sort-User-Manual", withExtension: "pdf") {
            NSWorkspace.shared.open(url)
            return
        }
        let fallback = URL(fileURLWithPath: "/Volumes/Large Drive/Smart Telescope Sort program/App/Resources/Smart-Telescope-Sort-User-Manual.pdf")
        if FileManager.default.fileExists(atPath: fallback.path) {
            NSWorkspace.shared.open(fallback)
        } else {
            status = "User manual PDF was not found in the app bundle."
        }
    }
}

struct ContentView: View {
    @StateObject private var model = SortViewModel()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            workspace
        }
        .background(Color(red: 0.02, green: 0.04, blue: 0.08))
        .foregroundStyle(Color(red: 0.92, green: 0.94, blue: 1.0))
        .onAppear { model.refresh() }
        .confirmationDialog(
            "Create Targets folder?",
            isPresented: $model.showCreateConfirm,
            titleVisibility: .visible
        ) {
            Button("Create Targets \(model.pendingCreateYear ?? "")") {
                model.createMissingTarget()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create Targets \(model.pendingCreateYear ?? "") under your Captures folder? No files will be moved.")
        }
        .confirmationDialog(
            "Back up before sorting?",
            isPresented: $model.showBackupOffer,
            titleVisibility: .visible
        ) {
            Button("Back up first…") {
                model.chooseBackupLocationAndRun()
            }
            Button("Sort without backup", role: .destructive) {
                model.showSortConfirm = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Recommended: copy the capture folders to a backup location first.")
        }
        .confirmationDialog(
            "Sort eligible files?",
            isPresented: $model.showSortConfirm,
            titleVisibility: .visible
        ) {
            Button("Sort now", role: .destructive) {
                model.performSort()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if model.actionableCount == 0 {
                Text("No TIFF/FITS left to move. Delete \(model.spentCaptureNames.count) emptied capture folder(s) at the Captures root?")
            } else if model.plannedCount == 0, model.summary.keep > 0 {
                Text("All \(model.summary.keep) files already exist in Targets (same or newer). Sort will remove the source duplicates and delete emptied capture folders.")
            } else {
                Text("Move \(model.summary.move) new files, replace \(model.summary.replace) older destination files, and clear \(model.summary.keep) source duplicates. Emptied capture folders will be deleted.")
            }
        }
        .sheet(isPresented: $model.showPlanSheet) {
            PlanReviewSheet(items: model.planItems, summary: model.summary, telescope: model.telescopeKind.menuTitle)
        }
    }

    private struct PlanReviewSheet: View {
        let items: [SortPlanItem]
        let summary: SortSummary
        let telescope: String
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("File plan").font(.title2.bold())
                        Text(telescope)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                Text("\(summary.move) move · \(summary.replace) replace · \(summary.keep) keep  —  \(items.count) files. Nothing has been moved yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if items.isEmpty {
                    Text("No TIFF/FITS actions in this preview. Check telescope type and Source Captures path.")
                        .padding(.top, 24)
                    Spacer()
                } else {
                    Table(items) {
                        TableColumn("Action") { (item: SortPlanItem) in
                            Text(item.action.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                        .width(70)
                        TableColumn("From") { (item: SortPlanItem) in
                            Text(item.source.path)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(2)
                        }
                        TableColumn("To") { (item: SortPlanItem) in
                            Text(item.destination.path)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(2)
                        }
                    }
                    .frame(minHeight: 360)
                }
            }
            .padding(20)
            .frame(minWidth: 720, minHeight: 480)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 0.44, green: 0.60, blue: 1.0), lineWidth: 1)
                        .frame(width: 38, height: 38)
                    Image(systemName: "sparkles.telescope")
                        .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1.0))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Telescope\nSort")
                        .font(.system(size: 17, weight: .bold))
                        .lineSpacing(-2)
                    Text(model.lockedKind == nil
                         ? "Multi-brand Captures → Targets"
                         : "Independent app. Not affiliated with telescope makers.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.58, green: 0.65, blue: 0.78))
                }
            }
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("TELESCOPE TYPE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(Color(red: 0.51, green: 0.58, blue: 0.71))
                if model.lockedKind == nil {
                    Picker("Telescope", selection: $model.telescopeKind) {
                        ForEach(TelescopeKind.allCases) { kind in
                            Text(kind.menuTitle).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text(model.telescopeKind.layoutTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.telescopeKind.compatibilityNote)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.78, green: 0.84, blue: 0.94))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.lockedKind == nil {
                    Text(model.telescopeKind.compatibilityNote)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.78, green: 0.84, blue: 0.94))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(TelescopeKind.notAffiliated)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.78, green: 0.84, blue: 0.94))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(model.telescopeKind.dropHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.72, green: 0.78, blue: 0.90))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.20, blue: 0.36).opacity(0.75))
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("HOW IT WORKS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(Color(red: 0.51, green: 0.58, blue: 0.71))
                ForEach(Array(model.telescopeKind.howItWorksLines.enumerated()), id: \.offset) { _, line in
                    infoLine(icon: line.icon, text: line.text)
                }
                infoLine(icon: "externaldrive", text: "Optional backup copies capture folders before anything moves.")
                infoLine(icon: "trash", text: "When a capture has no TIFF/FITS left, that folder is deleted at the Captures root.")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.16, blue: 0.30).opacity(0.55))
            )

            Spacer()
            Button {
                model.openUserManual()
            } label: {
                Label("Open user manual (PDF)", systemImage: "book.pages")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1.0))
            Button {
                NSWorkspace.shared.open(BigSkyAstroWebLinks.observationPlanner)
            } label: {
                Label("Astronomy Observation Planner", systemImage: "macwindow")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1.0))
            Button {
                NSWorkspace.shared.open(BigSkyAstroWebLinks.telescopePlanner)
            } label: {
                Label("Smart Telescope Planner", systemImage: "iphone")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1.0))
            Text("Nothing moves until you press Sort eligible files.")
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.58, green: 0.65, blue: 0.78))
        }
        .padding(24)
        .frame(width: 290, alignment: .topLeading)
        .background(Color(red: 0.05, green: 0.09, blue: 0.18))
    }

    private func infoLine(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1.0))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.72, green: 0.78, blue: 0.90))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CAPTURE LIBRARY")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Color(red: 0.51, green: 0.58, blue: 0.71))
                    Text("Ready to review").font(.system(size: 24, weight: .bold))
                    Text(model.telescopeKind.menuTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1.0))
                }
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(model.sourceAvailable ? Color.green : Color.orange).frame(width: 7, height: 7)
                    Text(model.sourceAvailable ? "Source available" : "Source unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(model.sourceAvailable ? Color.green : Color.orange)
                }
            }

            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color(red: 0.45, green: 0.62, blue: 1.0))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SOURCE CAPTURES")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color(red: 0.51, green: 0.58, blue: 0.71))
                    Text(model.sourcePath)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                Spacer()
                Button("…") { model.chooseSourceFolder() }
                    .buttonStyle(.bordered)
                Text("\(model.excluded) skipped as sources.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.90, green: 0.70, blue: 0.35))
            }
            .padding(.vertical, 8)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DESTINATION").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color(red: 0.51, green: 0.58, blue: 0.71))
                    Text("Choose a year and month").font(.system(size: 16, weight: .semibold))
                    Text("Objects decode into Targets {year}/{DSO} for the selected telescope type.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.58, green: 0.65, blue: 0.78))
                }
                Spacer()
                Picker("Year", selection: $model.selectedYear) {
                    Text("All years").tag("all")
                    ForEach(model.years, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 120)
                .onChange(of: model.selectedYear) { _, _ in model.refresh() }

                Picker("Month", selection: $model.selectedMonth) {
                    ForEach(model.months, id: \.id) { Text($0.title).tag($0.id) }
                }
                .frame(width: 140)
                .onChange(of: model.selectedMonth) { _, _ in model.refresh() }

                Button("Refresh preview") { model.refresh() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.30, green: 0.48, blue: 0.95))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.15, blue: 0.28).opacity(0.8))
            )

            if let year = model.missingYears.first {
                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Targets \(year) does not exist yet.").font(.system(size: 12, weight: .semibold))
                        Text("Create the matching target folder before sorting.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.72, green: 0.64, blue: 0.49))
                    }
                    Spacer()
                    Button("Create Targets \(year)") {
                        model.pendingCreateYear = year
                        model.showCreateConfirm = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.orange.opacity(0.4))
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                )
            }

            table
            stats
            planBar
            footer
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.04, green: 0.07, blue: 0.14))
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(model.entries.count) capture rows found")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.90, green: 0.93, blue: 1.0))
                Spacer()
                Text("Destination shows where TIFF/FITS files will move")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.70, green: 0.76, blue: 0.88))
            }
            Table(model.entries) {
                TableColumn("Capture folder") { (entry: CaptureEntry) in
                    Text(entry.captureFolder)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(tableInk)
                        .lineLimit(1)
                }
                .width(min: 180, ideal: 240)
                TableColumn("Year") { Text($0.year).foregroundStyle(tableInk) }.width(50)
                TableColumn("Month") { Text($0.month).foregroundStyle(tableInk) }.width(50)
                TableColumn("DSO object") {
                    Text($0.object).fontWeight(.semibold).foregroundStyle(tableInk)
                }
                .width(120)
                TableColumn("Img folders") { Text("\($0.imageFolders)").foregroundStyle(tableInk) }.width(70)
                TableColumn("Files") { Text("\($0.files)").foregroundStyle(tableInk) }.width(50)
                TableColumn("Formats") {
                    Text($0.formats.joined(separator: ", ")).foregroundStyle(tableInk)
                }
                .width(90)
                TableColumn("Destination") { (entry: CaptureEntry) in
                    Text("Targets \(entry.year)/\(entry.object)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tableDestination)
                        .help(entry.targetDirectory.path)
                }
                .width(min: 160, ideal: 200)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .foregroundStyle(tableInk)
            .colorScheme(.light)
            .frame(minHeight: 240)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var tableInk: Color { Color(red: 0.08, green: 0.12, blue: 0.22) }
    private var tableDestination: Color { Color(red: 0.10, green: 0.28, blue: 0.62) }

    private var stats: some View {
        HStack(spacing: 18) {
            stat(value: "\(model.entries.count)", label: "folders ready to inspect")
            stat(value: "\(model.entries.reduce(0) { $0 + $1.files })", label: "TIFF / FITS capture files")
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(Color(red: 0.59, green: 0.68, blue: 1.0))
                Text("Replace only when newer.\nExisting target files are kept unless the source is newer.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.56, green: 0.63, blue: 0.78))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }

    private func stat(value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Text(value).font(.system(size: 18, weight: .bold))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 0.56, green: 0.63, blue: 0.78))
        }
    }

    private var planBar: some View {
        HStack {
            if model.actionableCount == 0, !model.spentCaptureNames.isEmpty {
                Text("\(model.spentCaptureNames.count) emptied capture folder(s) ready to delete at the Captures root.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.68, green: 0.74, blue: 0.88))
            } else if model.plannedCount == 0, model.summary.keep > 0 {
                Text("\(model.summary.keep) already in Targets — Sort clears source duplicates and removes emptied capture folders.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.68, green: 0.74, blue: 0.88))
            } else {
                Text("\(model.plannedCount) files eligible: \(model.summary.move) new moves, \(model.summary.replace) newer replacements, \(model.summary.keep) source duplicates to clear.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.68, green: 0.74, blue: 0.88))
            }
            Spacer()
            Button("Review file plan") { model.reviewFilePlan() }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.30, green: 0.48, blue: 0.95))
                .disabled(model.isBusy || (model.planItems.isEmpty && model.entries.isEmpty))
            Button(model.actionableCount == 0 && !model.spentCaptureNames.isEmpty ? "Remove empty captures" : "Sort eligible files") {
                model.beginSortFlow()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.30, green: 0.48, blue: 0.95))
            .disabled(!model.canSortOrCleanup || model.isBusy)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.15, green: 0.22, blue: 0.40).opacity(0.55))
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            Text(model.status)
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.51, green: 0.58, blue: 0.71))
            Spacer()
        }
        .padding(.top, 4)
    }
}
