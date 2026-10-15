import AppKit

enum ActivationPolicyRule {
    /// Dock icon and menu bar only while the hub is open; menu-bar-only otherwise.
    static func policy(openHubWindows: Int) -> NSApplication.ActivationPolicy {
        openHubWindows > 0 ? .regular : .accessory
    }
}
