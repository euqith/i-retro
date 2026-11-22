//
//  FoundationTests.swift
//  iRetroTests
//
//  Unit tests for Epic 1 foundation: AppDelegate, Info.plist, LaunchImages,
//  PhotoPermissionsHelper, and CameraViewController portrait/status-bar setup.
//

import XCTest
import UIKit
import AVFoundation
import Photos
@testable import iRetro

final class FoundationTests: XCTestCase {

    func testAppDelegateEnforcesPortraitOrientationAndDarkWindow() {
        let appDelegate = AppDelegate()
        XCTAssertEqual(
            appDelegate.application(UIApplication.shared, supportedInterfaceOrientationsFor: nil),
            .portrait
        )

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(
            AppDelegate.chassisBackgroundColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        )
        XCTAssertEqual(red, 0.07, accuracy: 0.001)
        XCTAssertEqual(green, 0.07, accuracy: 0.001)
        XCTAssertEqual(blue, 0.08, accuracy: 0.001)
        XCTAssertEqual(alpha, 1.0, accuracy: 0.001)

        if let hostedDelegate = UIApplication.shared.delegate as? AppDelegate,
           let hostedWindow = hostedDelegate.window {
            XCTAssertEqual(hostedWindow.backgroundColor, AppDelegate.chassisBackgroundColor)
            XCTAssertTrue(hostedWindow.rootViewController is CameraViewController)
        }
    }

    func testInfoPlistPhotoOnlyAndIOS12Constraints() {
        guard let info = Bundle(for: AppDelegate.self).infoDictionary else {
            XCTFail("Expected Info.plist dictionary for app bundle")
            return
        }

        XCTAssertEqual(info["MinimumOSVersion"] as? String, "12.0")
        XCTAssertEqual(info["UIStatusBarHidden"] as? Bool, true)
        XCTAssertEqual(info["UIViewControllerBasedStatusBarAppearance"] as? Bool, true)
        XCTAssertEqual(
            info["UISupportedInterfaceOrientations"] as? [String],
            ["UIInterfaceOrientationPortrait"]
        )

        let cameraUsage = info["NSCameraUsageDescription"] as? String ?? ""
        let photoAddUsage = info["NSPhotoLibraryAddUsageDescription"] as? String ?? ""
        let photoReadUsage = info["NSPhotoLibraryUsageDescription"] as? String ?? ""
        XCTAssertFalse(cameraUsage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(photoAddUsage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(photoReadUsage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let capabilities = info["UIRequiredDeviceCapabilities"] as? [String] ?? []
        XCTAssertTrue(capabilities.contains("arm64"))
        XCTAssertTrue(capabilities.contains("metal"))
        XCTAssertTrue(capabilities.contains("still-camera"))

        let launchImages = info["UILaunchImages"] as? [[String: Any]] ?? []
        let hasFourInchRetinaLaunch = launchImages.contains { entry in
            (entry["UILaunchImageSize"] as? String) == "{320, 568}" &&
            (entry["UILaunchImageOrientation"] as? String) == "Portrait"
        }
        XCTAssertTrue(hasFourInchRetinaLaunch, "Native 4-inch iPhone 5S launch image {320, 568} must be present")

        // Prohibited keys (Photo-only, programmatic UIKit, iOS 12)
        XCTAssertNil(info["NSMicrophoneUsageDescription"])
        XCTAssertNil(info["UILaunchStoryboardName"])
        XCTAssertNil(info["UIMainStoryboardFile"])
        XCTAssertNil(info["UIApplicationSceneManifest"])
    }

    func testPhotoPermissionsHelperMappingAndRetroAlert() {
        XCTAssertEqual(PhotoPermissionsHelper.mapCameraAuthorizationStatus(.authorized), .authorized)
        XCTAssertEqual(PhotoPermissionsHelper.mapCameraAuthorizationStatus(.notDetermined), .notDetermined)
        XCTAssertEqual(PhotoPermissionsHelper.mapCameraAuthorizationStatus(.denied), .denied)
        XCTAssertEqual(PhotoPermissionsHelper.mapCameraAuthorizationStatus(.restricted), .restricted)

        XCTAssertEqual(PhotoPermissionsHelper.mapPhotoLibraryAuthorizationStatus(.authorized), .authorized)
        XCTAssertEqual(PhotoPermissionsHelper.mapPhotoLibraryAuthorizationStatus(.notDetermined), .notDetermined)
        XCTAssertEqual(PhotoPermissionsHelper.mapPhotoLibraryAuthorizationStatus(.denied), .denied)
        XCTAssertEqual(PhotoPermissionsHelper.mapPhotoLibraryAuthorizationStatus(.restricted), .restricted)
        if #available(iOS 14, *) {
            XCTAssertEqual(PhotoPermissionsHelper.mapPhotoLibraryAuthorizationStatus(.limited), .authorized)
        }

        let alert = PhotoPermissionsHelper.makeRetroSettingsAlert(
            message: "Please enable camera access in Settings."
        )
        XCTAssertEqual(alert.preferredStyle, .alert)
        XCTAssertEqual(alert.title, "[ ACCESS REQUIRED ]")
        XCTAssertEqual(alert.message, "Please enable camera access in Settings.")
        XCTAssertEqual(alert.actions.count, 2)
        XCTAssertEqual(alert.actions.map { $0.title }, ["DISMISS", "OPEN SETTINGS"])
        XCTAssertEqual(alert.actions[0].style, .cancel)
        XCTAssertEqual(alert.actions[1].style, .default)
        XCTAssertEqual(alert.view.tintColor, PhotoPermissionsHelper.retroAlertTintColor)
        XCTAssertNotNil(URL(string: UIApplication.openSettingsURLString))
    }

    func testCameraViewControllerPortraitAndHiddenStatusBar() {
        let cameraVC = CameraViewController()
        XCTAssertTrue(cameraVC.prefersStatusBarHidden)
        XCTAssertEqual(cameraVC.preferredStatusBarStyle, .lightContent)
        XCTAssertEqual(cameraVC.supportedInterfaceOrientations, .portrait)
    }
}
