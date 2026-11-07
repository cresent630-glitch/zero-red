import SwiftUI

@main
@MainActor
struct ZeroRedApp: App {
    @UIApplicationDelegateAdaptor(BackgroundAppDelegate.self) private var appDelegate
    @StateObject private var library = LibraryStore()
    @StateObject private var reading = ReadingLibrary()
    var body: some Scene {
        WindowGroup {
            BrowserView().environmentObject(library).environmentObject(reading).tint(.primary).environment(\.locale, library.locale)
        }
    }
}
