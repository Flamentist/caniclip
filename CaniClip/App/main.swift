import AppKit

// Top-level code runs on the main thread; tell the compiler so for the
// main-actor-isolated delegate.
let delegate = MainActor.assumeIsolated { AppDelegate() }
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
