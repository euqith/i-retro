# i-Retro — Retro Camera & Film Simulation (iOS 12.0+)

Aplikasi kamera **khusus foto (Photo-Only, Tanpa Video)** bertema *Retro Digicam & Film Simulation* dengan *real-time 3D LUT preview* (WYSIWYG), dioptimalkan untuk berjalan mulus pada **30fps** di perangkat **iOS 12.0+ (termasuk iPhone 5S dengan chip Apple A7 & 1 GB RAM)** menggunakan **Swift 5 & Programmatic UIKit**.

## Spesifikasi & Batasan Teknis
- **Fokus Fitur**: 100% Fotografi (Tanpa perekaman video / tanpa input mikrofon).
- **Deployment Target**: iOS 12.0+ (Kompatibel penuh dengan iPhone 5S).
- **Framework**: Swift 5, UIKit, AVFoundation, CoreImage, Metal (`MTKView`), Photos (`PHPhotoLibrary`). **Tanpa SwiftUI**.
- **Performa**: Live preview 30fps terakselerasi GPU Metal dengan satu `CIContext(mtlDevice:)` (`cacheIntermediates: false`), in-flight frame semaphore, dan `autoreleasepool` ketat di setiap frame untuk mencegah memory leak dan overheating.

## Komponen Modular
1. **[PLANNING.md](PLANNING.md)** — Dokumen analisis arsitektur, strategi optimasi chip A7 / 1 GB RAM, serta breakdown 5 Epic dan 13 Issue.
2. **[iRetro/Core/LUT/CubeLUTParser.swift](iRetro/Core/LUT/CubeLUTParser.swift)** — Parser file `.cube` 3D LUT yang mengekstrak matriks RGB ke buffer RGBA Float32 dan membangun filter `CIColorCubeWithColorSpace`.
3. **[iRetro/Core/Presets/PresetManager.swift](iRetro/Core/Presets/PresetManager.swift)** — Pengelola 5 preset simulasi film bawaan (*Japanese Airy*, *Fuji Classic Chrome*, *Fuji Pro Neg*, *Kodak Portra 400*, *Kodak Gold 200*) serta penyimpanan file `.cube` kustom di `Documents/CustomLUTs/`.
4. **[iRetro/Camera/CameraViewController.swift](iRetro/Camera/CameraViewController.swift)** — Engine kamera `AVCaptureSession` (rear camera, `.photo` preset), `AVCaptureVideoDataOutput` 30fps, renderer `MTKView` (`MetalPreviewView`), UI Retro Digicam (`UICollectionView` + Circular Shutter Button), `UIDocumentPickerViewController` import `.cube`, dan `AVCapturePhotoOutput` -> `PHPhotoLibrary`.
5. **[iRetro/App/AppDelegate.swift](iRetro/App/AppDelegate.swift)** & **[iRetro/App/Info.plist](iRetro/App/Info.plist)** — Bootstrap programmatic `UIWindow` iOS 12.0+ dan konfigurasi izin kamera & galeri foto.
