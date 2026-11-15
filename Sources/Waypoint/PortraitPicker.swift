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

    func retry() { failures = [] }

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

@MainActor
final class PortraitPicker: NSWindowController {
    private static var current: PortraitPicker?
    private var buttons: [(AccountPortrait, NSButton)] = []
    private let status = NSTextField(wrappingLabelWithString: "")
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
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 540),
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
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 20)
        ])
        for game in ["World of Warcraft", "Diablo III"] {
            let label = NSTextField(labelWithString: game)
            label.font = .boldSystemFont(ofSize: 13)
            stack.addArrangedSubview(label)
            let choices = AccountPortrait.choices.filter { $0.game == game }
            for offset in stride(from: 0, to: choices.count, by: 4) {
                let row = NSStackView()
                row.spacing = 8
                for choice in choices.dropFirst(offset).prefix(4) {
                    let button = NSButton(title: choice.name, target: self, action: #selector(selectPortrait(_:)))
                    button.identifier = NSUserInterfaceItemIdentifier(choice.id)
                    button.imagePosition = .imageAbove
                    button.imageScaling = .scaleProportionallyDown
                    button.bezelStyle = .regularSquare
                    button.setButtonType(.toggle)
                    button.font = .systemFont(ofSize: 11)
                    button.toolTip = "Use \(choice.name) for \(account.displayName)"
                    button.setAccessibilityLabel(choice.name)
                    button.widthAnchor.constraint(equalToConstant: 118).isActive = true
                    button.heightAnchor.constraint(equalToConstant: 90).isActive = true
                    row.addArrangedSubview(button)
                    buttons.append((choice, button))
                }
                stack.addArrangedSubview(row)
            }
        }
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        stack.addArrangedSubview(status)
        let actions = NSStackView()
        actions.spacing = 12
        actions.addArrangedSubview(NSButton(title: "Use Default Icon", target: self, action: #selector(reset)))
        actions.addArrangedSubview(NSButton(title: "Retry Images", target: self, action: #selector(retry)))
        let done = NSButton(title: "Done", target: self, action: #selector(done))
        done.keyEquivalent = "\r"
        actions.addArrangedSubview(done)
        stack.addArrangedSubview(actions)
        panel.center()
        observeChanges { [weak self] in self?.render() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func render() {
        let saved = model.accounts.first { $0.id == accountID }
        for (choice, button) in buttons {
            let portrait = PortraitImages.shared.image(id: choice.id)
            let display = portrait?.copy() as? NSImage
            display?.size = NSSize(width: 48, height: 48)
            button.image = display ?? .symbol("person.crop.circle", pointSize: 32)
            button.isEnabled = saved != nil && portrait != nil
            button.state = saved?.portraitID == choice.id ? .on : .off
        }
        let failures = PortraitImages.shared.failures.count
        status.stringValue = failures > 0
            ? "Some portraits couldn’t load. Your saved choice is unchanged. Try again when connected."
            : "Artwork loads directly from Blizzard’s CDN and stays cached for offline use."
    }

    @objc private func selectPortrait(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        model.setPortrait(id, for: accountID)
    }
    @objc private func reset() { model.setPortrait(nil, for: accountID) }
    @objc private func retry() { PortraitImages.shared.retry() }
    @objc private func done() { close() }
}
