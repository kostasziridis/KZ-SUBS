import Foundation
import Observation

/// Where a screen can go.
enum Route: Hashable {
    case importVideo(VideoAsset)
    case modelSetup(asset: VideoAsset, language: AppLanguage)
    case processing(asset: VideoAsset, language: AppLanguage)
    case stylePicker(SubtitleProject)
    case editor(SubtitleProject)
    case export(SubtitleProject)
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

    /// Replaces the stack with a single screen, so finishing a job does not leave the
    /// steps that produced it sitting behind the Back button.
    func replaceStack(with route: Route) {
        path = [route]
    }
}
