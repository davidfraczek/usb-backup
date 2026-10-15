import SwiftUI

@main
struct USBPhotoBackupApp: App {
    init() {
        Notifier.configure()      // lets notifications show up while the app is open
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
