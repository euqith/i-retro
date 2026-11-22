//
//  PhotoPermissionsHelper.swift
//  iRetro
//
//  Deployment Target: iOS 12.0+ (Photo-Only: Camera Video Preview & Photo Library)
//

import Foundation
import UIKit
import AVFoundation
import Photos

/// Normalized authorization state for photo-only hardware & library permissions.
public enum PhotoPermissionState: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

/// Photo-only permission inspector, requester, and retro-styled Settings alert factory.
/// Strictly excludes microphone or movie recording APIs.
public enum PhotoPermissionsHelper {

    public static let retroAlertTintColor = UIColor(red: 0.96, green: 0.78, blue: 0.26, alpha: 1.0)

    // MARK: - Status Mapping & Queries

    public static func mapCameraAuthorizationStatus(_ status: AVAuthorizationStatus) -> PhotoPermissionState {
        switch status {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    public static func cameraAuthorizationStatus() -> PhotoPermissionState {
        return mapCameraAuthorizationStatus(AVCaptureDevice.authorizationStatus(for: .video))
    }

    public static func mapPhotoLibraryAuthorizationStatus(_ status: PHAuthorizationStatus) -> PhotoPermissionState {
        switch status {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .limited:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    public static func photoLibraryAuthorizationStatus() -> PhotoPermissionState {
        if #available(iOS 14, *) {
            return mapPhotoLibraryAuthorizationStatus(PHPhotoLibrary.authorizationStatus(for: .addOnly))
        } else {
            return mapPhotoLibraryAuthorizationStatus(PHPhotoLibrary.authorizationStatus())
        }
    }

    // MARK: - Main-Thread Access Requests

    public static func requestCameraAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    public static func requestPhotoLibraryAccess(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                let granted = (mapPhotoLibraryAuthorizationStatus(status) == .authorized)
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                let granted = (mapPhotoLibraryAuthorizationStatus(status) == .authorized)
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        }
    }

    // MARK: - Retro Settings Alert

    public static func makeRetroSettingsAlert(
        title: String = "[ ACCESS REQUIRED ]",
        message: String,
        openSettingsTitle: String = "OPEN SETTINGS",
        dismissTitle: String = "DISMISS",
        settingsOpener: @escaping (URL) -> Void = { url in
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        },
        cancelHandler: (() -> Void)? = nil
    ) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.view.tintColor = retroAlertTintColor

        let dismissAction = UIAlertAction(title: dismissTitle, style: .cancel) { _ in
            cancelHandler?()
        }
        let openSettingsAction = UIAlertAction(title: openSettingsTitle, style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                settingsOpener(settingsURL)
            }
        }

        alert.addAction(dismissAction)
        alert.addAction(openSettingsAction)
        return alert
    }
}
