import SwiftUI

@main
struct PersonalFinanceApp: App {
    private let dependencies = AppDependencies.live

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: AppViewModel(dependencies: dependencies))
        }
    }
}
