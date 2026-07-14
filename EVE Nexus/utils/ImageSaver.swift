import Photos
import SwiftUI
import UIKit

/// 简化的图片保存工具
class ImageSaver {
    /// 简单的保存图片方法
    static func saveImage(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
            if let error = error {
                Logger.error("保存图片失败: \(error.localizedDescription)")
            } else {
                Logger.info("图片保存成功")
            }

            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}
