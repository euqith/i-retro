//
//  AppDelegate.swift
//  iRetro
//
//  Deployment Target: iOS 12.0+ (Supports iPhone 5S / Apple A7 / 1GB RAM)
//  Frameworks: UIKit ONLY (Strictly NO SwiftUI, NO SceneDelegate)
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    static let chassisBackgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let mainWindow = UIWindow(frame: UIScreen.main.bounds)
        mainWindow.backgroundColor = AppDelegate.chassisBackgroundColor
        mainWindow.rootViewController = CameraViewController()
        mainWindow.makeKeyAndVisible()
        self.window = mainWindow
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .portrait
    }
}
