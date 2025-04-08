//
//  C_ALL_Avoidance_Path_BluetoothUITestsLaunchTests.swift
//  C_ALL_Avoidance_Path_BluetoothUITests
//
//  Created by SSW - Design Team  on 2/13/25.
//

import XCTest

final class C_ALL_Avoidance_Path_BluetoothUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
