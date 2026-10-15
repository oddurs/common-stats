import AppKit

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) {
    let seconds = arguments.indices.contains(flag + 2) ? Int(arguments[flag + 2]) ?? 3 : 3
    SnapshotCommand.run(path: arguments[flag + 1], seconds: seconds)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
