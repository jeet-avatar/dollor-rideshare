//
//  AppStoreScreenshots.swift
//  eatffairdeliveryUITests
//
//  Captures App Store screenshots for the Driver app.
//

import XCTest

final class DriverAppStoreScreenshotTests: XCTestCase {

    var app: XCUIApplication!
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = true
        let token = fetchDriverToken()
        app = XCUIApplication()
        if let token = token {
            app.launchEnvironment["UITEST_DRIVER_TOKEN"] = token
        }
        app.launch()
        dismissSystemAlerts()
        sleep(3)
    }

    private func fetchDriverToken() -> String? {
        let url = URL(string: "https://api.dollor.ai/api/auth/driver/login")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("DollorDriver/1.0 (iPhone; iOS 17.0)", forHTTPHeaderField: "User-Agent")
        req.httpBody = "username=demo.driver%40dollor.ai&password=DemoDriver2025%21".data(using: .utf8)
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
        // Wait for dashboard to appear
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "Must be logged in with tab bar visible")
        sleep(2)

        // 01 — Rideshare dashboard (Available tab)
        goToTab(0)
        snap("01_rideshare_available")

        // 02 — My Bids tab (inner segment)
        let myBidsBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'bids' OR label CONTAINS[c] 'bid'")).firstMatch
        if myBidsBtn.waitForExistence(timeout: 3) {
            myBidsBtn.tap(); sleep(2)
            snap("02_my_bids")
        }

        // 03 — Active tab (inner segment)
        let activeBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'active'")).firstMatch
        if activeBtn.waitForExistence(timeout: 3) {
            activeBtn.tap(); sleep(2)
            snap("03_active_rides")
        }

        // 04 — Messages tab
        goToTab(1)
        snap("04_messages")

        // 05 — Profile tab (Personal/Overview)
        let lastIdx = tabBar.buttons.count - 1
        tabBar.buttons.element(boundBy: lastIdx).tap()
        sleep(2)
        snap("05_profile_overview")

        // 06 — Documents sub-tab
        let docsBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'document' OR label CONTAINS[c] 'docs'")).firstMatch
        if docsBtn.waitForExistence(timeout: 3) {
            docsBtn.tap(); sleep(2)
            snap("06_profile_documents")
        }

        // 07 — Earnings sub-tab
        let earningsBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'earning' OR label CONTAINS[c] 'payout'")).firstMatch
        if earningsBtn.waitForExistence(timeout: 3) {
            earningsBtn.tap(); sleep(2)
            snap("07_profile_earnings")
        }

        // 08 — Settings sub-tab
        let settingsBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'setting'")).firstMatch
        if settingsBtn.waitForExistence(timeout: 3) {
            settingsBtn.tap(); sleep(2)
            snap("08_profile_settings")
        }

        // 10 — Back to rideshare with Available segment (clean hero shot)
        goToTab(0)
        let availBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'available'")).firstMatch
        if availBtn.waitForExistence(timeout: 3) { availBtn.tap(); sleep(1) }
        snap("10_rideshare_go_online")
    }
}
