import AppKit
import Foundation
import Security

/// A version published on GitHub.
struct Release {
    let version: String     // "0.2.0" (without the leading "v")
    let pageURL: URL        // release page with the notes
    let zipURL: URL         // Present-Perfect-macOS.zip
}

enum UpdateError: Error, CustomStringConvertible {
    case http(Int)
    case badResponse
    case unzip
    case noApp
    case notSigned
    case notNotarized
    case notNewer(String)

    var description: String {
        switch self {
        case .http(let code): return "GitHub answered with error \(code)"
        case .badResponse: return "unexpected answer from GitHub"
        case .unzip: return "the download could not be unpacked"
        case .noApp: return "the download does not contain the app"
        case .notSigned: return "the download is not signed with the same Developer ID"
        case .notNotarized: return "the download is not notarized by Apple"
        case .notNewer(let v): return "the download (version \(v)) is not newer"
        }
    }
}

/// Finds, checks and installs new versions from GitHub Releases.
/// An update is only installed when it is signed with the same Developer ID as this app
/// and notarized by Apple. Nothing about the user is sent: it only reads the public release.
enum Updater {
    static let repository = "Filhgd/Present-Perfect-Mac"
    static let assetName = "Present-Perfect-macOS.zip"
    static let bundleID = "be.haegdorens.presentperfect"

    // MARK: Versions

    /// "v1.10.2" -> [1, 10, 2]; anything after the digits of a part is ignored ("2-beta" -> 2).
    static func numbers(_ version: String) -> [Int] {
        stripV(version).split(separator: ".").map { part in Int(part.prefix(while: { $0.isNumber })) ?? 0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func stripV(_ tag: String) -> String {
        var v = tag.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return v
    }

    // MARK: Finding the latest release

    static func fetchLatest(completion: @escaping (Result<Release, Error>) -> Void) {
        let api = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PresentPerfect/\(Build.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, (response as? HTTPURLResponse)?.statusCode == 200, let release = try? parse(data) {
                completion(.success(release))
            } else {
                // GitHub limits API requests per network (a school shares one address): use the release page instead.
                fetchLatestFromPage(completion: completion)
            }
        }.resume()
    }

    static func parse(_ data: Data) throws -> Release {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap({ URL(string: $0) }) else {
            throw UpdateError.badResponse
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String) == assetName }
            .flatMap { ($0["browser_download_url"] as? String).flatMap { URL(string: $0) } }
        return Release(version: stripV(tag), pageURL: page, zipURL: zip ?? downloadURL(tag: tag))
    }

    /// github.com/<repo>/releases/latest redirects to the page of the latest tag.
    private static func fetchLatestFromPage(completion: @escaping (Result<Release, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://github.com/\(repository)/releases/latest")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "HEAD"
        URLSession.shared.dataTask(with: request) { _, response, error in
            guard let url = response?.url, let range = url.path.range(of: "/releases/tag/") else {
                completion(.failure(error ?? UpdateError.badResponse))
                return
            }
            let tag = String(url.path[range.upperBound...])
            completion(.success(Release(version: stripV(tag), pageURL: url, zipURL: downloadURL(tag: tag))))
        }.resume()
    }

    private static func downloadURL(tag: String) -> URL {
        URL(string: "https://github.com/\(repository)/releases/download/\(tag)/\(assetName)")!
    }

    // MARK: Downloading and checking

    static func download(_ url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        URLSession.shared.downloadTask(with: url) { temp, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let temp, status == 200 else {
                completion(.failure(error ?? UpdateError.http(status)))
                return
            }
            let zip = FileManager.default.temporaryDirectory.appendingPathComponent("PresentPerfect-\(UUID().uuidString).zip")
            do {
                try FileManager.default.moveItem(at: temp, to: zip)
                completion(.success(zip))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    /// Unpacks the zip and returns the app inside, after checking its signature.
    static func unpackAndVerify(zip: URL, teamID: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PresentPerfect-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path]).status == 0 else { throw UpdateError.unzip }
        let items = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        guard let app = items.first(where: { $0.pathExtension == "app" }) else { throw UpdateError.noApp }
        try verify(app: app, teamID: teamID)
        return app
    }

    /// Team ID of the Developer ID that signed this running app; nil for a build signed ad hoc.
    static func ownTeamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// The app must be Present Perfect, signed with a Developer ID certificate of `teamID`,
    /// intact, and accepted by Gatekeeper as notarized.
    static func verify(app: URL, teamID: String) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError.notSigned
        }
        let text = "identifier \"\(bundleID)\" and anchor apple generic"
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(teamID)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, SecCSFlags(), &requirement) == errSecSuccess, let requirement else {
            throw UpdateError.notSigned
        }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSStrictValidate) | UInt32(kSecCSCheckNestedCode))
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else { throw UpdateError.notSigned }
        let gatekeeper = run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose", app.path])
        guard gatekeeper.status == 0, gatekeeper.output.contains("Notarized Developer ID") else { throw UpdateError.notNotarized }
    }

    static func version(of app: URL) -> String {
        Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: Installing

    /// Where the running app lives, if it can replace itself there.
    static var installTarget: URL? {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app", !app.path.contains("/AppTranslocation/") else { return nil }
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: app.deletingLastPathComponent().path), fm.isWritableFile(atPath: app.path) else { return nil }
        return app
    }

    /// Replaces `target` with `app`. The new copy is prepared next to it first, so the swap itself is one step.
    static func install(app: URL, replacing target: URL) throws {
        let staging = target.deletingLastPathComponent().appendingPathComponent(".\(target.deletingPathExtension().lastPathComponent)-update.app")
        try? FileManager.default.removeItem(at: staging)
        guard run("/usr/bin/ditto", [app.path, staging.path]).status == 0 else { throw UpdateError.unzip }
        _ = try FileManager.default.replaceItemAt(target, withItemAt: staging)
    }

    /// Opens the (new) app again a moment after this one has quit.
    static func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

/// Checks once a day and installs updates by itself, but never while you are presenting.
final class UpdateManager {
    var onNote: (Note, (() -> Void)?) -> Void = { _, _ in }
    var isPresenting: () -> Bool = { false }

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var working = false
    private var waiting: Release?   // found while presenting: installed as soon as possible

    var automatic: Bool {
        get { defaults.bool(forKey: "autoUpdate") }
        set { defaults.set(newValue, forKey: "autoUpdate") }
    }

    func start() {
        defaults.register(defaults: ["autoUpdate": true])
        announceIfJustUpdated()
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        if let release = waiting, !isPresenting() {
            waiting = nil
            install(release, manual: false)
            return
        }
        guard automatic else { return }
        let last = defaults.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        if Date().timeIntervalSince(last) > 23 * 3600 { check(manual: false) }
    }

    /// "Check for Updates…" (manual) or the daily check.
    func check(manual: Bool) {
        guard !working else { return }
        working = true
        Updater.fetchLatest { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.defaults.set(Date(), forKey: "lastUpdateCheck")
                switch result {
                case .failure:
                    self.working = false
                    if manual {
                        self.onNote(Note(title: L("Could not check for updates"), lines: [L("Check your internet connection and try again.")]), nil)
                    }
                case .success(let release):
                    guard Updater.isNewer(release.version, than: Build.version) else {
                        self.working = false
                        if manual {
                            self.onNote(Note(title: L("Present Perfect is up to date"), lines: [L("Version %@ is the newest version.", Build.version)]), nil)
                        }
                        return
                    }
                    if !manual && self.isPresenting() {
                        self.waiting = release
                        self.working = false
                        return
                    }
                    self.working = false
                    self.install(release, manual: manual)
                }
            }
        }
    }

    private func install(_ release: Release, manual: Bool) {
        guard let target = Updater.installTarget, let team = Updater.ownTeamID() else {
            offerDownload(release)
            return
        }
        guard !working else { return }
        working = true
        if manual {
            onNote(Note(title: L("Updating to version %@…", release.version), lines: []), nil)
        }
        Updater.download(release.zipURL) { [weak self] result in
            var outcome: Result<URL, Error> = .failure(UpdateError.badResponse)
            switch result {
            case .failure(let error):
                outcome = .failure(error)
            case .success(let zip):
                do {
                    let app = try Updater.unpackAndVerify(zip: zip, teamID: team)
                    let newVersion = Updater.version(of: app)
                    guard Updater.isNewer(newVersion, than: Build.version) else { throw UpdateError.notNewer(newVersion) }
                    try Updater.install(app: app, replacing: target)
                    outcome = .success(target)
                } catch {
                    outcome = .failure(error)
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.working = false
                switch outcome {
                case .success(let app):
                    self.defaults.set(Build.version, forKey: "updatedFrom")
                    self.defaults.set(release.pageURL.absoluteString, forKey: "updatedNotesURL")
                    Updater.relaunch(app)
                case .failure(let error):
                    NSLog("Present Perfect: update failed: \(error)")
                    self.onNote(Note(title: L("The update could not be installed"),
                                     lines: [L("Download it from the website instead.")],
                                     actionTitle: L("Download")),
                                { _ = NSWorkspace.shared.open(release.pageURL) })
                }
            }
        }
    }

    private func offerDownload(_ release: Release) {
        onNote(Note(title: L("Version %@ is available", release.version), lines: [L("Download it from the website instead.")],
                    actionTitle: L("Download")),
               { _ = NSWorkspace.shared.open(release.pageURL) })
    }

    /// After an update the new version says so once.
    private func announceIfJustUpdated() {
        guard let from = defaults.string(forKey: "updatedFrom") else { return }
        defaults.removeObject(forKey: "updatedFrom")
        let notes = defaults.string(forKey: "updatedNotesURL").flatMap { URL(string: $0) }
        defaults.removeObject(forKey: "updatedNotesURL")
        guard from != Build.version else { return }
        var action: (() -> Void)?
        if let notes { action = { _ = NSWorkspace.shared.open(notes) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.onNote(Note(title: L("Updated to version %@", Build.version), lines: [],
                              actionTitle: action == nil ? nil : L("What's New")), action)
        }
    }
}
