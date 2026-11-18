import AppKit

@MainActor
private final class ScriptPanel: NSPanel {
    var editing = false
    override var canBecomeKey: Bool { editing }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ScriptTextView: NSTextView {
    override var needsPanelToBecomeKey: Bool { isEditable }
}

@MainActor
private final class ScriptTitleField: NSTextField {
    override var needsPanelToBecomeKey: Bool { true }
}

@MainActor
final class Cuecard: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    private let storage: ScriptStorage
    private var library: ScriptLibrary
    private let loadFailure: Error?
    private var dirty = false
    private var saveTimer: Timer?
    private var sections: [ScriptSection] = []
    private var editing = false
    private var editingID: UUID?
    private var previousApp: NSRunningApplication?
    private var confirmingID: UUID?
    private var readerOffset: CGFloat = 0

    private lazy var status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = ScriptPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 570),
                                    styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
    private let scroll = ReadingScrollView()
    private let text = ScriptTextView(frame: .zero)
    private let picker = NSPopUpButton()
    private let sectionPicker = NSPopUpButton()
    private let manage = PanelButton()
    private let management = NSMenu()
    private let switchMode = PanelButton()
    private let titleField = ScriptTitleField(frame: .zero)
    private let markdownOption = NSButton(checkboxWithTitle: "Markdown", target: nil, action: nil)
    private let warning = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let speedLabel = NSTextField(labelWithString: "")
    private let clockLabel = NSTextField(labelWithString: "0:00")
    private let scrollButton = PanelButton()
    private let clockButton = PanelButton()
    private let resetButton = PanelButton()
    private let progress = ReadingProgress()
    private let scrollHint = NSTextField(labelWithString: "")
    private let speedControl = NSSlider(value: 20, minValue: 5, maxValue: 100, target: nil, action: nil)
    private var readerTools: NSStackView!
    private var editorTools: NSStackView!
    private var deleteTools: NSStackView!

    private var scrollTimer: Timer?
    private var scrollPosition: CGFloat = 0
    private var lastScrollTick: TimeInterval = 0
    private var clockTimer: Timer?
    private var clockStarted: TimeInterval?
    private var elapsed: TimeInterval = 0
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private var selection: Int? { library.scripts.firstIndex { $0.id == library.selected } }

    init(storage: ScriptStorage = .local) {
        self.storage = storage
        do {
            library = try storage.load()
            loadFailure = nil
        } catch {
            library = ScriptLibrary(scripts: [], selected: nil)
            loadFailure = error
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditMenu()
        configurePanel()
        refreshScripts()
        showReader(at: 0)
        updateClock()
        updateSizeAndSpeed()

        if let button = status.button {
            button.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Cuecard")
            button.toolTip = "Cuecard"
            button.target = self
            button.action = #selector(togglePanel)
        }
        if let loadFailure {
            report("Unable to read scripts", error: loadFailure)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        persist()
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            placePanelIfNeeded()
            panel.orderFrontRegardless()
            layoutScript()
            updateReadingStatus()
        }
    }

    @objc private func hidePanel() {
        stopAutoScroll()
        endEditing(keepVisible: false)
        confirmingID = nil
        updateToolVisibility()
        persist()
        panel.orderOut(nil)
    }

    @objc private func quit() {
        persist()
        // If the disk is temporarily unwritable, keep unsaved edits available.
        guard !dirty || loadFailure != nil else { return }
        NSApp.terminate(nil)
    }

    private func placePanelIfNeeded() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
                ?? status.button?.window?.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let old = panel.frame
        let size = NSSize(width: min(old.width, visible.width), height: min(old.height, visible.height))
        let nearPointer = old.width == 0 || !visible.intersects(old) || !placed
        let x = nearPointer ? pointer.x - size.width + 20 : old.minX
        let y = nearPointer ? visible.maxY - size.height : old.minY
        panel.setFrame(NSRect(x: min(max(visible.minX, x), visible.maxX - size.width),
                              y: min(max(visible.minY, y), visible.maxY - size.height),
                              width: size.width, height: size.height), display: false)
        placed = true
    }

    private var placed = false

    private func installEditMenu() {
        let menu = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        let commands = [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
                        ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                        ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")]
        for (title, action, key) in commands {
            edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func configurePanel() {
        panel.title = "Cuecard"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .canJoinAllApplications]
        panel.contentMinSize = NSSize(width: 400, height: 340)

        let surface = NSVisualEffectView()
        surface.material = .popover
        surface.blendingMode = .behindWindow
        surface.state = .active
        panel.contentView = surface

        let mark = makeSymbol("text.alignleft", size: 14)
        mark.contentTintColor = .controlAccentColor
        let branding = label("Cuecard", size: 13, weight: .semibold, color: .labelColor)
        warning.font = .systemFont(ofSize: 11, weight: .medium)
        warning.textColor = .systemOrange
        warning.lineBreakMode = .byTruncatingTail
        warning.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wire(manage, title: "", action: #selector(showManagement), symbol: "ellipsis")
        manage.setAccessibilityLabel("Manage scripts")
        manage.toolTip = "Manage scripts"
        let hide = makeButton("", #selector(hidePanel), symbol: "xmark")
        hide.toolTip = "Hide panel"
        hide.setAccessibilityLabel("Hide panel")
        let header = row([mark, branding, NSView(), warning, manage, hide])

        picker.target = self
        picker.action = #selector(selectScript)
        picker.menu?.autoenablesItems = false
        picker.isBordered = false
        picker.font = .systemFont(ofSize: 22, weight: .semibold)
        picker.cell?.lineBreakMode = .byTruncatingTail
        picker.setAccessibilityLabel("Current script")
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addManageItem("New Script", #selector(newScript))
        addManageItem("Rename Script", #selector(renameScript))
        addManageItem("Delete Script…", #selector(requestDelete))
        management.addItem(.separator())
        addManageItem("Quit Cuecard", #selector(quit))
        wire(switchMode, title: "Edit", action: #selector(toggleEditing), symbol: "pencil")
        switchMode.treatment = .filled
        let scriptsRow = row([picker, NSView(), switchMode])

        sectionPicker.target = self
        sectionPicker.action = #selector(jumpToSection)
        sectionPicker.menu?.autoenablesItems = false
        sectionPicker.isBordered = false
        sectionPicker.font = .systemFont(ofSize: 12, weight: .medium)
        sectionPicker.setAccessibilityLabel("Jump to a section")
        sectionPicker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        readerTools = row([sectionPicker, NSView()])

        titleField.placeholderString = "Script name"
        titleField.setAccessibilityLabel("Script name")
        titleField.delegate = self
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        markdownOption.target = self
        markdownOption.action = #selector(changeFormat)
        editorTools = row([titleField, markdownOption])

        let deleteLabel = NSTextField(labelWithString: "Delete this script?")
        deleteLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        deleteTools = row([deleteLabel, NSView(),
                           makeButton("Cancel", #selector(cancelDelete)),
                           makeButton("Delete", #selector(deleteScript))])

        let toolbar = NSView()
        for tools in [readerTools!, editorTools!, deleteTools!] { pinRow(tools, inside: toolbar) }
        toolbar.heightAnchor.constraint(equalToConstant: 26).isActive = true

        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        text.frame = NSRect(origin: .zero, size: NSSize(width: 410, height: 330))
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.containerSize = NSSize(width: 410, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 19, height: 17)
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.delegate = self
        text.setAccessibilityLabel("Presentation script")
        scroll.userDidScroll = { [weak self] in
            if self?.scrollTimer != nil { self?.stopAutoScroll() }
        }
        scroll.documentDidFit = { [weak self] in self?.updateReadingStatus() }
        scroll.documentView = text
        let card = ReaderCard()
        card.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: card.topAnchor, constant: 2),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -2),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 2),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -2)
        ])
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportDidChange(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(userStartedScrolling(_:)),
                                               name: NSScrollView.willStartLiveScrollNotification, object: scroll)

        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .secondaryLabelColor
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        speedLabel.textColor = .secondaryLabelColor
        let smaller = makeButton("A−", #selector(smallerText))
        let larger = makeButton("A+", #selector(largerText))
        smaller.setAccessibilityLabel("Decrease text size")
        larger.setAccessibilityLabel("Increase text size")
        wire(scrollButton, title: "Auto-scroll", action: #selector(toggleAutoScroll), symbol: "play.fill")
        scrollButton.treatment = .primary
        scrollButton.widthAnchor.constraint(equalToConstant: 116).isActive = true
        speedControl.controlSize = .small
        speedControl.isContinuous = true
        speedControl.target = self
        speedControl.action = #selector(changeSpeed)
        speedControl.setAccessibilityLabel("Auto-scroll speed")
        speedControl.widthAnchor.constraint(equalToConstant: 60).isActive = true
        speedLabel.widthAnchor.constraint(equalToConstant: 49).isActive = true
        let readingRow = row([scrollButton, speedControl, speedLabel, NSView(), smaller, sizeLabel, larger])

        let timerLabel = makeSymbol("timer", size: 13)
        clockLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        clockLabel.setAccessibilityLabel("Elapsed time")
        wire(clockButton, title: "Start", action: #selector(toggleClock))
        wire(resetButton, title: "", action: #selector(resetClock), symbol: "arrow.counterclockwise")
        resetButton.setAccessibilityLabel("Reset timer")
        resetButton.toolTip = "Reset timer"
        scrollHint.font = .systemFont(ofSize: 11, weight: .medium)
        scrollHint.textColor = .secondaryLabelColor
        scrollHint.lineBreakMode = .byTruncatingTail
        scrollHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let timerRow = row([timerLabel, clockLabel, clockButton, resetButton, NSView(), scrollHint])

        let rows: [NSView] = [header, scriptsRow, toolbar, card, progress, readingRow, timerRow]
        for view in rows {
            surface.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 17),
                view.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -17)
            ])
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: surface.topAnchor, constant: 13),
            scriptsRow.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            toolbar.topAnchor.constraint(equalTo: scriptsRow.bottomAnchor, constant: 3),
            card.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 7),
            progress.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 9),
            progress.heightAnchor.constraint(equalToConstant: 3),
            readingRow.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 7),
            timerRow.topAnchor.constraint(equalTo: readingRow.bottomAnchor, constant: 3),
            timerRow.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -9),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])
        updateToolVisibility()
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func pinRow(_ row: NSStackView, inside container: NSView) {
        container.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
    }

    private func label(_ title: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    private func makeSymbol(_ symbol: String, size: CGFloat) -> NSImageView {
        let view = NSImageView()
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        view.contentTintColor = .secondaryLabelColor
        return view
    }

    private func makeButton(_ title: String, _ action: Selector, symbol: String? = nil) -> PanelButton {
        let button = PanelButton()
        wire(button, title: title, action: action, symbol: symbol)
        return button
    }

    private func wire(_ button: PanelButton, title: String, action: Selector, symbol: String? = nil) {
        button.title = title
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.target = self
        button.action = action
        if let symbol { setSymbol(symbol, on: button) }
    }

    private func setSymbol(_ symbol: String, on button: NSButton) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        button.imagePosition = button.title.isEmpty ? .imageOnly : .imageLeading
    }

    @objc private func showManagement() {
        management.popUp(positioning: nil, at: NSPoint(x: 0, y: manage.isFlipped ? manage.bounds.maxY : 0), in: manage)
    }

    private func addManageItem(_ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        management.addItem(item)
    }

    private func updateToolVisibility() {
        readerTools.isHidden = editing || confirmingID != nil
        editorTools.isHidden = !editing
        deleteTools.isHidden = confirmingID == nil
        switchMode.title = editing ? "Done" : "Edit"
        setSymbol(editing ? "checkmark" : "pencil", on: switchMode)
        switchMode.isEnabled = selection != nil
        updateReadingStatus()
    }

    private func refreshScripts() {
        picker.removeAllItems()
        if library.scripts.isEmpty {
            picker.addItem(withTitle: "No scripts")
            picker.isEnabled = false
        } else {
            for script in library.scripts {
                appendChoice(script.displayTitle, to: picker)
            }
            picker.selectItem(at: selection ?? 0)
            picker.isEnabled = true
        }
        updateToolVisibility()
    }

    @objc private func selectScript() {
        let index = picker.indexOfSelectedItem
        guard library.scripts.indices.contains(index) else { return }
        let id = library.scripts[index].id
        if id == library.selected { return }
        endEditing(keepVisible: true)
        confirmingID = nil
        library.selected = id
        refreshScripts()
        showReader(at: 0)
        saveSoon()
    }

    @objc private func newScript() {
        endEditing(keepVisible: true)
        confirmingID = nil
        let script = Script(title: "Untitled Script")
        library.scripts.append(script)
        library.selected = script.id
        refreshScripts()
        showReader(at: 0)
        saveSoon()
        beginEditing(focusTitle: true)
    }

    @objc private func renameScript() {
        beginEditing(focusTitle: true)
    }

    @objc private func toggleEditing() {
        if editing { endEditing(keepVisible: true) }
        else { beginEditing(focusTitle: false) }
    }

    private func beginEditing(focusTitle: Bool) {
        guard let selection else { return }
        if !editing {
            stopAutoScroll()
            confirmingID = nil
            readerOffset = scroll.contentView.bounds.minY
            previousApp = NSWorkspace.shared.frontmostApplication
            let script = library.scripts[selection]
            titleField.stringValue = script.title
            markdownOption.state = script.markdown ? .on : .off
            text.isSelectable = true
            text.isEditable = true
            text.isRichText = false
            text.string = script.source
            text.font = .systemFont(ofSize: CGFloat(min(library.textSize, 28)))
            text.textColor = .textColor
            text.allowsUndo = true
            text.undoManager?.removeAllActions()
            text.setSelectedRange(NSRange(location: 0, length: 0))
            editingID = script.id
            editing = true
            panel.editing = true
            updateToolVisibility()
        }
        panel.makeKey()
        panel.makeFirstResponder(focusTitle ? titleField : text)
        if focusTitle { titleField.selectText(nil) }
    }

    private func endEditing(keepVisible: Bool) {
        guard editing else { return }
        panel.makeFirstResponder(nil)
        editing = false
        editingID = nil
        panel.editing = false
        text.allowsUndo = false
        text.isEditable = false
        text.isSelectable = false
        refreshScripts()
        showReader(at: readerOffset)
        persist()
        if panel.isKeyWindow {
            panel.orderOut(nil)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier {
                previousApp?.activate(options: [])
            }
            if keepVisible { panel.orderFrontRegardless() }
        }
        previousApp = nil
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === titleField,
              let selection, library.scripts[selection].id == editingID else { return }
        library.scripts[selection].title = titleField.stringValue
        saveSoon()
    }

    func textDidChange(_ notification: Notification) {
        guard let selection, library.scripts[selection].id == editingID else { return }
        library.scripts[selection].source = text.string
        saveSoon()
    }

    @objc private func changeFormat() {
        guard let selection, library.scripts[selection].id == editingID else { return }
        library.scripts[selection].markdown = markdownOption.state == .on
        saveSoon()
    }

    @objc private func requestDelete() {
        guard let id = library.selected else { return }
        endEditing(keepVisible: true)
        confirmingID = id
        updateToolVisibility()
    }

    @objc private func cancelDelete() {
        confirmingID = nil
        updateToolVisibility()
    }

    @objc private func deleteScript() {
        guard let id = confirmingID, let index = library.scripts.firstIndex(where: { $0.id == id }) else { return }
        library.scripts.remove(at: index)
        library.selected = library.scripts.isEmpty ? nil : library.scripts[min(index, library.scripts.count - 1)].id
        confirmingID = nil
        refreshScripts()
        showReader(at: 0)
        saveSoon()
    }

    private func showReader(at offset: CGFloat) {
        stopAutoScroll()
        let script = selection.map { library.scripts[$0] }
        let body: String
        if let script, !script.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = script.source
        } else {
            body = script == nil ? "Choose ⋯ → New Script to get started." : "Click Edit to write your script."
        }
        let result = FormattedScript.render(body, markdown: script?.markdown ?? false, size: CGFloat(library.textSize))
        text.isRichText = true
        text.textStorage?.setAttributedString(result.text)
        sections = result.sections
        sectionPicker.removeAllItems()
        sectionPicker.addItem(withTitle: sections.isEmpty ? "Add # headings to jump" : "Jump to section")
        for section in sections {
            appendChoice(section.name, to: sectionPicker)
        }
        sectionPicker.selectItem(at: 0)
        sectionPicker.isEnabled = !sections.isEmpty
        layoutScript()
        scrollTo(offset)
        updateReadingStatus()
    }

    private func appendChoice(_ title: String, to popup: NSPopUpButton) {
        // AppKit otherwise replaces an existing row with the same title.
        popup.addItem(withTitle: UUID().uuidString)
        popup.item(at: popup.numberOfItems - 1)?.title = title
    }

    @objc private func jumpToSection() {
        let index = sectionPicker.indexOfSelectedItem - 1
        sectionPicker.selectItem(at: 0)
        guard sections.indices.contains(index), let layout = text.layoutManager else { return }
        let offset = sections[index].offset
        guard offset < (text.textStorage?.length ?? 0) else { return }
        stopAutoScroll()
        layoutScript()
        let glyph = layout.glyphIndexForCharacter(at: offset)
        let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        scrollTo(line.minY)
    }

    @objc private func smallerText() { changeSize(-2) }
    @objc private func largerText() { changeSize(2) }

    private func changeSize(_ delta: Int) {
        library.textSize = min(max(library.textSize + delta, 14), 64)
        updateSizeAndSpeed()
        if editing { text.font = .systemFont(ofSize: CGFloat(min(library.textSize, 28))) }
        else { showReader(at: scroll.contentView.bounds.minY) }
        saveSoon()
    }

    @objc private func changeSpeed() {
        library.scrollSpeed = speedControl.integerValue
        updateSizeAndSpeed()
        saveSoon()
    }

    private func updateSizeAndSpeed() {
        sizeLabel.stringValue = "\(library.textSize) pt"
        speedControl.integerValue = library.scrollSpeed
        speedLabel.stringValue = "\(library.scrollSpeed) pt/s"
    }

    private func layoutScript() {
        panel.contentView?.layoutSubtreeIfNeeded()
        scroll.fitDocument()
    }

    private func scrollTo(_ y: CGFloat) {
        scroll.move(to: y)
    }

    @objc private func toggleAutoScroll() {
        if scrollTimer != nil { stopAutoScroll(); return }
        layoutScript()
        guard !editing, scroll.scrollLimit > 0.5 else {
            updateReadingStatus()
            return
        }
        scrollPosition = scroll.contentView.bounds.minY
        if scrollPosition >= scroll.scrollLimit - 0.5 {
            scrollPosition = 0
            scrollTo(0)
        }
        lastScrollTick = now
        let timer = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(advanceScroll(_:)),
                          userInfo: nil, repeats: true)
        scrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        updateScrollButton()
        updateReadingStatus()
    }

    @objc private func advanceScroll(_ timer: Timer) {
        let timestamp = now
        // Keep fractional points across ticks because the clip view rounds to pixels.
        scrollPosition += min(timestamp - lastScrollTick, 0.08) * CGFloat(library.scrollSpeed)
        lastScrollTick = timestamp
        scrollTo(scrollPosition)
        if scrollPosition >= scroll.scrollLimit { stopAutoScroll() }
    }

    private func stopAutoScroll() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        updateScrollButton()
        updateReadingStatus()
    }

    private func updateScrollButton() {
        let playing = scrollTimer != nil
        scrollButton.title = playing ? "Pause scroll" : "Auto-scroll"
        setSymbol(playing ? "pause.fill" : "play.fill", on: scrollButton)
    }

    @objc private func viewportDidChange(_ notification: Notification) {
        updateReadingStatus()
    }

    @objc private func userStartedScrolling(_ notification: Notification) {
        if scrollTimer != nil { stopAutoScroll() }
    }

    private func updateReadingStatus() {
        let limit = scroll.scrollLimit
        let canScroll = !editing && selection != nil && limit > 0.5
        progress.fraction = canScroll ? min(max(scroll.contentView.bounds.minY / limit, 0), 1) : 0
        if scrollButton.isEnabled != canScroll { scrollButton.isEnabled = canScroll }
        let hint: String
        if editing { hint = "Changes save automatically" }
        else if selection != nil && !canScroll { hint = "Script fits on screen" }
        else if scrollTimer == nil && progress.fraction >= 0.999 { hint = "End of script" }
        else { hint = "" }
        if scrollHint.stringValue != hint { scrollHint.stringValue = hint }
        let tip = !editing && canScroll ? nil : hint
        if scrollButton.toolTip != tip { scrollButton.toolTip = tip }
    }

    @objc private func toggleClock() {
        if let started = clockStarted {
            elapsed += now - started
            clockStarted = nil
            clockTimer?.invalidate()
            clockTimer = nil
        } else {
            clockStarted = now
            let timer = Timer(timeInterval: 0.2, target: self, selector: #selector(refreshClock(_:)),
                              userInfo: nil, repeats: true)
            clockTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        updateClock()
    }

    @objc private func resetClock() {
        clockStarted = nil
        clockTimer?.invalidate()
        clockTimer = nil
        elapsed = 0
        updateClock()
    }

    @objc private func refreshClock(_ timer: Timer) { updateClock() }

    private func updateClock() {
        let seconds = Int(elapsed + (clockStarted.map { now - $0 } ?? 0))
        clockLabel.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
        clockButton.title = clockStarted == nil ? (elapsed == 0 ? "Start" : "Resume") : "Pause"
        resetButton.isEnabled = clockStarted != nil || elapsed > 0
    }

    private func saveSoon() {
        dirty = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(timeInterval: 0.30, target: self, selector: #selector(saveAfterDelay(_:)),
                                         userInfo: nil, repeats: false)
    }

    @objc private func saveAfterDelay(_ timer: Timer) { persist() }

    private func persist() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard dirty, loadFailure == nil else { return }
        do {
            try storage.save(library)
            dirty = false
            warning.stringValue = ""
            warning.toolTip = nil
        } catch {
            report("Scripts not saved", error: error)
        }
    }

    private func report(_ message: String, error: Error) {
        warning.stringValue = message
        warning.toolTip = "\(error.localizedDescription)\n\(storage.file.path)"
    }
}
