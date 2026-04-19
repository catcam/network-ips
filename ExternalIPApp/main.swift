import AppKit
import Darwin
import Foundation

private struct IPResponse: Decodable {
    let ip: String
}

private struct InterfaceAddress {
    let name: String
    let address: String
    let family: sa_family_t
    let flags: UInt32

    var isUp: Bool {
        flags & UInt32(IFF_UP) != 0
    }

    var isLoopback: Bool {
        flags & UInt32(IFF_LOOPBACK) != 0
    }
}

private struct TailscaleInfo {
    let status: String
    let addresses: [String]
}

private func makeSectionLabel(_ title: String) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = .secondaryLabelColor
    return label
}

private func makeValueLabel(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .monospacedSystemFont(ofSize: size, weight: weight)
    label.lineBreakMode = .byWordWrapping
    label.maximumNumberOfLines = 0
    return label
}

private func uniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}

private func uniqueInterfaceAddresses(_ values: [InterfaceAddress]) -> [InterfaceAddress] {
    var seen = Set<String>()
    return values.filter { seen.insert("\($0.name)|\($0.address)|\($0.family)").inserted }
}

private func sockaddrLength(for family: sa_family_t) -> socklen_t {
    switch Int32(family) {
    case AF_INET:
        return socklen_t(MemoryLayout<sockaddr_in>.size)
    case AF_INET6:
        return socklen_t(MemoryLayout<sockaddr_in6>.size)
    default:
        return socklen_t(MemoryLayout<sockaddr>.size)
    }
}

private func numericAddressString(from sockaddrPointer: UnsafePointer<sockaddr>) -> String? {
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let result = getnameinfo(
        sockaddrPointer,
        sockaddrLength(for: sockaddrPointer.pointee.sa_family),
        &host,
        socklen_t(host.count),
        nil,
        0,
        NI_NUMERICHOST
    )

    guard result == 0 else {
        return nil
    }

    return String(cString: host)
}

private func collectInterfaceAddresses() -> [InterfaceAddress] {
    var results: [InterfaceAddress] = []
    var pointer: UnsafeMutablePointer<ifaddrs>?

    guard getifaddrs(&pointer) == 0, let first = pointer else {
        return results
    }

    defer { freeifaddrs(pointer) }

    var current: UnsafeMutablePointer<ifaddrs>? = first
    while let entry = current {
        defer { current = entry.pointee.ifa_next }

        guard let addressPointer = entry.pointee.ifa_addr else {
            continue
        }

        let family = addressPointer.pointee.sa_family
        guard family == sa_family_t(AF_INET) || family == sa_family_t(AF_INET6) else {
            continue
        }

        let name = String(cString: entry.pointee.ifa_name)
        let flags = UInt32(entry.pointee.ifa_flags)

        guard let address = numericAddressString(from: addressPointer) else {
            continue
        }

        results.append(
            InterfaceAddress(
                name: name,
                address: address,
                family: family,
                flags: flags
            )
        )
    }

    return uniqueInterfaceAddresses(results)
}

private func isPrivateIPv4(_ address: String) -> Bool {
    let parts = address.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4 else {
        return false
    }

    switch parts[0] {
    case 10:
        return true
    case 172:
        return (16...31).contains(parts[1])
    case 192:
        return parts[1] == 168
    default:
        return false
    }
}

private func isLinkLocalIPv4(_ address: String) -> Bool {
    address.hasPrefix("169.254.")
}

private func isLinkLocalIPv6(_ address: String) -> Bool {
    address.lowercased().hasPrefix("fe80:")
}

private func isTailscaleIPv4(_ address: String) -> Bool {
    let parts = address.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4, parts[0] == 100 else {
        return false
    }

    return (64...127).contains(parts[1])
}

private func isTailscaleIPv6(_ address: String) -> Bool {
    address.lowercased().hasPrefix("fd7a:115c:a1e0:")
}

private func isTailscaleAddress(_ address: String) -> Bool {
    isTailscaleIPv4(address) || isTailscaleIPv6(address)
}

private func localNetworkAddresses(from allAddresses: [InterfaceAddress]) -> [InterfaceAddress] {
    let privateIPv4 = allAddresses.filter {
        $0.family == sa_family_t(AF_INET)
            && $0.isUp
            && !$0.isLoopback
            && !isLinkLocalIPv4($0.address)
            && !isTailscaleAddress($0.address)
            && isPrivateIPv4($0.address)
    }

    if !privateIPv4.isEmpty {
        return uniqueInterfaceAddresses(privateIPv4)
    }

    let fallbackIPv4 = allAddresses.filter {
        $0.family == sa_family_t(AF_INET)
            && $0.isUp
            && !$0.isLoopback
            && !isLinkLocalIPv4($0.address)
            && !isTailscaleAddress($0.address)
    }

    if !fallbackIPv4.isEmpty {
        return uniqueInterfaceAddresses(fallbackIPv4)
    }

    let fallbackIPv6 = allAddresses.filter {
        $0.family == sa_family_t(AF_INET6)
            && $0.isUp
            && !$0.isLoopback
            && !isLinkLocalIPv6($0.address)
            && !isTailscaleAddress($0.address)
    }

    return uniqueInterfaceAddresses(fallbackIPv6)
}

private func formatInterfaceAddresses(_ addresses: [InterfaceAddress]) -> String {
    guard !addresses.isEmpty else {
        return "Not detected"
    }

    return addresses
        .map { "\($0.name)  \($0.address)" }
        .joined(separator: "\n")
}

private func runCommand(executable: String, arguments: [String]) -> String? {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
    } catch {
        return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        return nil
    }

    let output = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return output.isEmpty ? nil : output
}

private func findTailscaleCLI() -> String? {
    let candidates = [
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
        "/usr/bin/tailscale"
    ]

    for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
        return candidate
    }

    guard let resolved = runCommand(executable: "/usr/bin/which", arguments: ["tailscale"]) else {
        return nil
    }

    let firstLine = resolved
        .split(whereSeparator: \.isNewline)
        .first
        .map(String.init)

    guard let firstLine, FileManager.default.isExecutableFile(atPath: firstLine) else {
        return nil
    }

    return firstLine
}

private func parseIPs(from output: String) -> [String] {
    uniqueStrings(
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains(" ") && ($0.contains(".") || $0.contains(":")) }
    )
}

private func detectTailscale(from allAddresses: [InterfaceAddress]) -> TailscaleInfo {
    let appBundleFound = FileManager.default.fileExists(atPath: "/Applications/Tailscale.app")
    let scannedAddresses = uniqueStrings(
        allAddresses
            .filter { $0.isUp && !$0.isLoopback && isTailscaleAddress($0.address) }
            .map(\.address)
    )

    if let cli = findTailscaleCLI() {
        let cliIPv4 = runCommand(executable: cli, arguments: ["ip", "-4"]).map(parseIPs(from:)) ?? []
        let cliIPv6 = runCommand(executable: cli, arguments: ["ip", "-6"]).map(parseIPs(from:)) ?? []
        let merged = uniqueStrings(cliIPv4 + cliIPv6 + scannedAddresses)

        if !merged.isEmpty {
            return TailscaleInfo(status: "Detected via CLI", addresses: merged)
        }

        return TailscaleInfo(status: "CLI found, no active Tailscale IP", addresses: [])
    }

    if !scannedAddresses.isEmpty {
        return TailscaleInfo(status: "Detected via interface scan", addresses: scannedAddresses)
    }

    if appBundleFound {
        return TailscaleInfo(status: "App bundle found, no active Tailscale IP", addresses: [])
    }

    return TailscaleInfo(status: "Not detected", addresses: [])
}

private func formatTailscaleInfo(_ info: TailscaleInfo) -> String {
    guard !info.addresses.isEmpty else {
        return info.status
    }

    return ([info.status] + info.addresses).joined(separator: "\n")
}

final class IPViewController: NSViewController {
    private let publicTitleLabel = makeSectionLabel("Public IP")
    private let publicIPLabel = makeValueLabel("...", size: 28, weight: .semibold)
    private let publicStatusLabel = makeValueLabel("Ready.", size: 11)
    private let localTitleLabel = makeSectionLabel("Local IP")
    private let localIPLabel = makeValueLabel("Detecting...")
    private let tailscaleTitleLabel = makeSectionLabel("Tailscale")
    private let tailscaleLabel = makeValueLabel("Detecting...")
    private let traceTitleLabel = makeSectionLabel("Traceroute")

    private let traceTextView: NSTextView = {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = "Waiting for public IP..."
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        return textView
    }()

    private lazy var traceScrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = traceTextView
        return scrollView
    }()

    private lazy var refreshButton: NSButton = {
        let button = NSButton(title: "Refresh", target: self, action: #selector(refreshIP))
        button.bezelStyle = .rounded
        return button
    }()

    private var currentTask: URLSessionDataTask?
    private var tracerouteProcess: Process?
    private var tracerouteRunID: UUID?
    private var refreshRunID: UUID?

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 620))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView(views: [
            publicTitleLabel,
            publicIPLabel,
            publicStatusLabel,
            localTitleLabel,
            localIPLabel,
            tailscaleTitleLabel,
            tailscaleLabel,
            refreshButton,
            traceTitleLabel,
            traceScrollView
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
            publicIPLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            publicStatusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            localIPLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tailscaleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            traceScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            traceScrollView.heightAnchor.constraint(equalToConstant: 260)
        ])

        self.view = rootView
    }

    @objc func refreshIP() {
        let runID = UUID()
        refreshRunID = runID

        currentTask?.cancel()
        stopTraceroute()

        publicIPLabel.stringValue = "..."
        publicStatusLabel.stringValue = "Fetching public IP..."
        localIPLabel.stringValue = "Detecting..."
        tailscaleLabel.stringValue = "Detecting..."
        traceTextView.string = "Waiting for public IP..."

        refreshLocalNetworkDetails(for: runID)

        guard let url = URL(string: "https://api.ipify.org?format=json") else {
            publicStatusLabel.stringValue = "Error: invalid URL."
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self, self.refreshRunID == runID else { return }

                if let nsError = error as NSError?, nsError.code == NSURLErrorCancelled {
                    return
                }

                if let error {
                    self.publicIPLabel.stringValue = "n/a"
                    self.publicStatusLabel.stringValue = "Error: \(error.localizedDescription)"
                    return
                }

                guard let data else {
                    self.publicIPLabel.stringValue = "n/a"
                    self.publicStatusLabel.stringValue = "Error: no response data."
                    return
                }

                do {
                    let response = try JSONDecoder().decode(IPResponse.self, from: data)
                    self.publicIPLabel.stringValue = response.ip
                    self.publicStatusLabel.stringValue = "Source: api.ipify.org"
                    self.runTraceroute(to: response.ip)
                } catch {
                    self.publicIPLabel.stringValue = "n/a"
                    self.publicStatusLabel.stringValue = "Error: unreadable response."
                    self.traceTextView.string = "Traceroute was not started."
                }
            }
        }

        currentTask = task
        task.resume()
    }

    private func refreshLocalNetworkDetails(for runID: UUID) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let addresses = collectInterfaceAddresses()
            let local = formatInterfaceAddresses(localNetworkAddresses(from: addresses))
            let tailscale = formatTailscaleInfo(detectTailscale(from: addresses))

            DispatchQueue.main.async {
                guard let self, self.refreshRunID == runID else { return }
                self.localIPLabel.stringValue = local
                self.tailscaleLabel.stringValue = tailscale
            }
        }
    }

    private func stopTraceroute() {
        tracerouteRunID = nil
        tracerouteProcess?.terminate()
        tracerouteProcess = nil
    }

    private func runTraceroute(to host: String) {
        stopTraceroute()
        let runID = UUID()
        tracerouteRunID = runID
        traceTextView.string = "Running traceroute to \(host)..."

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/sbin/traceroute")
            process.arguments = ["-m", "12", "-q", "1", "-w", "1", host]
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    guard self.tracerouteRunID == runID else { return }
                    self.traceTextView.string = "Could not start traceroute."
                }
                return
            }

            DispatchQueue.main.async {
                guard self.tracerouteRunID == runID else {
                    process.terminate()
                    return
                }
                self.tracerouteProcess = process
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                guard self.tracerouteRunID == runID else { return }
                defer {
                    self.tracerouteProcess = nil
                    self.tracerouteRunID = nil
                }

                if process.terminationReason == .uncaughtSignal {
                    self.traceTextView.string = "Traceroute interrupted."
                    return
                }

                guard let output, !output.isEmpty else {
                    self.traceTextView.string = "Traceroute returned no output."
                    return
                }

                self.traceTextView.string = output
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let viewController = IPViewController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Network IPs"
        window.center()
        window.contentViewController = viewController
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        viewController.refreshIP()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.setActivationPolicy(.regular)
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
