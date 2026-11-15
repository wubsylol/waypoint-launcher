import AppKit
import ImageIO
import Observation
import WaypointCore

/// Only bounded, downsampled artwork is cached. No cookies or authorization are sent.
@MainActor @Observable
final class PortraitImages {
    static let shared = PortraitImages()
    private var images: [String: NSImage] = [:]
    private(set) var failures: Set<String> = []
    @ObservationIgnored private var pending: Set<String> = []

    func image(id: String) -> NSImage? {
        if let image = images[id] { return image }
        guard let choice = AccountPortrait.choices.first(where: { $0.id == id }),
              !failures.contains(id), pending.insert(id).inserted else { return nil }
        Task {
            do {
                let data = try await Self.fetch(choice)
                guard let source = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                let portrait = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
                    NSBezierPath(ovalIn: rect).addClip()
                    let side = min(source.size.width, source.size.height)
                    source.draw(in: rect, from: NSRect(x: (source.size.width - side) / 2,
                        y: (source.size.height - side) / 2, width: side, height: side),
                        operation: .sourceOver, fraction: 1)
                    return true
                }
                portrait.isTemplate = false
                images[id] = portrait
            } catch { failures.insert(id) }
            pending.remove(id)
        }
        return nil
    }

    nonisolated private static func fetch(_ choice: AccountPortrait) async throws -> Data {
        let directory = URL.cachesDirectory.appendingPathComponent("io.wubs.waypoint/portraits-v1", isDirectory: true)
        let file = directory.appendingPathComponent(choice.id + ".png")
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 262_144,
           let data = try? Data(contentsOf: file), thumbnail(data) != nil { return data }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: choice.url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == choice.url.host,
              response.mimeType?.hasPrefix("image/") == true,
              response.expectedContentLength <= 262_144 else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 262_144 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        guard let small = thumbnail(data) else { throw URLError(.cannotDecodeContentData) }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? small.write(to: file, options: .atomic)
        return small
    }

    nonisolated private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 96,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Keep the portrait and caption together at the centre of the native button.
@MainActor
private final class PortraitButton: NSButton {
    let portraitView = NSImageView()

    init(name: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = ""
        bezelStyle = .regularSquare
        setButtonType(.toggle)
        setAccessibilityLabel(name)
        let caption = NSTextField(labelWithString: name)
        caption.font = .systemFont(ofSize: 11)
        caption.alignment = .center
        let content = NSStackView(views: [portraitView, caption])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        portraitView.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 106),
            heightAnchor.constraint(equalToConstant: 84),
            portraitView.widthAnchor.constraint(equalToConstant: 40),
            portraitView.heightAnchor.constraint(equalToConstant: 40),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
}

@MainActor
final class PortraitPicker: NSWindowController {
    private static var current: PortraitPicker?
    private var buttons: [(AccountPortrait?, PortraitButton)] = []
    private let model: AppModel
    private let accountID: String

    static func show(model: AppModel, account: Account) {
        current?.close()
        let picker = PortraitPicker(model: model, account: account)
        current = picker
        picker.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(model: AppModel, account: Account) {
        self.model = model
        accountID = account.id
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 336),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Choose Portrait — \(account.displayName)"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 16)
        ])
        let choices: [AccountPortrait?] = [nil] + AccountPortrait.choices.map { Optional($0) }
        for offset in stride(from: 0, to: choices.count, by: 4) {
            let row = NSStackView()
            row.spacing = 8
            for choice in choices.dropFirst(offset).prefix(4) {
                let name = choice?.name ?? "Waypoint"
                let button = PortraitButton(name: name, target: self, action: #selector(selectPortrait(_:)))
                button.identifier = NSUserInterfaceItemIdentifier(choice?.id ?? "default")
                button.toolTip = "Use \(name) for \(account.displayName)"
                row.addArrangedSubview(button)
                buttons.append((choice, button))
            }
            stack.addArrangedSubview(row)
        }
        let actions = NSStackView()
        actions.addArrangedSubview(NSView())
        let done = NSButton(title: "Done", target: self, action: #selector(done))
        done.keyEquivalent = "\r"
        actions.addArrangedSubview(done)
        stack.addArrangedSubview(actions)
        actions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        panel.setContentSize(NSSize(width: 480, height: stack.fittingSize.height + 32))
        panel.center()
        observeChanges { [weak self] in self?.render() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func render() {
        let saved = model.accounts.first { $0.id == accountID }
        for (choice, button) in buttons {
            let portrait = choice.flatMap { PortraitImages.shared.image(id: $0.id) }
            button.portraitView.image = portrait ?? .waypointPortrait
            button.isEnabled = saved != nil && (choice == nil || portrait != nil)
            button.state = saved?.portraitID == choice?.id ? .on : .off
            if let choice, PortraitImages.shared.failures.contains(choice.id) {
                button.toolTip = "\(choice.name) couldn’t load from Blizzard. Please report this if it persists."
            }
        }
    }

    @objc private func selectPortrait(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        model.setPortrait(id == "default" ? nil : id, for: accountID)
    }
    @objc private func done() { close() }
}

extension NSImage {
    /// Use the bundled application artwork, never another installed app's icon.
    @MainActor static let waypointPortrait: NSImage = {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let source = NSImage(contentsOf: iconURL) else {
            // SwiftPM development launches have no bundled Resources directory.
            return .symbol("person.crop.circle", pointSize: 24) ?? NSImage()
        }
        let result = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            // Remove the app icon’s transparent macOS padding before the circular crop.
            let side = min(source.size.width, source.size.height) * 0.8
            source.draw(in: rect, from: NSRect(x: (source.size.width - side) / 2,
                y: (source.size.height - side) / 2, width: side, height: side),
                operation: .sourceOver, fraction: 1)
            return true
        }
        result.isTemplate = false
        return result
    }()
}
