Buatkan planning dan untuk project berikut:
Fokus aplikasi ini hanya untuk foto tanpa video.

Push epik dan issue nya pada github : https://github.com/euqith/i-retro.git

Act as an expert iOS developer specializing in AVFoundation, CoreImage, and hardware optimization. I need you to generate the complete code for a Retro Camera & Film Simulation app. 

CRITICAL CONSTRAINTS:
- Deployment Target: iOS 12.0+ (Must support iPhone 5S).
- Frameworks: Swift 5 and UIKit ONLY (Strictly NO SwiftUI).
- Performance: Must run smoothly at 30fps on older A7 chips with 1GB RAM without overheating or memory leaks.

Please generate the modular Swift code covering the following 4 core components:

1. CAMERA ENGINE & METAL RENDERING (`CameraViewController.swift`)
- Initialize an `AVCaptureSession` using the rear camera.
- Configure `AVCaptureVideoDataOutput` to extract real-time frames (CMSampleBuffer).
- Render the frames to the screen using `MTKView` (Metal) or `GLKView` to ensure GPU-accelerated smooth 30fps live preview.
- Ensure aggressive memory management (deallocate CIImage/textures every frame) to prevent RAM leaks.

2. 3D LUT PROCESSING PIPELINE (`CubeLUTParser.swift`)
- Write a robust parser that reads standard `.cube` text files, skips comments, and extracts the 3D RGB matrix into an array of floats.
- Create a function to convert that float array into a `CIColorCube` filter.
- Inject this `CIColorCube` into the `AVCaptureVideoDataOutput` pipeline so the live preview is filtered in real-time (WYSIWYG).

3. RETRO UI & PRESET MANAGEMENT (`PresetManager.swift` & UI Setup)
- Build a minimalist, retro digicam UI: a viewfinder maintaining the correct aspect ratio, a prominent circular Shutter Button, and a horizontal `UICollectionView` at the bottom for selecting filters.
- Create a `PresetManager` that loads embedded `.cube` presets. Include placeholder setups for: "Japanese Airy", "Fuji Classic Chrome", "Fuji Pro Neg", "Kodak Portra 400", and "Kodak Gold 200".
- Bind the `UICollectionView` so tapping a preset instantly swaps the active `CIColorCube` filter in the camera pipeline.

4. CUSTOM IMPORT & HIGH-RES CAPTURE 
- Custom LUT Import: Add an "Import .cube" button that triggers `UIDocumentPickerViewController`. Allow users to select `.cube` files from the Files app/iCloud, save them locally to the app's Document Directory, and dynamically add them to the preset carousel.
- High-Res Capture: Implement `AVCapturePhotoOutput`. When the shutter is pressed, capture a full-resolution photo, apply the CURRENTLY ACTIVE `CIColorCube` filter to it, and save the final WYSIWYG image to the iOS Camera Roll using `PHPhotoLibrary`.

Please provide the complete, structured code for these classes and extensions, separated clearly by file names.