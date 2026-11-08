import Cocoa
import SwiftUI
import Security
import CommonCrypto
import ServiceManagement

// MARK: - Models

enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case claude = "claude"
    case antigravity = "antigravity"
    case codex = "codex"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .antigravity: return "Antigravity"
        case .codex: return "Codex"
        }
    }
}

struct QuotaBucket: Identifiable, Equatable {
    let id: String          // e.g. "claude.5h", "claude.7d", "antigravity.gemini.5h", "codex.primary"
    let provider: ProviderID
    let label: String       // Short label for pin button: "5h", "7d", "Gemini 5h", "Gemini 7d", "Claude 5h", "30d"
    let remainingPercent: Int
    let resetDate: Date?
    let detail: String?

    var shortResetText: String {
        guard let resetDate = resetDate else { return detail ?? "" }
        let diff = resetDate.timeIntervalSinceNow
        if diff <= 0 { return "now" }
        let totalMinutes = Int(diff / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let mins = totalMinutes % 60
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}

struct ProviderStatus: Identifiable {
    let id: ProviderID
    var subtitle: String
    var buckets: [QuotaBucket]
    var errorNote: String?
}

// MARK: - Color Helpers

func quotaNSColor(for pct: Int) -> NSColor {
    if pct <= 15 {
        return NSColor(srgbRed: 0.973, green: 0.443, blue: 0.443, alpha: 1.0) // Red #F87171
    } else if pct <= 40 {
        return NSColor(srgbRed: 0.980, green: 0.800, blue: 0.082, alpha: 1.0) // Yellow #FACC15
    } else {
        return NSColor(srgbRed: 0.290, green: 0.871, blue: 0.502, alpha: 1.0) // Green #4ADE80
    }
}

func quotaSwiftUIColor(for pct: Int) -> Color {
    if pct <= 15 {
        return Color(red: 0.973, green: 0.443, blue: 0.443)
    } else if pct <= 40 {
        return Color(red: 0.980, green: 0.800, blue: 0.082)
    } else {
        return Color(red: 0.290, green: 0.871, blue: 0.502)
    }
}

// MARK: - Native App Icons & Vector Logos

enum LogoCache {
    // Transparent-background Antigravity rainbow 'A' glyph (prefers bundled PNG, falls back to unmixing icon.icns)
    static let antigravityIcon: NSImage? = {
        if let bundledPath = Bundle.main.path(forResource: "antigravity_logo", ofType: "png"),
           let bundled = NSImage(contentsOfFile: bundledPath) {
            return bundled
        }
        guard let src = NSImage(contentsOfFile: "/Applications/Antigravity.app/Contents/Resources/icon.icns") else { return nil }
        let targetSize = NSSize(width: 512, height: 512)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 512,
            pixelsHigh: 512,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        src.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        let cropX = 100, cropY = 95, cropSize = 312
        guard let outRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: cropSize,
            pixelsHigh: cropSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        for y in 0..<cropSize {
            for x in 0..<cropSize {
                guard let c = rep.colorAt(x: cropX + x, y: cropY + y)?.usingColorSpace(.deviceRGB) else { continue }
                let r = c.redComponent
                let g = c.greenComponent
                let b = c.blueComponent
                let minC = min(r, min(g, b))
                let rawAlpha = (0.96 - minC) / (0.96 - 0.35)
                let alpha = max(0.0, min(1.0, rawAlpha)) * c.alphaComponent
                if alpha > 0.01 {
                    let fgR = max(0.0, min(1.0, (r - (1.0 - alpha)) / alpha))
                    let fgG = max(0.0, min(1.0, (g - (1.0 - alpha)) / alpha))
                    let fgB = max(0.0, min(1.0, (b - (1.0 - alpha)) / alpha))
                    outRep.setColor(NSColor(deviceRed: fgR, green: fgG, blue: fgB, alpha: alpha), atX: x, y: y)
                } else {
                    outRep.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y)
                }
            }
        }

        let outImg = NSImage(size: NSSize(width: cropSize, height: cropSize))
        outImg.addRepresentation(outRep)
        return outImg
    }()

    // Tightly cropped Claude starburst template (prefers bundled PNG, falls back to TrayIconTemplate@2x.png)
    static let claudeTemplateIcon: NSImage? = {
        if let bundledPath = Bundle.main.path(forResource: "claude_template", ofType: "png"),
           let bundled = NSImage(contentsOfFile: bundledPath) {
            return bundled
        }
        guard let tpl = NSImage(contentsOfFile: "/Applications/Claude.app/Contents/Resources/TrayIconTemplate@2x.png") else { return nil }
        let w = tpl.size.width
        let h = tpl.size.height
        let srcRect = NSRect(x: w * (6.5 / 48.0), y: h * (6.5 / 48.0), width: w * (35.0 / 48.0), height: h * (35.0 / 48.0))
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { dst in
            NSGraphicsContext.current?.imageInterpolation = .high
            tpl.draw(in: dst, from: srcRect, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }()

    // Official OpenAI knot template (prefers bundled PNG, falls back to ChatGPT.app)
    static let openAITemplateIcon: NSImage? = {
        if let bundledPath = Bundle.main.path(forResource: "openai_template", ofType: "png"),
           let bundled = NSImage(contentsOfFile: bundledPath) {
            return bundled
        }
        let path = "/Applications/ChatGPT.app/Contents/Resources/chatgptTemplate@2x.png"
        return NSImage(contentsOfFile: path)
    }()
}

func drawProviderLogo(_ provider: ProviderID, in rect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current?.imageInterpolation = .high

    let cx = rect.midX
    let cy = rect.midY
    let r = min(rect.width, rect.height) * 0.45

    switch provider {
    case .claude:
        let orange = NSColor(srgbRed: 0.961, green: 0.545, blue: 0.247, alpha: 1.0) // Warm Claude terracotta/orange
        if let tpl = LogoCache.claudeTemplateIcon, tpl.size.width > 0 {
            let tinted = NSImage(size: rect.size, flipped: false) { dst in
                tpl.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1.0)
                orange.setFill()
                dst.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return
        }
        // Fallback Claude starburst
        orange.setStroke()
        orange.setFill()
        for i in 0..<6 {
            let angle = Double(i) * (.pi / 6.0)
            let dx = CGFloat(cos(angle)) * r
            let dy = CGFloat(sin(angle)) * r
            let path = NSBezierPath()
            path.lineWidth = max(1.5, rect.width * 0.11)
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: cx - dx, y: cy - dy))
            path.line(to: NSPoint(x: cx + dx, y: cy + dy))
            path.stroke()
        }

    case .antigravity:
        if let icon = LogoCache.antigravityIcon, icon.size.width > 0 {
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return
        }
        // Fallback bold Antigravity 'A' boomerang arch
        let color = NSColor(srgbRed: 0.25, green: 0.65, blue: 1.0, alpha: 1.0)
        color.setFill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx, y: cy + r))
        path.curve(
            to: NSPoint(x: cx + r * 0.88, y: cy - r * 0.85),
            controlPoint1: NSPoint(x: cx + r * 0.45, y: cy + r * 0.95),
            controlPoint2: NSPoint(x: cx + r * 0.65, y: cy - r * 0.35)
        )
        path.curve(
            to: NSPoint(x: cx, y: cy - r * 0.15),
            controlPoint1: NSPoint(x: cx + r * 0.55, y: cy - r * 0.85),
            controlPoint2: NSPoint(x: cx + r * 0.30, y: cy - r * 0.15)
        )
        path.curve(
            to: NSPoint(x: cx - r * 0.88, y: cy - r * 0.85),
            controlPoint1: NSPoint(x: cx - r * 0.30, y: cy - r * 0.15),
            controlPoint2: NSPoint(x: cx - r * 0.55, y: cy - r * 0.85)
        )
        path.curve(
            to: NSPoint(x: cx, y: cy + r),
            controlPoint1: NSPoint(x: cx - r * 0.65, y: cy - r * 0.35),
            controlPoint2: NSPoint(x: cx - r * 0.45, y: cy + r * 0.95)
        )
        path.close()
        path.fill()

    case .codex:
        if let tpl = LogoCache.openAITemplateIcon, tpl.size.width > 0 {
            let tinted = NSImage(size: rect.size, flipped: false) { dst in
                tpl.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1.0)
                NSColor.white.withAlphaComponent(0.95).setFill()
                dst.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return
        }
        // Fallback hexagon with inner ring
        let color = NSColor(srgbRed: 0.655, green: 0.953, blue: 0.816, alpha: 1.0)
        color.setStroke()
        let hex = NSBezierPath()
        hex.lineWidth = max(1.5, rect.width * 0.11)
        hex.lineJoinStyle = .round
        for i in 0..<6 {
            let angle = Double(i) * (.pi / 3.0) + (.pi / 6.0)
            let pt = NSPoint(x: cx + CGFloat(cos(angle)) * r, y: cy + CGFloat(sin(angle)) * r)
            if i == 0 { hex.move(to: pt) } else { hex.line(to: pt) }
        }
        hex.close()
        hex.stroke()

        let innerR = r * 0.34
        let inner = NSBezierPath(ovalIn: NSRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2))
        inner.lineWidth = max(1.3, rect.width * 0.09)
        inner.stroke()
    }
}

struct ProviderLogoView: View {
    let provider: ProviderID
    var size: CGFloat = 15

    var body: some View {
        Image(nsImage: NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawProviderLogo(provider, in: rect)
            return true
        })
        .frame(width: size, height: size)
    }
}

// MARK: - Self-Signed Localhost URLSession Delegate (for Antigravity local server)

final class LocalhostTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Quota Fetchers

final class QuotaService {
    private let localSession: URLSession
    private var cachedClaudeToken: String?
    private var failedClaudeTokens: Set<String> = []
    private var cachedSafeStorageKey: Data?
    private var didAttemptSafeStorageKey: Bool = false
    private var didAttemptClaudeCodeKeychain: Bool = false
    private var cachedAntigravityEndpoint: (scheme: String, port: Int, csrf: String)?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 5.0
        self.localSession = URLSession(configuration: config, delegate: LocalhostTrustDelegate(), delegateQueue: nil)
    }

    // MARK: 1. Antigravity Fetcher

    func fetchAntigravity(includeClaude: Bool = false) async -> ProviderStatus {
        // 1. Try cached working endpoint first
        if let ep = cachedAntigravityEndpoint {
            if let buckets = await queryAntigravityEndpoint(scheme: ep.scheme, port: ep.port, csrf: ep.csrf, includeClaude: includeClaude) {
                return ProviderStatus(
                    id: .antigravity,
                    subtitle: "Connected",
                    buckets: buckets,
                    errorNote: nil
                )
            }
            cachedAntigravityEndpoint = nil
        }

        // 2. Discover running language_server instances and preserve lsof FD order (FD 7u & 8u are always the main RPC ports)
        let servers = findAntigravityServers()
        guard !servers.isEmpty else {
            return ProviderStatus(
                id: .antigravity,
                subtitle: "App not running",
                buckets: [],
                errorNote: "Open Antigravity IDE to view live model quotas"
            )
        }

        for serverInfo in servers {
            // Take the first 6 ports in exact lsof FD order (plus the 2 lowest port numbers as fallback if not already in prefix)
            var candidatePorts = Array(serverInfo.ports.prefix(6))
            for lowPort in serverInfo.ports.sorted().prefix(2) where !candidatePorts.contains(lowPort) {
                candidatePorts.append(lowPort)
            }

            for port in candidatePorts {
                for scheme in ["https", "http"] {
                    if let buckets = await queryAntigravityEndpoint(scheme: scheme, port: port, csrf: serverInfo.csrfToken, includeClaude: includeClaude) {
                        self.cachedAntigravityEndpoint = (scheme, port, serverInfo.csrfToken)
                        return ProviderStatus(
                            id: .antigravity,
                            subtitle: "Connected",
                            buckets: buckets,
                            errorNote: nil
                        )
                    }
                }
            }
        }

        return ProviderStatus(
            id: .antigravity,
            subtitle: "Server active",
            buckets: [],
            errorNote: "Could not read quota buckets from language_server"
        )
    }

    private func queryAntigravityEndpoint(scheme: String, port: Int, csrf: String, includeClaude: Bool) async -> [QuotaBucket]? {
        if let buckets = await queryAntigravitySummary(scheme: scheme, port: port, csrf: csrf, includeClaude: includeClaude), !buckets.isEmpty {
            return buckets
        }
        if let buckets = await queryAntigravityUserStatus(scheme: scheme, port: port, csrf: csrf, includeClaude: includeClaude), !buckets.isEmpty {
            return buckets
        }
        return nil
    }

    private func findAntigravityServers() -> [(pid: Int, csrfToken: String, ports: [Int])] {
        guard let psOutput = runCommand("/bin/ps", args: ["-ax", "-o", "pid=,command="]) else { return [] }
        var results: [(pid: Int, csrfToken: String, ports: [Int])] = []

        for rawLine in psOutput.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.contains("language_server"),
                  line.localizedCaseInsensitiveContains("antigravity"),
                  line.contains("--csrf_token") else { continue }

            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let pidStr = parts.first, let pid = Int(pidStr) else { continue }
            guard let csrfIdx = parts.firstIndex(of: "--csrf_token"), csrfIdx + 1 < parts.count else { continue }
            let csrf = parts[csrfIdx + 1]

            guard let lsofOut = runCommand("/usr/sbin/lsof", args: ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-Fn"]) else {
                continue
            }

            // Preserve lsof's file descriptor order! FD 7u and 8u (first in lsof output) are the main RPC servers.
            var orderedPorts: [Int] = []
            var seen = Set<Int>()
            for lsofLine in lsofOut.components(separatedBy: .newlines) {
                if lsofLine.hasPrefix("n"), let colon = lsofLine.lastIndex(of: ":") {
                    let portStr = lsofLine[lsofLine.index(after: colon)...]
                    if let port = Int(portStr), !seen.contains(port) {
                        seen.insert(port)
                        orderedPorts.append(port)
                    }
                }
            }
            if !orderedPorts.isEmpty {
                results.append((pid, csrf, orderedPorts))
            }
        }
        return results
    }

    private func queryAntigravitySummary(scheme: String, port: Int, csrf: String, includeClaude: Bool) async -> [QuotaBucket]? {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.setValue(csrf, forHTTPHeaderField: "x-codeium-csrf-token")
        req.httpBody = Data("{}".utf8)

        guard let (data, resp) = try? await localSession.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let root: [String: Any]
        if let qs = json["quotaSummary"] as? [String: Any] {
            root = qs
        } else if let r = json["response"] as? [String: Any] {
            root = r
        } else {
            root = json
        }

        var results: [QuotaBucket] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()

        if let groups = root["groups"] as? [[String: Any]] {
            let filteredGroups = groups.filter { grp in
                if includeClaude { return true }
                let name = (grp["displayName"] as? String ?? "").lowercased()
                return !name.contains("claude")
            }
            for (gIdx, group) in filteredGroups.enumerated() {
                var groupName = (group["displayName"] as? String ?? "Group \(gIdx + 1)")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if groupName.lowercased().hasSuffix(" models") {
                    groupName = String(groupName.dropLast(7))
                }
                let shortGroup = shortenAntigravityName(groupName)

                if let buckets = group["buckets"] as? [[String: Any]], !buckets.isEmpty {
                    var groupBuckets: [(order: Int, bucket: QuotaBucket)] = []
                    for (bIdx, bucket) in buckets.enumerated() {
                        if let disabled = bucket["disabled"] as? Bool, disabled { continue }
                        guard let frac = extractFraction(from: bucket) else { continue }
                        let pct = max(0, min(100, Int((frac * 100.0).rounded())))
                        let rawWindow = (bucket["window"] as? String) ?? (bucket["displayName"] as? String) ?? ""
                        let resetStr = (bucket["resetTime"] as? String) ?? (bucket["reset_time"] as? String)
                        let resetDate = resetStr.flatMap { isoFormatter.date(from: $0) ?? isoFallback.date(from: $0) }

                        let shortWin = normalizeAntigravityWindow(rawWindow: rawWindow, resetDate: resetDate, fallbackIdx: bIdx)
                        let label = (filteredGroups.count == 1 && !shortWin.isEmpty) ? shortWin : (shortWin.isEmpty ? shortGroup : "\(shortGroup) \(shortWin)")
                        let idSuffix = shortWin.isEmpty ? "\(bIdx)" : shortWin.lowercased()
                        let id = "antigravity.\(shortGroup.lowercased()).\(idSuffix)"
                        let sortOrder = (shortWin == "5h") ? 0 : (shortWin == "7d" ? 1 : 2 + bIdx)

                        groupBuckets.append((
                            order: sortOrder,
                            bucket: QuotaBucket(
                                id: id,
                                provider: .antigravity,
                                label: label,
                                remainingPercent: pct,
                                resetDate: resetDate,
                                detail: nil
                            )
                        ))
                    }
                    // Sort so 5h comes before 7d (matching Claude's 5h -> 7d order)
                    groupBuckets.sort { $0.order < $1.order }
                    results.append(contentsOf: groupBuckets.map(\.bucket))
                } else if let frac = extractFraction(from: group) {
                    let pct = max(0, min(100, Int((frac * 100.0).rounded())))
                    let resetStr = (group["resetTime"] as? String) ?? (group["reset_time"] as? String)
                    let resetDate = resetStr.flatMap { isoFormatter.date(from: $0) ?? isoFallback.date(from: $0) }
                    results.append(QuotaBucket(
                        id: "antigravity.\(shortGroup.lowercased())",
                        provider: .antigravity,
                        label: shortGroup,
                        remainingPercent: pct,
                        resetDate: resetDate,
                        detail: nil
                    ))
                }
            }
        }
        return results.isEmpty ? nil : results
    }

    private func normalizeAntigravityWindow(rawWindow: String, resetDate: Date?, fallbackIdx: Int) -> String {
        let lower = rawWindow.lowercased()
        if lower.contains("5h") || lower.contains("5-hour") || lower.contains("hour") {
            return "5h"
        }
        if lower.contains("7d") || lower.contains("week") {
            return "7d"
        }
        if let resetDate = resetDate {
            let hours = resetDate.timeIntervalSinceNow / 3600.0
            if hours > 0 && hours <= 12 {
                return "5h"
            } else if hours > 12 {
                return "7d"
            }
        }
        if !rawWindow.isEmpty && rawWindow.count <= 4 {
            return rawWindow
        }
        return fallbackIdx == 0 ? "7d" : "5h"
    }

    private func queryAntigravityUserStatus(scheme: String, port: Int, csrf: String, includeClaude: Bool) async -> [QuotaBucket]? {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.setValue(csrf, forHTTPHeaderField: "x-codeium-csrf-token")
        req.httpBody = Data("{}".utf8)

        guard let (data, resp) = try? await localSession.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let userStatus = (json["userStatus"] as? [String: Any])
            ?? ((json["response"] as? [String: Any])?["userStatus"] as? [String: Any])
            ?? json

        guard let cascade = userStatus["cascadeModelConfigData"] as? [String: Any],
              let configs = cascade["clientModelConfigs"] as? [[String: Any]] else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()

        var seenFamilies: [String: QuotaBucket] = [:]
        var orderedKeys: [String] = []

        for cfg in configs {
            guard let label = cfg["label"] as? String,
                  (includeClaude || !label.lowercased().contains("claude")),
                  let quotaInfo = cfg["quotaInfo"] as? [String: Any],
                  let frac = extractFraction(from: quotaInfo) else { continue }
            let pct = max(0, min(100, Int((frac * 100.0).rounded())))
            let family = shortenAntigravityName(label)
            let resetStr = (quotaInfo["resetTime"] as? String) ?? (quotaInfo["reset_time"] as? String)
            let resetDate = resetStr.flatMap { isoFormatter.date(from: $0) ?? isoFallback.date(from: $0) }

            let bucket = QuotaBucket(
                id: "antigravity.\(family.lowercased())",
                provider: .antigravity,
                label: family,
                remainingPercent: pct,
                resetDate: resetDate,
                detail: nil
            )
            if let existing = seenFamilies[family] {
                if pct < existing.remainingPercent {
                    seenFamilies[family] = bucket
                }
            } else {
                seenFamilies[family] = bucket
                orderedKeys.append(family)
            }
        }

        let list = orderedKeys.compactMap { seenFamilies[$0] }
        return list.isEmpty ? nil : list
    }

    private func extractFraction(from dict: [String: Any]) -> Double? {
        for key in ["remainingFraction", "remaining_fraction"] {
            if let num = dict[key] as? NSNumber { return num.doubleValue }
            if let str = dict[key] as? String, let val = Double(str) { return val }
        }
        if let rem = dict["remaining"] as? [String: Any] {
            for key in ["remainingFraction", "remaining_fraction"] {
                if let num = rem[key] as? NSNumber { return num.doubleValue }
                if let str = rem[key] as? String, let val = Double(str) { return val }
            }
        }
        return nil
    }

    private func shortenAntigravityName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("claude") { return "Claude" }
        if lower.contains("flash") { return "Flash" }
        if lower.contains("pro") || lower.contains("gemini") { return "Gemini" }
        return String(name.prefix(7))
    }

    // MARK: 2. Claude Fetcher

    func fetchClaude() async -> ProviderStatus {
        // 1. Try cached token first if available
        if let cached = cachedClaudeToken,
           let status = await fetchClaudeOAuthUsage(token: cached) {
            return status
        }
        cachedClaudeToken = nil

        // 2. Discover candidate OAuth tokens from ~/.claude/.credentials.json, Keychain, or Claude Desktop config.json
        let tokens = readCandidateClaudeOAuthTokens()
        for token in tokens where !failedClaudeTokens.contains(token) {
            if let status = await fetchClaudeOAuthUsage(token: token) {
                self.cachedClaudeToken = token
                return status
            } else {
                failedClaudeTokens.insert(token)
            }
        }

        // 3. Try Claude Desktop plan-usage-history.json if non-empty
        if let desktopBuckets = readClaudeDesktopPlanHistory(), !desktopBuckets.isEmpty {
            return ProviderStatus(
                id: .claude,
                subtitle: readClaudePlanName() ?? "Desktop",
                buckets: desktopBuckets,
                errorNote: nil
            )
        }

        // 4. Check if Claude is installed/configured locally before falling back to local JSONL token estimation
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let hasClaudeSetup = fm.fileExists(atPath: home + "/.claude")
            || fm.fileExists(atPath: home + "/.claude.json")
            || fm.fileExists(atPath: home + "/Library/Application Support/Claude")
        if !hasClaudeSetup {
            return ProviderStatus(
                id: .claude,
                subtitle: "Not configured",
                buckets: [],
                errorNote: "Log in to Claude Desktop or Claude Code"
            )
        }

        // 5. Fallback: compute rolling 5h & 7d usage from local ~/.claude/projects/*.jsonl
        let localUsage = readLocalClaudeProjectTokens()
        let planName = readClaudePlanName() ?? "Pro"
        let pct5h = max(0, min(100, 100 - Int((Double(localUsage.tokens5h) / 500_000.0) * 100.0)))
        let pct7d = max(0, min(100, 100 - Int((Double(localUsage.tokens7d) / 5_000_000.0) * 100.0)))

        let buckets: [QuotaBucket] = [
            QuotaBucket(
                id: "claude.5h",
                provider: .claude,
                label: "5h",
                remainingPercent: pct5h,
                resetDate: localUsage.oldestIn5h?.addingTimeInterval(5 * 3600),
                detail: "\(formatTokens(localUsage.tokens5h))"
            ),
            QuotaBucket(
                id: "claude.7d",
                provider: .claude,
                label: "7d",
                remainingPercent: pct7d,
                resetDate: nil,
                detail: "\(formatTokens(localUsage.tokens7d))"
            )
        ]

        return ProviderStatus(
            id: .claude,
            subtitle: "\(planName) (est.)",
            buckets: buckets,
            errorNote: nil
        )
    }

    private func readCandidateClaudeOAuthTokens() -> [String] {
        var results: [String] = []

        // A. ~/.claude/.credentials.json
        let credPath = NSHomeDirectory() + "/.claude/.credentials.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: credPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            results.append(token)
        }

        // B. "Claude Code-credentials" in Keychain (only attempt once per session to avoid repeated prompts)
        if !didAttemptClaudeCodeKeychain {
            didAttemptClaudeCodeKeychain = true
            if let rawCreds = runCommand("/usr/bin/security", args: ["find-generic-password", "-s", "Claude Code-credentials", "-w"])?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawCreds.isEmpty,
               let data = rawCreds.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let oauth = json["claudeAiOauth"] as? [String: Any],
               let token = oauth["accessToken"] as? String, !token.isEmpty {
                results.append(token)
            }
        }

        // C. Claude Desktop's encrypted oauth:tokenCacheV2 / oauth:tokenCache in ~/Library/Application Support/Claude/config.json
        let desktopTokens = readClaudeDesktopEncryptedOAuthTokens()
        for t in desktopTokens where !results.contains(t) {
            results.append(t)
        }

        return results
    }

    private func readClaudeDesktopEncryptedOAuthTokens() -> [String] {
        let configPath = NSHomeDirectory() + "/Library/Application Support/Claude/config.json"
        guard let configData = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let configJSON = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            return []
        }

        guard let aesKey = getClaudeSafeStorageAESKey() else { return [] }

        var scoredTokens: [(score: Int, expiresAt: Double, token: String)] = []

        for cacheField in ["oauth:tokenCacheV2", "oauth:tokenCache"] {
            guard let b64 = configJSON[cacheField] as? String,
                  let encrypted = Data(base64Encoded: b64),
                  let decryptedJSONStr = decryptElectronSafeStorage(encrypted: encrypted, key: aesKey),
                  let decData = decryptedJSONStr.data(using: .utf8),
                  let map = try? JSONSerialization.jsonObject(with: decData) as? [String: Any] else {
                continue
            }

            for (k, v) in map {
                guard let entry = v as? [String: Any],
                      let token = entry["token"] as? String, !token.isEmpty else { continue }
                let expires = (entry["expiresAt"] as? NSNumber)?.doubleValue ?? 0
                var score = 0
                if k.contains("claude_code") { score += 10 }
                if k.contains("user:profile") { score += 5 }
                if k.contains("user:inference") { score += 3 }
                scoredTokens.append((score, expires, token))
            }
        }

        scoredTokens.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.expiresAt > $1.expiresAt
        }
        return scoredTokens.map(\.token)
    }

    private func getClaudeSafeStorageAESKey() -> Data? {
        if let key = cachedSafeStorageKey { return key }
        if didAttemptSafeStorageKey { return nil }
        didAttemptSafeStorageKey = true

        guard let password = runCommand("/usr/bin/security", args: ["find-generic-password", "-s", "Claude Safe Storage", "-w"])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !password.isEmpty else {
            return nil
        }

        let salt = Array("saltysalt".utf8)
        let passBytes = Array(password.utf8)
        var derivedKey = [UInt8](repeating: 0, count: kCCKeySizeAES128)

        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
             password,
            passBytes.count,
            salt,
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            1003,
            &derivedKey,
            derivedKey.count
        )
        guard status == kCCSuccess else { return nil }
        let keyData = Data(derivedKey)
        cachedSafeStorageKey = keyData
        return keyData
    }

    private func decryptElectronSafeStorage(encrypted: Data, key: Data) -> String? {
        // Electron safeStorage on macOS prepends "v10" (3 bytes) to AES-128-CBC ciphertext with a 16-space IV
        guard encrypted.count > 3 else { return nil }
        let prefix = encrypted.prefix(3)
        guard String(data: prefix, encoding: .utf8) == "v10" else { return nil }

        let cipher = Data(encrypted.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var outBuffer = [UInt8](repeating: 0, count: cipher.count + kCCBlockSizeAES128)
        var outLength: size_t = 0

        let status = cipher.withUnsafeBytes { cipherBytes in
            key.withUnsafeBytes { keyBytes in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    keyBytes.baseAddress,
                    key.count,
                    iv,
                    cipherBytes.baseAddress,
                    cipher.count,
                    &outBuffer,
                    outBuffer.count,
                    &outLength
                )
            }
        }
        guard status == kCCSuccess else { return nil }
        return String(bytes: outBuffer.prefix(outLength), encoding: .utf8)
    }

    private func fetchClaudeOAuthUsage(token: String) async -> ProviderStatus? {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("claude-code/2.1.317", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let buckets = parseClaudeUsageJSON(json)
        guard !buckets.isEmpty else { return nil }
        return ProviderStatus(
            id: .claude,
            subtitle: readClaudePlanName() ?? "Pro",
            buckets: buckets,
            errorNote: nil
        )
    }

    private func parseClaudeUsageJSON(_ json: [String: Any]) -> [QuotaBucket] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()

        var bucket5h: QuotaBucket?
        var bucket7d: QuotaBucket?

        if let fh = json["five_hour"] as? [String: Any],
           let used = extractPercentValue(from: fh) {
            let rem = max(0, min(100, Int((100.0 - used).rounded())))
            let resetStr = fh["resets_at"] as? String
            let resetDate = resetStr.flatMap { isoFormatter.date(from: $0) ?? isoFallback.date(from: $0) }
            bucket5h = QuotaBucket(
                id: "claude.5h",
                provider: .claude,
                label: "5h",
                remainingPercent: rem,
                resetDate: resetDate,
                detail: nil
            )
        }

        if let sd = json["seven_day"] as? [String: Any],
           let used = extractPercentValue(from: sd) {
            let rem = max(0, min(100, Int((100.0 - used).rounded())))
            let resetStr = sd["resets_at"] as? String
            let resetDate = resetStr.flatMap { isoFormatter.date(from: $0) ?? isoFallback.date(from: $0) }
            bucket7d = QuotaBucket(
                id: "claude.7d",
                provider: .claude,
                label: "7d",
                remainingPercent: rem,
                resetDate: resetDate,
                detail: nil
            )
        }

        // Also check new `limits` array format used by Claude Desktop
        if let limits = json["limits"] as? [[String: Any]] {
            for item in limits {
                guard let used = extractPercentValue(from: item) else { continue }
                let rem = max(0, min(100, Int((100.0 - used).rounded())))
                let kind = (item["kind"] as? String ?? "").lowercased()
                let group = (item["group"] as? String ?? "").lowercased()
                let resetStr = item["resets_at"] as? String
                let resetDate = resetStr.flatMap { isoFormatter.date(from: $0) ?? isoFallback.date(from: $0) }

                if kind == "session" || group == "session" || kind.contains("five_hour") {
                    bucket5h = QuotaBucket(
                        id: "claude.5h",
                        provider: .claude,
                        label: "5h",
                        remainingPercent: rem,
                        resetDate: resetDate,
                        detail: nil
                    )
                } else if kind == "weekly_all" || group == "weekly" || kind.contains("seven_day") {
                    if bucket7d == nil || kind == "weekly_all" {
                        bucket7d = QuotaBucket(
                            id: "claude.7d",
                            provider: .claude,
                            label: "7d",
                            remainingPercent: rem,
                            resetDate: resetDate,
                            detail: nil
                        )
                    }
                }
            }
        }

        return [bucket5h, bucket7d].compactMap { $0 }
    }

    private func extractPercentValue(from dict: [String: Any]) -> Double? {
        for key in ["utilization", "percent", "used_percent", "used_percentage"] {
            if let num = dict[key] as? NSNumber { return num.doubleValue }
            if let str = dict[key] as? String, let val = Double(str) { return val }
        }
        return nil
    }

    private func readClaudeDesktopPlanHistory() -> [QuotaBucket]? {
        let path = NSHomeDirectory() + "/Library/Application Support/Claude/plan-usage-history.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = json["samples"] as? [[String: Any]] else {
            return nil
        }

        for sample in samples.reversed() {
            guard let u = sample["u"] as? [String: Any], !u.isEmpty else { continue }
            var buckets: [QuotaBucket] = []
            if let fh = (u["fh"] as? NSNumber)?.doubleValue {
                let pct = fh <= 1.0 ? Int(((1.0 - fh) * 100.0).rounded()) : Int((100.0 - fh).rounded())
                buckets.append(QuotaBucket(
                    id: "claude.5h",
                    provider: .claude,
                    label: "5h",
                    remainingPercent: max(0, min(100, pct)),
                    resetDate: nil,
                    detail: nil
                ))
            }
            if let sd = (u["sd"] as? NSNumber)?.doubleValue {
                let pct = sd <= 1.0 ? Int(((1.0 - sd) * 100.0).rounded()) : Int((100.0 - sd).rounded())
                buckets.append(QuotaBucket(
                    id: "claude.7d",
                    provider: .claude,
                    label: "7d",
                    remainingPercent: max(0, min(100, pct)),
                    resetDate: nil,
                    detail: nil
                ))
            }
            if !buckets.isEmpty { return buckets }
        }
        return nil
    }

    private func readClaudePlanName() -> String? {
        let path = NSHomeDirectory() + "/.claude.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acct = json["oauthAccount"] as? [String: Any],
              let orgType = acct["organizationType"] as? String else {
            return nil
        }
        if orgType.contains("pro") { return "Pro" }
        if orgType.contains("max") { return "Max" }
        if orgType.contains("team") { return "Team" }
        return orgType
    }

    private func readLocalClaudeProjectTokens() -> (tokens5h: Int, tokens7d: Int, oldestIn5h: Date?) {
        let root = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/projects")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0, nil)
        }

        let now = Date()
        let cutoff5h = now.addingTimeInterval(-5 * 3600)
        let cutoff7d = now.addingTimeInterval(-7 * 24 * 3600)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()

        var tokens5h = 0
        var tokens7d = 0
        var oldest5h: Date?
        var seenReqIDs = Set<String>()

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            if let mod = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               mod < cutoff7d {
                continue
            }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) where line.contains("\"usage\"") {
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
                if let reqId = obj["requestId"] as? String {
                    if seenReqIDs.contains(reqId) { continue }
                    seenReqIDs.insert(reqId)
                }
                guard let tsStr = obj["timestamp"] as? String,
                      let ts = isoFormatter.date(from: tsStr) ?? isoFallback.date(from: tsStr),
                      ts >= cutoff7d else { continue }

                let msg = obj["message"] as? [String: Any]
                guard let usage = (msg?["usage"] as? [String: Any]) ?? (obj["usage"] as? [String: Any]) else { continue }
                let input = (usage["input_tokens"] as? Int) ?? 0
                let output = (usage["output_tokens"] as? Int) ?? 0
                let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
                let weighted = input + output + (cacheCreate / 4)
                tokens7d += weighted
                if ts >= cutoff5h {
                    tokens5h += weighted
                    if oldest5h.map({ ts < $0 }) ?? true {
                        oldest5h = ts
                    }
                }
            }
        }
        return (tokens5h, tokens7d, oldest5h)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM tok", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fk tok", Double(count) / 1_000.0)
        }
        return "\(count) tok"
    }

    // MARK: 3. Codex Fetcher

    func fetchCodex() -> ProviderStatus {
        let sessionsRoot = URL(fileURLWithPath: NSHomeDirectory() + "/.codex/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ProviderStatus(id: .codex, subtitle: "No sessions", buckets: [], errorNote: nil)
        }

        var jsonlFiles: [(url: URL, mod: Date)] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            let mod = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            jsonlFiles.append((fileURL, mod))
        }
        jsonlFiles.sort { $0.mod > $1.mod }

        for entry in jsonlFiles.prefix(15) {
            guard let content = try? String(contentsOf: entry.url, encoding: .utf8) else { continue }
            var latestRL: [String: Any]?
            for line in content.components(separatedBy: .newlines) where line.contains("\"rate_limits\"") {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = obj["payload"] as? [String: Any],
                      let rl = payload["rate_limits"] as? [String: Any] else { continue }
                latestRL = rl
            }
            if let rl = latestRL {
                var buckets: [QuotaBucket] = []
                let plan = (rl["plan_type"] as? String)?.capitalized ?? "Active"

                if let primary = rl["primary"] as? [String: Any],
                   let used = (primary["used_percent"] as? NSNumber)?.doubleValue {
                    let rem = max(0, min(100, Int((100.0 - used).rounded())))
                    let winMins = (primary["window_minutes"] as? Int) ?? 300
                    let shortLbl = codexWindowLabel(minutes: winMins)
                    let resetDate = (primary["resets_at"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
                    buckets.append(QuotaBucket(
                        id: "codex.primary",
                        provider: .codex,
                        label: shortLbl,
                        remainingPercent: rem,
                        resetDate: resetDate,
                        detail: nil
                    ))
                }

                if let secondary = rl["secondary"] as? [String: Any],
                   let used = (secondary["used_percent"] as? NSNumber)?.doubleValue {
                    let rem = max(0, min(100, Int((100.0 - used).rounded())))
                    let winMins = (secondary["window_minutes"] as? Int) ?? 10080
                    let shortLbl = codexWindowLabel(minutes: winMins)
                    let resetDate = (secondary["resets_at"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
                    buckets.append(QuotaBucket(
                        id: "codex.secondary",
                        provider: .codex,
                        label: shortLbl,
                        remainingPercent: rem,
                        resetDate: resetDate,
                        detail: nil
                    ))
                }

                return ProviderStatus(
                    id: .codex,
                    subtitle: "\(plan) plan",
                    buckets: buckets,
                    errorNote: nil
                )
            }
        }

        return ProviderStatus(id: .codex, subtitle: "No recent rate limits", buckets: [], errorNote: nil)
    }

    private func codexWindowLabel(minutes: Int) -> String {
        if minutes <= 360 {
            return "5h"
        } else if minutes <= 10500 {
            return "7d"
        } else {
            let days = max(1, minutes / 1440)
            return "\(days)d"
        }
    }

    // MARK: Process Helper

    private func runCommand(_ launchPath: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - ViewModel & Menu Bar Renderer

@MainActor
final class QuotaViewModel: ObservableObject {
    @Published var statuses: [ProviderStatus] = []
    @Published var pinnedBucketIDs: Set<String>
    @Published var enabledProviders: Set<ProviderID>
    @Published var includeAntigravityClaude: Bool
    @Published var launchAtLogin: Bool
    @Published var showSettings: Bool = false
    @Published var lastUpdated: Date = Date()
    @Published var isRefreshing: Bool = false

    private let service = QuotaService()
    private let defaultsKey = "pinnedBucketIDs_v2"
    private let enabledProvidersKey = "enabledProviders_v1"
    private let includeAgyClaudeKey = "includeAntigravityClaude_v1"
    var onMenuBarNeedsUpdate: (() -> Void)?

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.local.AIQuotaBar.plist")
    }

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) {
            self.pinnedBucketIDs = Set(saved)
        } else {
            // Sensible default: pin Claude 5h + 7d and Antigravity Gemini 5h + 7d
            self.pinnedBucketIDs = [
                "claude.5h",
                "claude.7d",
                "antigravity.gemini.5h",
                "antigravity.gemini.7d"
            ]
        }

        if let savedProviders = UserDefaults.standard.stringArray(forKey: enabledProvidersKey) {
            self.enabledProviders = Set(savedProviders.compactMap(ProviderID.init(rawValue:)))
        } else {
            self.enabledProviders = Set(ProviderID.allCases)
        }

        self.includeAntigravityClaude = UserDefaults.standard.bool(forKey: includeAgyClaudeKey)
        self.launchAtLogin = FileManager.default.fileExists(atPath: Self.launchAgentURL.path)
            || (SMAppService.mainApp.status == .enabled)
    }

    func isProviderEnabled(_ provider: ProviderID) -> Bool {
        enabledProviders.contains(provider)
    }

    func toggleProvider(_ provider: ProviderID) {
        if enabledProviders.contains(provider) {
            // Keep at least one provider enabled or allow disabling any
            enabledProviders.remove(provider)
        } else {
            enabledProviders.insert(provider)
        }
        UserDefaults.standard.set(enabledProviders.map(\.rawValue), forKey: enabledProvidersKey)
        statuses.removeAll { !enabledProviders.contains($0.id) }
        onMenuBarNeedsUpdate?()
        Task { await refresh() }
    }

    func toggleIncludeAntigravityClaude() {
        includeAntigravityClaude.toggle()
        UserDefaults.standard.set(includeAntigravityClaude, forKey: includeAgyClaudeKey)
        Task { await refresh() }
    }

    func toggleLaunchAtLogin() {
        let plistURL = Self.launchAgentURL
        if launchAtLogin {
            try? FileManager.default.removeItem(at: plistURL)
            try? SMAppService.mainApp.unregister()
            launchAtLogin = false
        } else {
            let execPath = Bundle.main.executablePath ?? "/Applications/AIQuotaBar.app/Contents/MacOS/AIQuotaBar"
            let plist: [String: Any] = [
                "Label": "com.local.AIQuotaBar",
                "ProgramArguments": [execPath],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]
            let dir = plistURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: plistURL, options: .atomic)
            }
            launchAtLogin = FileManager.default.fileExists(atPath: plistURL.path)
        }
    }

    func isPinned(_ bucket: QuotaBucket) -> Bool {
        pinnedBucketIDs.contains(bucket.id)
    }

    func togglePin(_ bucket: QuotaBucket) {
        if pinnedBucketIDs.contains(bucket.id) {
            pinnedBucketIDs.remove(bucket.id)
        } else {
            pinnedBucketIDs.insert(bucket.id)
        }
        UserDefaults.standard.set(Array(pinnedBucketIDs), forKey: defaultsKey)
        onMenuBarNeedsUpdate?()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        let wantClaude = enabledProviders.contains(.claude)
        let wantAgy = enabledProviders.contains(.antigravity)
        let wantCodex = enabledProviders.contains(.codex)
        let showAgyClaude = includeAntigravityClaude

        async let claudeOpt: ProviderStatus? = wantClaude ? await service.fetchClaude() : nil
        async let agyOpt: ProviderStatus? = wantAgy ? await service.fetchAntigravity(includeClaude: showAgyClaude) : nil
        let codexOpt: ProviderStatus? = wantCodex ? service.fetchCodex() : nil

        let cStatus = await claudeOpt
        let aStatus = await agyOpt

        if let aStatus = aStatus,
           UserDefaults.standard.stringArray(forKey: defaultsKey) == nil,
           let firstAgy = aStatus.buckets.first,
           !aStatus.buckets.contains(where: { pinnedBucketIDs.contains($0.id) }) {
            pinnedBucketIDs.insert(firstAgy.id)
        }

        self.statuses = [cStatus, aStatus, codexOpt].compactMap { $0 }
        self.lastUpdated = Date()
        self.isRefreshing = false
        onMenuBarNeedsUpdate?()
    }

    // Renders a frameless, full-height native menu bar NSImage with provider logos & colored percentages
    func renderMenuBarImage() -> NSImage {
        struct Segment {
            let provider: ProviderID
            let percentages: [Int]
        }

        var segments: [Segment] = []
        for status in statuses where enabledProviders.contains(status.id) {
            let pinned = status.buckets.filter { pinnedBucketIDs.contains($0.id) }
            if !pinned.isEmpty {
                segments.append(Segment(provider: status.id, percentages: pinned.map(\.remainingPercent)))
            }
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        let slashSpaceAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .regular)
        ]
        let slashAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.45)
        ]

        let height: CGFloat = 22.0
        let iconSize: CGFloat = 16.5
        let iconTextGap: CGFloat = 5.0
        let segmentGap: CGFloat = 13.0
        let horizontalPad: CGFloat = 2.0

        if segments.isEmpty {
            let fallbackSize = NSSize(width: 18, height: height)
            let fallbackProvider = ProviderID.allCases.first(where: { enabledProviders.contains($0) }) ?? .antigravity
            return NSImage(size: fallbackSize, flipped: false) { _ in
                drawProviderLogo(fallbackProvider, in: NSRect(x: 1.0, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
                return true
            }
        }

        var builtSegments: [(provider: ProviderID, attr: NSAttributedString, size: NSSize)] = []
        var totalWidth: CGFloat = horizontalPad * 2

        for (idx, seg) in segments.enumerated() {
            let mas = NSMutableAttributedString()
            for (pIdx, pct) in seg.percentages.enumerated() {
                if pIdx > 0 {
                    mas.append(NSAttributedString(string: " ", attributes: slashSpaceAttrs))
                    mas.append(NSAttributedString(string: "/", attributes: slashAttrs))
                    mas.append(NSAttributedString(string: " ", attributes: slashSpaceAttrs))
                }
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: quotaNSColor(for: pct)
                ]
                mas.append(NSAttributedString(string: "\(pct)%", attributes: attrs))
            }
            let textSize = mas.size()
            builtSegments.append((seg.provider, mas, textSize))
            totalWidth += iconSize + iconTextGap + ceil(textSize.width)
            if idx < segments.count - 1 {
                totalWidth += segmentGap
            }
        }

        let image = NSImage(size: NSSize(width: ceil(totalWidth), height: height), flipped: false) { _ in
            var x: CGFloat = horizontalPad
            for (idx, item) in builtSegments.enumerated() {
                let logoRect = NSRect(x: x, y: (height - iconSize) / 2.0, width: iconSize, height: iconSize)
                drawProviderLogo(item.provider, in: logoRect)
                x += iconSize + iconTextGap

                let textY = (height - item.size.height) / 2.0 - 0.5
                item.attr.draw(at: NSPoint(x: x, y: textY))
                x += ceil(item.size.width)

                if idx < builtSegments.count - 1 {
                    x += segmentGap
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

// MARK: - Popover SwiftUI View

struct QuotaPopoverView: View {
    @ObservedObject var vm: QuotaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Text("AI Quotas")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                    Text("Pinned to menu bar")
                        .font(.system(size: 10.5))
                }
                .foregroundColor(.secondary)

                Button(action: { vm.showSettings.toggle() }) {
                    Image(systemName: vm.showSettings ? "gearshape.fill" : "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(vm.showSettings ? .accentColor : .secondary)
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(vm.showSettings ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help("Configure enabled providers & startup settings")
            }

            if vm.showSettings {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ENABLED INTEGRATIONS")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 6) {
                        ForEach(ProviderID.allCases) { provider in
                            let enabled = vm.isProviderEnabled(provider)
                            Button(action: { vm.toggleProvider(provider) }) {
                                HStack(spacing: 4.5) {
                                    ProviderLogoView(provider: provider, size: 13)
                                    Text(provider.displayName)
                                        .font(.system(size: 11, weight: enabled ? .semibold : .regular))
                                        .lineLimit(1)
                                    Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10))
                                        .foregroundColor(enabled ? .accentColor : .secondary)
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(enabled ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(enabled ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if vm.isProviderEnabled(.antigravity) {
                        Button(action: { vm.toggleIncludeAntigravityClaude() }) {
                            HStack(spacing: 6) {
                                Image(systemName: vm.includeAntigravityClaude ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundColor(vm.includeAntigravityClaude ? .accentColor : .secondary)
                                Text("Show Claude models inside Antigravity")
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary.opacity(0.9))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: { vm.toggleLaunchAtLogin() }) {
                        HStack(spacing: 6) {
                            Image(systemName: vm.launchAtLogin ? "checkmark.square.fill" : "square")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(vm.launchAtLogin ? .accentColor : .secondary)
                            Text("Launch AIQuotaBar at login")
                                .font(.system(size: 11))
                                .foregroundColor(.primary.opacity(0.9))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            Divider()

            if vm.statuses.isEmpty {
                Text("All providers disabled. Click ⚙️ above to enable.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(vm.statuses.enumerated()), id: \.element.id) { idx, status in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            ProviderLogoView(provider: status.id, size: 15.5)
                            Text(status.id.displayName)
                                .font(.system(size: 12, weight: .semibold))
                            Text("· \(status.subtitle)")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        if status.buckets.isEmpty {
                            Text(status.errorNote ?? "No active quota data")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 1)
                        } else {
                            let pillWidth: CGFloat = status.buckets.contains(where: { $0.label.count > 4 }) ? 92 : 62
                            ForEach(status.buckets) { bucket in
                                let pinned = vm.isPinned(bucket)
                                HStack(spacing: 7) {
                                    Button(action: { vm.togglePin(bucket) }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: pinned ? "pin.fill" : "pin")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(pinned ? Color.white : Color.secondary)
                                            Text(bucket.label)
                                                .font(.system(size: 11, weight: pinned ? .semibold : .regular))
                                                .foregroundColor(pinned ? Color.white : Color.primary.opacity(0.85))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2.5)
                                        .frame(width: pillWidth, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(pinned ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.07))
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    // Compact Single-Line Progress Bar
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.primary.opacity(0.12))
                                                .frame(height: 5.5)
                                            Capsule()
                                                .fill(quotaSwiftUIColor(for: bucket.remainingPercent))
                                                .frame(width: max(4, geo.size.width * CGFloat(bucket.remainingPercent) / 100.0), height: 5.5)
                                        }
                                        .frame(maxHeight: .infinity, alignment: .center)
                                    }
                                    .frame(height: 16)

                                    // Inline Reset Countdown
                                    Text(bucket.shortResetText)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 52, alignment: .trailing)

                                    // Colored Percentage
                                    Text("\(bucket.remainingPercent)%")
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                        .foregroundColor(quotaSwiftUIColor(for: bucket.remainingPercent))
                                        .frame(width: 38, alignment: .trailing)
                                }
                            }
                        }
                    }

                    if idx < vm.statuses.count - 1 {
                        Divider()
                    }
                }
            }

            Divider()

            // Footer Controls
            HStack {
                Button(action: {
                    Task { await vm.refresh() }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text(vm.isRefreshing ? "Refreshing…" : "Refresh")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(vm.isRefreshing)

                Spacer()

                Text(vm.lastUpdated, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(11)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let vm = QuotaViewModel()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        let hostingController = NSHostingController(rootView: QuotaPopoverView(vm: vm))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = hostingController

        vm.onMenuBarNeedsUpdate = { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }
            button.image = self.vm.renderMenuBarImage()
        }

        vm.onMenuBarNeedsUpdate?()

        Task {
            await vm.refresh()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.vm.refresh()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.vm.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await self.vm.refresh()
            }
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            if Date().timeIntervalSince(vm.lastUpdated) > 10 {
                Task { await vm.refresh() }
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
