import Cocoa
import Foundation

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: OrganizerWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = OrganizerWindowController()
        self.controller = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

enum FileCategory: String, CaseIterable, Codable, Hashable {
    case documents, spreadsheets, presentations, images, videos, audio, archives, installers, code, other

    var displayName: String {
        switch self {
        case .documents: return "Documents"
        case .spreadsheets: return "Spreadsheets"
        case .presentations: return "Presentations"
        case .images: return "Images"
        case .videos: return "Videos"
        case .audio: return "Audio"
        case .archives: return "Archives"
        case .installers: return "Installers"
        case .code: return "Code"
        case .other: return "Other"
        }
    }

    static func category(for url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        if ["pdf", "doc", "docx", "rtf", "txt", "md", "odt", "pages", "epub", "tex"].contains(ext) { return .documents }
        if ["xls", "xlsx", "csv", "tsv", "ods", "numbers"].contains(ext) { return .spreadsheets }
        if ["ppt", "pptx", "key", "odp"].contains(ext) { return .presentations }
        if ["jpg", "jpeg", "png", "gif", "heic", "webp", "tif", "tiff", "svg", "raw", "dng", "cr2", "nef"].contains(ext) { return .images }
        if ["mp4", "mov", "avi", "mkv", "webm", "m4v", "mpg", "mpeg"].contains(ext) { return .videos }
        if ["mp3", "wav", "aiff", "flac", "m4a", "aac", "ogg"].contains(ext) { return .audio }
        if ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "iso"].contains(ext) { return .archives }
        if ["dmg", "pkg", "msi"].contains(ext) { return .installers }
        if ["swift", "py", "r", "js", "ts", "jsx", "tsx", "html", "css", "scss", "json", "yaml", "yml", "xml", "sh", "bash", "zsh", "fish", "ipynb", "sql", "java", "c", "cpp", "h", "go", "rs", "rb", "php"].contains(ext) { return .code }
        return .other
    }
}

struct PreviewItem {
    let source: URL
    let destination: URL
    let category: FileCategory
    let modified: Date
    let size: Int64

    var fileName: String { source.lastPathComponent }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    var modifiedText: String { "Modified " + RelativeDateTimeFormatter().localizedString(for: modified, relativeTo: Date()) }
    var destinationText: String {
        let parent = destination.deletingLastPathComponent()
        return parent.lastPathComponent + "/" + destination.lastPathComponent
    }
}

struct ActivityRecord: Codable {
    let fileName: String
    let destination: String
    let date: Date
}

final class OrganizerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private var sourceFolder: URL
    private var previewItems: [PreviewItem] = []
    private var activityRecords: [ActivityRecord] = []
    private var lastRun: [(source: URL, destination: URL)] = []
    private var watchTimer: Timer?
    private var isWorking = false

    private let sourcePathLabel = NSTextField(labelWithString: "")
    private let previewTitleLabel = NSTextField(labelWithString: "Preview")
    private let previewDetailLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Ready to scan")
    private let organizeButton = NSButton(title: "Organize Files", target: nil, action: nil)
    private let undoButton = NSButton(title: "Undo Last Run", target: nil, action: nil)
    private let tableView = NSTableView()

    private let sortTypeCheck = NSButton(checkboxWithTitle: "Sort by file type", target: nil, action: nil)
    private let sortDateCheck = NSButton(checkboxWithTitle: "Sort by date", target: nil, action: nil)
    private let codeCheck = NSButton(checkboxWithTitle: "Include code files", target: nil, action: nil)
    private let recentCheck = NSButton(checkboxWithTitle: "Skip recently modified files", target: nil, action: nil)
    private let watchCheck = NSButton(checkboxWithTitle: "Watch Downloads", target: nil, action: nil)
    private let intervalPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private var sortByType: Bool { sortTypeCheck.state == .on }
    private var sortByDate: Bool { sortDateCheck.state == .on }
    private var includeCodeFiles: Bool { codeCheck.state == .on }
    private var skipRecentFiles: Bool { recentCheck.state == .on }
    private var watchEnabled: Bool { watchCheck.state == .on }
    private var watchInterval: TimeInterval { [60.0, 300.0, 900.0][max(0, intervalPopup.indexOfSelectedItem)] }
    private var organizedRoot: URL { sourceFolder.appendingPathComponent("Organized", isDirectory: true) }

    init() {
        let defaultDownloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        let storedPath = UserDefaults.standard.string(forKey: "sourceFolderPath")
        self.sourceFolder = storedPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultDownloads
        super.init(window: nil)
        loadActivityHistory()
        buildWindow()
        loadSettings()
        refreshPreview()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { watchTimer?.invalidate() }

    private func buildWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 1050, height: 720)
        let appWindow = NSWindow(contentRect: contentRect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        appWindow.title = "Downloads Organizer"
        appWindow.center()
        appWindow.minSize = NSSize(width: 920, height: 620)
        appWindow.titlebarAppearsTransparent = true
        appWindow.isMovableByWindowBackground = true
        window = appWindow

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        appWindow.contentView = content

        let header = makeHeader()
        let separator = NSBox()
        separator.boxType = .separator
        let leftPanel = makeLeftPanel()
        let rightPanel = makeRightPanel()

        [header, separator, leftPanel, rightPanel].forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 15),
            header.heightAnchor.constraint(equalToConstant: 60),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            leftPanel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            leftPanel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 20),
            leftPanel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
            leftPanel.widthAnchor.constraint(equalToConstant: 285),
            rightPanel.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: 24),
            rightPanel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            rightPanel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 20),
            rightPanel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22)
        ])
    }

    private func makeHeader() -> NSView {
        let container = NSView()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Downloads Organizer")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        icon.contentTintColor = .systemBlue
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Downloads Organizer")
        title.font = .systemFont(ofSize: 21, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let subtitle = NSTextField(labelWithString: "A safer home for a less chaotic Downloads folder")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let activity = NSButton(title: "Activity", target: self, action: #selector(showActivity))
        activity.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        activity.bezelStyle = .texturedRounded
        activity.translatesAutoresizingMaskIntoConstraints = false
        let scan = NSButton(title: "Scan Now", target: self, action: #selector(refreshPreview))
        scan.bezelStyle = .texturedRounded
        scan.translatesAutoresizingMaskIntoConstraints = false

        [icon, title, subtitle, activity, scan].forEach(container.addSubview)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 42),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 11),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            activity.trailingAnchor.constraint(equalTo: scan.leadingAnchor, constant: -10),
            activity.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            scan.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scan.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func makeLeftPanel() -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor, constant: -14).isActive = true

        let sourceCaption = makeCaption("SOURCE FOLDER")
        let folderButton = NSButton(title: "Choose Folder…", target: self, action: #selector(chooseSourceFolder))
        folderButton.bezelStyle = .rounded
        sourcePathLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        sourcePathLabel.textColor = .secondaryLabelColor
        sourcePathLabel.lineBreakMode = .byTruncatingMiddle
        sourcePathLabel.maximumNumberOfLines = 2
        sourcePathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let organizationCaption = makeCaption("ORGANIZATION")
        configureCheckButton(sortTypeCheck, action: #selector(settingsChanged))
        configureCheckButton(sortDateCheck, action: #selector(settingsChanged))
        configureCheckButton(codeCheck, action: #selector(settingsChanged))
        configureCheckButton(recentCheck, action: #selector(settingsChanged))
        recentCheck.toolTip = "Files changed in the last two minutes may still be downloading or saving."

        let watchCaption = makeCaption("AUTOMATION")
        configureCheckButton(watchCheck, action: #selector(watchChanged))
        intervalPopup.addItems(withTitles: ["Every 1 minute", "Every 5 minutes", "Every 15 minutes"])
        intervalPopup.target = self
        intervalPopup.action = #selector(watchChanged)
        intervalPopup.font = .systemFont(ofSize: 12)

        let safetyCaption = makeCaption("SAFETY")
        let safetyText = makeWrappedLabel("Preview first, then move. Folders, hidden items, partial downloads, and recent files are left in place. Existing files are never overwritten.", size: 11.5)
        safetyText.textColor = .secondaryLabelColor
        let destinationText = makeWrappedLabel("Destination: Organized/Category/Year/Month", size: 11.5)
        destinationText.textColor = .secondaryLabelColor

        let leftDivider = NSBox()
        leftDivider.boxType = .separator
        let undo = undoButton
        undo.target = self
        undo.action = #selector(undoLastRun)
        undo.bezelStyle = .rounded
        undo.isEnabled = false

        [sourceCaption, folderButton, sourcePathLabel, spacer(8), organizationCaption, sortTypeCheck, sortDateCheck, codeCheck, recentCheck, spacer(8), watchCaption, watchCheck, intervalPopup, spacer(8), safetyCaption, safetyText, destinationText, spacer(8), leftDivider, spacer(5), undo].forEach { stack.addArrangedSubview($0) }
        return scroll
    }

    private func makeRightPanel() -> NSView {
        let container = NSView()
        let title = previewTitleLabel
        title.font = .systemFont(ofSize: 19, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let detail = previewDetailLabel
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.translatesAutoresizingMaskIntoConstraints = false

        organizeButton.target = self
        organizeButton.action = #selector(organizePreviewedFiles)
        organizeButton.bezelStyle = .rounded
        organizeButton.isEnabled = false
        organizeButton.translatesAutoresizingMaskIntoConstraints = false

        let tableScroll = makeTable()
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let safety = NSTextField(labelWithString: "Safe moves  •  One-run undo  •  Local-only")
        safety.font = .systemFont(ofSize: 11.5)
        safety.textColor = .tertiaryLabelColor
        safety.translatesAutoresizingMaskIntoConstraints = false

        [title, detail, organizeButton, tableScroll, statusLabel, safety].forEach(container.addSubview)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            title.topAnchor.constraint(equalTo: container.topAnchor),
            detail.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            organizeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            organizeButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            tableScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tableScroll.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 16),
            tableScroll.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -14),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: safety.leadingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            safety.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            safety.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeTable() -> NSScrollView {
        let columns: [(String, String, CGFloat)] = [("name", "FILE", 220), ("category", "CATEGORY", 105), ("destination", "DESTINATION", 260), ("size", "SIZE", 70)]
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 38
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.delegate = self
        tableView.dataSource = self
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = id == "name" ? 160 : 70
            tableView.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder
        return scroll
    }

    private func configureCheckButton(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.setButtonType(.switch)
        button.font = .systemFont(ofSize: 13)
    }

    private func makeCaption(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: 10.5, weight: .bold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeWrappedLabel(_ string: String, size: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = .systemFont(ofSize: size)
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func loadSettings() {
        sortTypeCheck.state = defaults.object(forKey: "sortByType") as? Bool ?? true ? .on : .off
        sortDateCheck.state = defaults.object(forKey: "sortByDate") as? Bool ?? true ? .on : .off
        codeCheck.state = defaults.object(forKey: "includeCodeFiles") as? Bool ?? true ? .on : .off
        recentCheck.state = defaults.object(forKey: "skipRecentFiles") as? Bool ?? true ? .on : .off
        watchCheck.state = defaults.object(forKey: "watchEnabled") as? Bool ?? false ? .on : .off
        let interval = defaults.object(forKey: "watchInterval") as? Double ?? 300
        intervalPopup.selectItem(at: interval == 60 ? 0 : interval == 900 ? 2 : 1)
        sourcePathLabel.stringValue = sourceFolder.path
        intervalPopup.isEnabled = watchEnabled
        configureWatchTimer()
    }

    @objc private func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose folder to organize"
        panel.message = "Select a folder, typically Downloads. Files will be moved into an Organized subfolder."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = sourceFolder
        if panel.runModal() == .OK, let url = panel.url {
            sourceFolder = url
            sourcePathLabel.stringValue = url.path
            defaults.set(url.path, forKey: "sourceFolderPath")
            refreshPreview()
        }
    }

    @objc private func settingsChanged() {
        persistSettings()
        refreshPreview()
    }

    @objc private func watchChanged() {
        persistSettings()
        intervalPopup.isEnabled = watchEnabled
        configureWatchTimer()
    }

    @objc private func refreshPreview() {
        guard !isWorking else { return }
        isWorking = true
        setStatus("Scanning \(sourceFolder.lastPathComponent)…", error: false)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.makePreview()
            DispatchQueue.main.async {
                self.previewItems = result.items
                self.tableView.reloadData()
                self.organizeButton.title = result.items.isEmpty ? "Nothing to Organize" : "Organize \(result.items.count) File\(result.items.count == 1 ? "" : "s")"
                self.organizeButton.isEnabled = !result.items.isEmpty
                self.previewDetailLabel.stringValue = result.items.isEmpty ? "No eligible files to move at the moment" : "\(result.items.count) file\(result.items.count == 1 ? "" : "s") ready for review"
                self.setStatus(result.message, error: result.isError)
                self.isWorking = false
            }
        }
    }

    @objc private func organizePreviewedFiles() {
        let items = previewItems
        guard !items.isEmpty, !isWorking else { return }
        let alert = NSAlert()
        alert.messageText = "Organize \(items.count) file\(items.count == 1 ? "" : "s")?"
        alert.informativeText = "Files will be moved into \(organizedRoot.path). Existing items will not be overwritten, and you can undo this run while the app remains open."
        alert.addButton(withTitle: "Organize")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isWorking = true
        setStatus("Moving \(items.count) files…", error: false)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var moved: [(URL, URL)] = []
            var records: [ActivityRecord] = []
            var failures = 0
            for item in items {
                do {
                    let destination = self.availableDestination(for: item.destination)
                    try self.fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try self.fileManager.moveItem(at: item.source, to: destination)
                    moved.append((item.source, destination))
                    records.append(ActivityRecord(fileName: item.fileName, destination: destination.path, date: Date()))
                } catch { failures += 1 }
            }
            DispatchQueue.main.async {
                self.lastRun = moved
                self.undoButton.isEnabled = !moved.isEmpty
                self.activityRecords = Array((records + self.activityRecords).prefix(200))
                self.saveActivityHistory()
                self.isWorking = false
                if moved.isEmpty {
                    self.setStatus("No files moved. Check folder access permissions.", error: true)
                    self.showAccessAlert()
                } else {
                    self.setStatus(failures == 0 ? "Moved \(moved.count) file\(moved.count == 1 ? "" : "s") safely." : "Moved \(moved.count), skipped \(failures).", error: failures > 0)
                }
                self.refreshPreview()
            }
        }
    }

    @objc private func undoLastRun() {
        guard !lastRun.isEmpty, !isWorking else { return }
        isWorking = true
        setStatus("Undoing last run…", error: false)
        let moves = lastRun.reversed()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var restored = 0
            var remaining: [(URL, URL)] = []
            for (source, destination) in moves {
                do {
                    guard self.fileManager.fileExists(atPath: destination.path), !self.fileManager.fileExists(atPath: source.path) else {
                        remaining.append((source, destination)); continue
                    }
                    try self.fileManager.moveItem(at: destination, to: source)
                    restored += 1
                } catch { remaining.append((source, destination)) }
            }
            DispatchQueue.main.async {
                self.lastRun = remaining.reversed()
                self.undoButton.isEnabled = !self.lastRun.isEmpty
                self.isWorking = false
                self.setStatus(restored > 0 ? "Restored \(restored) file\(restored == 1 ? "" : "s")." : "No files could be restored.", error: restored == 0)
                self.refreshPreview()
            }
        }
    }

    @objc private func showActivity() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Activity"
        panel.center()
        let scroll = NSScrollView(frame: panel.contentView!.bounds.insetBy(dx: 20, dy: 20))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textColor = .labelColor
        if activityRecords.isEmpty {
            text.string = "No activity yet. Organized file moves will appear here."
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            text.string = activityRecords.map { "\(formatter.string(from: $0.date))  \($0.fileName)\n    → \($0.destination)" }.joined(separator: "\n\n")
        }
        scroll.documentView = text
        panel.contentView?.addSubview(scroll)
        window?.beginSheet(panel)
    }

    private func configureWatchTimer() {
        watchTimer?.invalidate()
        watchTimer = nil
        guard watchEnabled else { return }
        watchTimer = Timer.scheduledTimer(timeInterval: watchInterval, target: self, selector: #selector(watchTick), userInfo: nil, repeats: true)
        if let watchTimer { RunLoop.main.add(watchTimer, forMode: .common) }
        setStatus("Watching every \(Int(watchInterval / 60)) minute\(watchInterval == 60 ? "" : "s").", error: false)
    }

    @objc private func watchTick() {
        guard !isWorking else { return }
        refreshPreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.watchEnabled, !self.previewItems.isEmpty, !self.isWorking else { return }
            self.moveWithoutConfirmation()
        }
    }

    private func moveWithoutConfirmation() {
        let items = previewItems
        guard !items.isEmpty else { return }
        isWorking = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var moved: [(URL, URL)] = []
            var records: [ActivityRecord] = []
            for item in items {
                do {
                    let destination = self.availableDestination(for: item.destination)
                    try self.fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try self.fileManager.moveItem(at: item.source, to: destination)
                    moved.append((item.source, destination))
                    records.append(ActivityRecord(fileName: item.fileName, destination: destination.path, date: Date()))
                } catch { continue }
            }
            DispatchQueue.main.async {
                if !moved.isEmpty {
                    self.lastRun = moved
                    self.undoButton.isEnabled = true
                    self.activityRecords = Array((records + self.activityRecords).prefix(200))
                    self.saveActivityHistory()
                    self.setStatus("Watch mode moved \(moved.count) file\(moved.count == 1 ? "" : "s").", error: false)
                }
                self.isWorking = false
                self.refreshPreview()
            }
        }
    }

    private func makePreview() -> (items: [PreviewItem], message: String, isError: Bool) {
        do {
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey]
            let contents = try fileManager.contentsOfDirectory(at: sourceFolder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            let now = Date()
            let items = contents.compactMap { url -> PreviewItem? in
                guard url.deletingLastPathComponent() == sourceFolder else { return nil }
                let values = try? url.resourceValues(forKeys: keys)
                guard values?.isDirectory != true, values?.isHidden != true else { return nil }
                let fileName = url.lastPathComponent.lowercased()
                let extensionName = url.pathExtension.lowercased()
                guard !fileName.hasPrefix("."), !["crdownload", "download", "part", "partial", "tmp"].contains(extensionName) else { return nil }
                let modified = values?.contentModificationDate ?? now
                if skipRecentFiles && now.timeIntervalSince(modified) < 120 { return nil }
                let category = FileCategory.category(for: url)
                if category == .code && !includeCodeFiles { return nil }
                let destination = destinationFor(url: url, category: category, modified: modified)
                return PreviewItem(source: url, destination: destination, category: category, modified: modified, size: Int64(values?.fileSize ?? 0))
            }.sorted { $0.modified > $1.modified }
            return (items, items.isEmpty ? "No eligible files found" : "Review planned moves before organizing", false)
        } catch {
            return ([], "Could not read \(sourceFolder.path).", true)
        }
    }

    private func destinationFor(url: URL, category: FileCategory, modified: Date) -> URL {
        var folder = organizedRoot
        if sortByType { folder.appendPathComponent(category.displayName, isDirectory: true) }
        if sortByDate {
            let calendar = Calendar.current
            let year = calendar.component(.year, from: modified)
            let monthNumber = calendar.component(.month, from: modified)
            let month = DateFormatter().monthSymbols[monthNumber - 1]
            folder.appendPathComponent(String(year), isDirectory: true)
            folder.appendPathComponent(String(format: "%02d-%@", monthNumber, month), isDirectory: true)
        }
        return folder.appendingPathComponent(url.lastPathComponent)
    }

    private func availableDestination(for proposed: URL) -> URL {
        guard fileManager.fileExists(atPath: proposed.path) else { return proposed }
        let directory = proposed.deletingLastPathComponent()
        let ext = proposed.pathExtension
        let stem = proposed.deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let name = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private func setStatus(_ string: String, error: Bool) {
        statusLabel.stringValue = string
        statusLabel.textColor = error ? .systemRed : .secondaryLabelColor
    }

    private func showAccessAlert() {
        let alert = NSAlert()
        alert.messageText = "Folder access needed"
        alert.informativeText = "Choose the Downloads folder again, or grant the app Files and Folders access in System Settings > Privacy & Security."
        alert.addButton(withTitle: "Choose Folder")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn { chooseSourceFolder() }
    }

    private func persistSettings() {
        defaults.set(sortByType, forKey: "sortByType")
        defaults.set(sortByDate, forKey: "sortByDate")
        defaults.set(includeCodeFiles, forKey: "includeCodeFiles")
        defaults.set(skipRecentFiles, forKey: "skipRecentFiles")
        defaults.set(watchEnabled, forKey: "watchEnabled")
        defaults.set(watchInterval, forKey: "watchInterval")
    }

    private func loadActivityHistory() {
        guard let data = defaults.data(forKey: "activityRecords"), let records = try? JSONDecoder().decode([ActivityRecord].self, from: data) else { return }
        activityRecords = records
    }

    private func saveActivityHistory() {
        guard let data = try? JSONEncoder().encode(activityRecords) else { return }
        defaults.set(data, forKey: "activityRecords")
    }

    func numberOfRows(in tableView: NSTableView) -> Int { previewItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let item = previewItems[row]
        let identifier = tableColumn.identifier.rawValue
        let text: String
        switch identifier {
        case "name": text = item.fileName
        case "category": text = item.category.displayName
        case "destination": text = item.destinationText
        case "size": text = item.sizeText
        default: text = ""
        }
        let cell = NSTextField(labelWithString: text)
        cell.font = identifier == "destination" ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 12)
        cell.textColor = identifier == "destination" || identifier == "size" ? .secondaryLabelColor : .labelColor
        cell.lineBreakMode = .byTruncatingMiddle
        cell.maximumNumberOfLines = 1
        return cell
    }
}
