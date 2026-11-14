import AppKit
import WaypointCore

/// Opt-in development diagnostic. Browser reuse and explicit saved-WoW-token
/// native exchange; no password submission, Keychain writes or account adoption.
@MainActor
final class SharedSignInProbe: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let status = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton(title: "Check Diablo IV shared sign-in", target: nil, action: nil)
    private var task: Task<Void, Never>?
    private let controlButton = NSButton(title: "Check WoW renewal (control)", target: nil, action: nil)
    private let validationButton = NSButton(title: "Validate Diablo IV authentication", target: nil, action: nil)
    private let nativeButton = NSButton(title: "Check saved WoW → Diablo IV exchange", target: nil, action: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 390),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Waypoint — Shared Sign-In Check"
        window.isReleasedWhenClosed = false
        self.window = window
        let explanation = NSTextField(wrappingLabelWithString: "Checks whether the selected account’s existing Waypoint browser session can obtain Diablo IV authorization (Americas). The browser check uses existing cookies, without a saved password. The native exchange reads the saved WoW token from Keychain: close all Blizzard games on all Macs first. Neither test saves authorization or launches a game.")
        status.stringValue = AccountList.load().active.map { "Ready for \($0.displayName)." } ?? "No selected account."
        button.target = self; button.action = #selector(check)
        nativeButton.target = self; nativeButton.action = #selector(checkNative)
        controlButton.target = self; controlButton.action = #selector(checkControl)
        validationButton.target = self; validationButton.action = #selector(checkValidation)
        let stack = NSStackView(views: [explanation, button, controlButton, nativeButton, validationButton, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.center(); window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }


    @objc private func checkControl() { startNative(target: .worldOfWarcraft) }
    @objc private func checkNative() { startNative(target: .diabloIV) }
    @objc private func checkValidation() { startNative(target: .diabloIV, validate: true) }
    private func startNative(target: NativeGameAccounts.CredentialTarget, validate: Bool = false) {
        guard task == nil, let account = AccountList.load().active else { return }
        guard !RunningProcesses.executables().contains(where: { URL(fileURLWithPath: $0.path).lastPathComponent.hasPrefix("World of Warcraft") }) else {
            status.stringValue = "Close Blizzard games on all devices before this native test."; return
        }
        button.isEnabled = false; nativeButton.isEnabled = false; controlButton.isEnabled = false; validationButton.isEnabled = false
        status.stringValue = "Reading saved WoW authorization…"
        task = Task {
            defer { task = nil; button.isEnabled = true; nativeButton.isEnabled = true; controlButton.isEnabled = true; validationButton.isEnabled = true }
            let vault = TokenVault(service: "\(Bundle.main.bundleIdentifier ?? "Waypoint"): Battle.net login tokens")
            guard let token = vault.token(account: account.id, codename: "WoW"), token.accountID == account.id else {
                status.stringValue = "Saved WoW token unavailable. No login changed."; return
            }
            let config = URLSessionConfiguration.ephemeral
            config.waitsForConnectivity = false; config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 20
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            let native = NativeGameAccounts()
            do {
                status.stringValue = "Checking owner-verified WoW authentication and target credential request…"
                let version = try await VersionService(session: session).latest(product: "wowf", region: .us)
                guard version.buildID > 0 else { throw NativeGameAccounts.Failure.unavailable }
                guard !Task.isCancelled,
                      !RunningProcesses.executables().contains(where: { URL(fileURLWithPath: $0.path).lastPathComponent.hasPrefix("World of Warcraft") }) else {
                    status.stringValue = "Close Blizzard games before native authentication. Saved login unchanged."; return
                }
                let issued = try await native.requestCredential(token: token, build: UInt64(version.buildID), region: .us, target: target)
                if validate {
                    status.stringValue = "Credential issued; checking Diablo IV native authentication…"
                    let targetVersion = try await VersionService(session: session).latest(product: "fenris", region: .us)
                    guard targetVersion.buildID > 0, !Task.isCancelled,
                          !RunningProcesses.executables().contains(where: { URL(fileURLWithPath: $0.path).lastPathComponent.hasPrefix("World of Warcraft") }) else { throw NativeGameAccounts.Failure.gameRunning }
                    do {
                        try await NativeGameAccounts().validateDiabloIVCredential(token: issued, build: UInt64(targetVersion.buildID), region: .us)
                    } catch NativeGameAccounts.Failure.rejected(let code) {
                        status.stringValue = "Credential issued, but Diablo IV native authentication refused (\(code)). Saved login unchanged."; return
                    } catch {
                        status.stringValue = "Credential issued; Diablo IV native authentication not established. Saved login unchanged."; return
                    }
                    status.stringValue = "Diablo IV native authentication accepted the generated credential for the expected owner. Not saved; actual game launch remains untested."
                    return
                }
                status.stringValue = "Matching-owner credential returned for \(target == .worldOfWarcraft ? "WoW control" : "Diablo IV request"). Not saved; target scope and game acceptance are untested."
            } catch NativeGameAccounts.Failure.rejected(let code) {
                let stage = native.authenticatedProfile == nil ? "Authentication" : "Signed in successfully; target credential request"
                status.stringValue = "\(stage) refused (\(code)). Saved login unchanged."
            } catch {
                status.stringValue = "Native check did not complete with an owner-verified credential. Saved login unchanged."
            }
        }
    }

    @objc private func check() {
        guard task == nil, let account = AccountList.load().active else { return }
        button.isEnabled = false; nativeButton.isEnabled = false; controlButton.isEnabled = false; validationButton.isEnabled = false; status.stringValue = "Checking existing browser authorization…"
        task = Task {
            defer { task = nil; button.isEnabled = true; nativeButton.isEnabled = true; controlButton.isEnabled = true; validationButton.isEnabled = true }
            let hasCookies = await WebSession.hasCookies(account.session)
            let result = await SilentTokenFetcher().fetch(BattleNetLogin.url(codename: "Fen", region: .us), session: account.session)
            switch result {
            case .token(let token):
                status.stringValue = token.accountID == account.id
                    ? "Matching-owner Diablo IV authorization returned. Not saved; game acceptance is untested."
                    : "A different account was returned. Authorization discarded; saved login unchanged."
            case .signedOut:
                status.stringValue = "Blizzard requires interaction. Battle.net cookies present: \(hasCookies ? "yes" : "no"). Saved login unchanged."
            case .failed:
                status.stringValue = "No authorization returned (network, timeout or unsupported redirect). Battle.net cookies present: \(hasCookies ? "yes" : "no"). Saved login unchanged."
            }
        }
    }
}
