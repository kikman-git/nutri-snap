import Photos
import UIKit

/// Saves an in-app meal snap to the user's Photos library (add-only). Best-effort and silent: a
/// denied permission or a write failure never disrupts logging. Only **camera** captures call this —
/// photos chosen from the library already live in Photos, so re-saving them would just duplicate.
enum PhotoLibrarySaver {
    static func save(_ image: UIImage) async {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
