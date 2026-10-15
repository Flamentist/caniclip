import AppKit

enum ActivationPolicyRule {
    /// With "Show in Dock" on, CaniClip is always a regular Dock app. With it off,
    /// it is menu-bar-only and gains a Dock icon only while the hub is open.
    static func policy(openHubWindows: Int, showInDock: Bool = false) -> NSApplication.ActivationPolicy {
        showInDock || openHubWindows > 0 ? .regular : .accessory
    }
}
