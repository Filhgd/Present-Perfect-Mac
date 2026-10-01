import AppKit

let appName = "Present Perfect"
let supportURL = URL(string: "https://buymeacoffee.com/filiphaegdorens")!

// MARK: - Command line (used by the build checks)

let args = CommandLine.arguments
if args.count >= 2, args[1] == "--version" {
    print(Build.versionString)
    exit(0)
}
if args.count >= 2, args[1] == "--diagnostics" {
    _ = NSApplication.shared
    print(Diagnostics.report())
    exit(0)
}
if args.count >= 2, args[1] == "--check-update" {
    let done = DispatchSemaphore(value: 0)
    var code: Int32 = 0
    Updater.fetchLatest { result in
        switch result {
        case .success(let r):
            let newer = Updater.isNewer(r.version, than: Build.version)
            print("current \(Build.version), latest \(r.version): " + (newer ? "update available" : "up to date"))
            print("download: \(r.zipURL.absoluteString)")
        case .failure(let e):
            print("error: \(e)")
            code = 2
        }
        done.signal()
    }
    done.wait()
    exit(code)
}
if args.count >= 3, args[1] == "--verify-app" {
    // Would this app be accepted as an update? (used by the build checks)
    guard let team = Updater.ownTeamID() else { print("this build is not signed with a Developer ID"); exit(2) }
    do {
        try Updater.verify(app: URL(fileURLWithPath: args[2]), teamID: team)
        print("accepted: signed by team \(team) and notarized")
        exit(0)
    } catch {
        print("refused: \(error)")
        exit(1)
    }
}
if args.count >= 4, args[1] == "--test-install" {
    // --test-install ZIP TARGET.app: unpack, check and install over TARGET (used by the build checks)
    guard let team = Updater.ownTeamID() else { print("this build is not signed with a Developer ID"); exit(2) }
    do {
        let app = try Updater.unpackAndVerify(zip: URL(fileURLWithPath: args[2]), teamID: team)
        let target = URL(fileURLWithPath: args[3])
        try Updater.install(app: app, replacing: target)
        print("installed version \(Updater.version(of: target)) at \(target.path)")
        exit(0)
    } catch {
        print("failed: \(error)")
        exit(1)
    }
}
if args.count >= 3, args[1] == "--render-ui" {
    renderSnapshots(to: URL(fileURLWithPath: args[2]))
    exit(0)
}

// MARK: - App

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
