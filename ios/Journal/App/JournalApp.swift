import SwiftUI
import UIKit

@main
struct JournalApp: App {
    init() {
        // Globally prevent any horizontal rubber-banding or panning across all scroll views
        UIScrollView.appearance().alwaysBounceHorizontal = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
