import SwiftUI

@main
struct FastObsidianMobileApp: App {
    @StateObject private var vault = VaultStore()
    @StateObject private var theme = ThemeSettings()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(vault)
                .environmentObject(theme)
                .preferredColorScheme(theme.appearance.colorScheme)
        }
    }
}
