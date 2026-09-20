import Foundation
import Observation

/// Where a screen can go.
enum Route: Hashable {
    case importVideo(VideoAsset)
    case processing(asset: VideoAsset, language: AppLanguage)
}

/// The navigation stack's path, shared so any screen can push - and so a finished
/// job can drop the user straight back home instead of reversing through the flow.
@MainActor
@Observable
final class AppRouter {
    var path: [Route] = []

    func push(_ route: Route) {
        path.append(route)
    }

    func popToRoot() {
        path.removeAll()
    }
}
