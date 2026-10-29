//
//  AppStoreScreenshots.swift
//  eatfaircustomerUITests
//
//  Captures App Store screenshots for the Customer (Rideshare) app.
//

import XCTest

final class AppStoreScreenshotTests: XCTestCase {

    var app: XCUIApplication!
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = true
        let token = fetchDemoToken()
        app = XCUIApplication()
        if let token = token {
            app.launchEnvironment["UITEST_ACCESS_TOKEN"] = token
        }
        app.launch()
        dismissSystemAlerts()
        sleep(2)
        // Dismiss any auto-opened location picker
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2) { cancel.tap(); sleep(1) }
    }

    private func fetchDemoToken() -> String? {
        let url = URL(string: "https://api.dollor.ai/api/auth/customer/login")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("DollorCustomer/1.0 (iPhone; iOS 17.0)", forHTTPHeaderField: "User-Agent")
        req.httpBody = "username=demo.customer%40dollor.ai&password=DemoCustomer2025%21".data(using: .utf8)
        req.timeoutInterval = 15
        var result: String?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let t = json["access_token"] as? String { result = t }
            sem.signal()
        }.resume()
        sem.wait()
        return result
    }

    private func dismissSystemAlerts() {
        let sb = springboard.alerts.firstMatch
        if sb.waitForExistence(timeout: 4) {
            let deny = sb.buttons["Don't Allow"]
            (deny.exists ? deny : sb.buttons.firstMatch).tap()
        }
    }

    func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func goToTab(_ idx: Int) {
        let tb = app.tabBars.firstMatch
        guard tb.exists, tb.buttons.count > idx else { return }
        tb.buttons.element(boundBy: idx).tap()
        sleep(2)
        dismissSystemAlerts()
    }

    @MainActor
    func testCaptureAllScreenshots() throws {
        // Wait for logged-in state
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "Must be logged in")
        sleep(2)

        // 01 — Ride home (Find a Driver)
        goToTab(0)
        snap("01_find_a_driver")

        // 02 — Pickup location map picker
        let pickupRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'pickup'")).firstMatch
        if pickupRow.waitForExistence(timeout: 3) {
            pickupRow.tap(); sleep(2)
            snap("02_pickup_map")
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.waitForExistence(timeout: 2) { cancel.tap(); sleep(1) }
        }

        // 03 — Dropoff location picker
        goToTab(0)
        let dropoffRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'dropoff' OR label CONTAINS[c] 'destination' OR label CONTAINS[c] 'drop'")).firstMatch
        if dropoffRow.waitForExistence(timeout: 3) {
            dropoffRow.tap(); sleep(2)
            snap("03_dropoff_map")
            let cancel2 = app.buttons["Cancel"].firstMatch
            if cancel2.waitForExistence(timeout: 2) { cancel2.tap(); sleep(1) }
        }

        // 04 — Trips tab
        goToTab(1)
        snap("04_trips")

        // 05 — Profile tab
        let lastIdx = tabBar.buttons.count - 1
        tabBar.buttons.element(boundBy: lastIdx).tap()
        sleep(2)
        snap("05_profile")

        // 06 — Payment Methods (from profile)
        let paymentBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'payment'")).firstMatch
        if paymentBtn.waitForExistence(timeout: 3) {
            paymentBtn.tap(); sleep(2)
            snap("06_payment_methods")
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }

        // 07 — Manage Addresses
        let addressBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'address'")).firstMatch
        if addressBtn.waitForExistence(timeout: 3) {
            addressBtn.tap(); sleep(2)
            snap("07_manage_addresses")
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }

        // 09 — Settings
        let settingsBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'settings' OR label CONTAINS[c] 'setting'")).firstMatch
        if settingsBtn.waitForExistence(timeout: 3) {
            settingsBtn.tap(); sleep(2)
            snap("09_settings")
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }

        // 10 — Refer & Earn
        let referBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'refer' OR label CONTAINS[c] 'earn'")).firstMatch
        if referBtn.waitForExistence(timeout: 3) {
            referBtn.tap(); sleep(2)
            snap("10_refer_earn")
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }
    }
}
