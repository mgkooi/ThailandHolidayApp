//
//  ThailandHolidayAppUITests.swift
//  ThailandHolidayAppUITests
//
//  Created by Martijn Kooi on 12/08/2026.
//

import XCTest

final class ThailandHolidayAppUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testAccommodationCreatedInReisAppearsImmediatelyInVandaag() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Reis"].tap()
        app.buttons["Nieuw reisitem"].tap()
        app.staticTexts["Accommodatie"].tap()
        let name = app.textFields["Naam"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Test Hotel Bangkok")
        let address = app.textFields["Adres"]
        address.tap(); address.typeText("Bangkok, Thailand")
        app.buttons["Bewaar"].tap()
        XCTAssertTrue(app.otherElements["saveConfirmation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Test Hotel Bangkok"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Vandaag"].tap()
        XCTAssertTrue(app.staticTexts["Test Hotel Bangkok"].waitForExistence(timeout: 5))
        app.buttons["Volgende reisdag"].tap()
        XCTAssertTrue(app.staticTexts["Test Hotel Bangkok"].waitForExistence(timeout: 5))
        app.buttons["Volgende reisdag"].tap()
        XCTAssertFalse(app.staticTexts["Test Hotel Bangkok"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testActivityCreatedInReisAppearsImmediatelyInVandaag() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Reis"].tap()
        app.buttons["Nieuw reisitem"].tap()
        app.staticTexts["Activiteit"].tap()
        let title = app.textFields["Titel"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Test activiteit")
        app.buttons["Bewaar"].tap()
        XCTAssertTrue(app.staticTexts["Test activiteit"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Vandaag"].tap()
        XCTAssertTrue(app.staticTexts["Test activiteit"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTodayCalendarUsesFullSheetAndSemanticDateFields() throws {
        let app = launchIsolatedApp()
        let chooseDate = app.buttons["Kies datum"]
        XCTAssertTrue(chooseDate.waitForExistence(timeout: 5))
        chooseDate.tap()
        XCTAssertTrue(app.navigationBars["Kies datum"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        app.buttons["Sluit"].tap()

        app.tabBars.buttons["Reis"].tap()
        app.buttons["Nieuw reisitem"].tap()
        app.staticTexts["Vlucht"].tap()
        XCTAssertTrue(app.staticTexts["Vertrekdatum"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Datum"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.staticTexts["Accommodatie"].tap()
        XCTAssertTrue(app.staticTexts["Check-in"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Check-out"].exists)
        XCTAssertFalse(app.staticTexts["Datum"].exists)
    }

    @MainActor
    func testBookedLunchAndDinnerAppearImmediatelyInToday() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Reis"].tap()
        app.buttons["Nieuw reisitem"].tap()
        for name in ["Restaurant Lunch", "Restaurant Dinner"] {
            app.staticTexts["Restaurant"].tap()
            let field = app.textFields["Naam"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText("\(name)\n")
            XCTAssertTrue(app.staticTexts["Datum"].exists)
            app.swipeUp()
            app.swipeUp()
            XCTAssertTrue(app.buttons["Bewaar"].waitForExistence(timeout: 5))
            app.buttons["Bewaar"].tap()
            XCTAssertTrue(app.navigationBars["Nieuw reisitem"].waitForExistence(timeout: 5))
        }
        app.tabBars.buttons["Vandaag"].tap()
        XCTAssertTrue(app.staticTexts["Restaurant Lunch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Restaurant Dinner"].exists)
    }

    @MainActor
    func testTodayNearbyOpensDiscoverAndManualPlaceChangesContext() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Reis"].tap()
        app.buttons["Nieuw reisitem"].tap()
        app.staticTexts["Accommodatie"].tap()
        let name = app.textFields["Naam"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Testverblijf Chiang Mai")
        let place = app.textFields["Plaats"]
        place.tap(); place.typeText("Chiang Mai")
        app.buttons["Bewaar"].tap()

        app.tabBars.buttons["Vandaag"].tap()
        XCTAssertTrue(app.staticTexts["In de buurt van Chiang Mai"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Bekijk alles"].waitForExistence(timeout: 5))
        app.buttons["Bekijk alles"].tap()
        XCTAssertTrue(app.navigationBars["Ontdekken"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Restaurants"].isSelected)
        XCTAssertTrue(app.staticTexts["Ontdekken rond Chiang Mai"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Ontdek"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Navigeer"].firstMatch.exists)

        let search = app.textFields["discoveryLocationField"]
        search.tap(); search.typeText("Koh Tao\n")
        XCTAssertTrue(app.staticTexts["Ontdekken rond Koh Tao"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTodayActiveAccommodationLocationOpensMapWithTripPin() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Reis"].tap()
        app.buttons["Nieuw reisitem"].tap()
        app.staticTexts["Accommodatie"].tap()
        let name = app.textFields["Naam"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Kaart Testhotel")
        let place = app.textFields["Plaats"]
        place.tap(); place.typeText("Chiang Mai")
        app.buttons["Bewaar"].tap()

        app.tabBars.buttons["Vandaag"].tap()
        let location = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Open Chiang Mai, Thailand op kaart'")).firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 10))
        location.tap()
        XCTAssertTrue(app.navigationBars["Kaart"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Kaart Testhotel"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testViewpointFiltersAndAddToTripPrefill() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Ontdekken"].tap()
        let search = app.textFields["discoveryLocationField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Koh Tao\n")
        let viewpoints = app.buttons["Viewpoints"]
        XCTAssertTrue(viewpoints.waitForExistence(timeout: 5))
        viewpoints.tap()
        XCTAssertTrue(viewpoints.isSelected)
        XCTAssertTrue(app.staticTexts["Viewpoints test 1"].waitForExistence(timeout: 5))

        app.buttons["Filters"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        app.buttons["Toepassen"].tap()
        let add = app.buttons["Toevoegen aan reis"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.navigationBars["Nieuw activiteit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Viewpoint"].exists)
        XCTAssertEqual(app.textFields["Titel"].value as? String, "Viewpoints test 1")
    }

    @MainActor
    func testTripContextDoesNotBlockScanOrAddToolbarButtons() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Reis"].tap()
        XCTAssertTrue(app.buttons["Actieve reis: Thailand 2026"].waitForExistence(timeout: 5))
        let scan = app.buttons["Scan boeking"]
        XCTAssertTrue(scan.isHittable)
        scan.tap()
        XCTAssertTrue(app.navigationBars["Scan boeking"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let add = app.buttons["Nieuw reisitem"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(app.navigationBars["Nieuw reisitem"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMapSearchShowsPlaceActionsAndPrefilledEditor() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Kaart"].tap()
        let search = app.textFields["mapSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Khao Sok hotel\n")
        XCTAssertTrue(app.staticTexts["Test Hotel Khao Sok"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Ontdek"].exists)
        XCTAssertTrue(app.buttons["Navigeer"].exists)
        app.buttons["Toevoegen"].tap()
        app.buttons["Accommodatie"].tap()
        let name = app.textFields["Naam"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Test Hotel Khao Sok")
        XCTAssertEqual(app.textFields["Plaats"].value as? String, "Khao Sok")
    }

    @MainActor
    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Reis"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
