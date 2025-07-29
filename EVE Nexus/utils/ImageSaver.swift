import UIKit
import Photos
import SwiftUI

// 图片保存结果枚举
enum ImageSaveResult {
    case success
    case failure(Error)
    case permissionDenied
}

// 图片保存器类
class ImageSaver: NSObject {
    private var completion: ((ImageSaveResult) -> Void)?
    
    // 保存图片到相册
    func saveImage(_ image: UIImage, completion: @escaping (ImageSaveResult) -> Void) {
        self.completion = completion
        
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    UIImageWriteToSavedPhotosAlbum(image, self, #selector(self?.image(_:didFinishSavingWithError:contextInfo:)), nil)
                case .denied, .restricted:
                    self?.completion?(.permissionDenied)
                case .notDetermined:
                    // 这种情况理论上不会发生，因为我们已经请求了权限
                    self?.completion?(.permissionDenied)
                @unknown default:
                    self?.completion?(.permissionDenied)
                }
            }
        }
    }
    
    // 保存图片的回调方法
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                Logger.error("保存图片失败: \(error.localizedDescription)")
                self?.completion?(.failure(error))
            } else {
                Logger.info("图片保存成功")
                self?.completion?(.success)
            }
        }
    }
}

// SwiftUI 视图修饰符
struct SaveImageModifier: ViewModifier {
    let image: UIImage
    @Binding var isSaving: Bool
    @Binding var showSuccess: Bool
    @Binding var showError: Bool
    
    private let imageSaver = ImageSaver()
    
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                saveImage()
            }
    }
    
    private func saveImage() {
        isSaving = true
        
        imageSaver.saveImage(image) { result in
            isSaving = false
            
            switch result {
            case .success:
                showSuccess = true
            case .failure:
                showError = true
            case .permissionDenied:
                showError = true
            }
        }
    }
}

// SwiftUI 扩展
extension View {
    func saveImage(
        _ image: UIImage,
        isSaving: Binding<Bool>,
        showSuccess: Binding<Bool>,
        showError: Binding<Bool>
    ) -> some View {
        self.modifier(SaveImageModifier(
            image: image,
            isSaving: isSaving,
            showSuccess: showSuccess,
            showError: showError
        ))
    }
} 