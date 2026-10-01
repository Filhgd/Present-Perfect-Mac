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
