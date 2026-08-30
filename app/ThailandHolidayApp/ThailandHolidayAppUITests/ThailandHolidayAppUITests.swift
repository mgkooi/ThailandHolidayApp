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
    func testWeatherUnavailableCardShowsInternalDiagnosis() throws {
        let app = launchIsolatedApp(extraArguments: ["--ui-weather-no-data"])
        let primary = app.descendants(matching: .any)["weatherPrimary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 8), "Weather card primary text ontbreekt")
        XCTAssertEqual(primary.label, "Nog geen weersverwachting beschikbaar")
        XCTAssertEqual(app.descendants(matching: .any)["weatherDiagnosis"].label, "Diagnose: noForecastData")
    }

    @MainActor
    func testWeatherOutOfRangeAndTodaySectionOrder() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-weather-out-of-range"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Nog geen weersverwachting beschikbaar voor deze datum"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.descendants(matching: .any)["weatherDiagnosis"].label, "Diagnose: dateOutOfRange")

        let transport = app.descendants(matching: .any)["todaySection.transport"]
        let accommodation = app.descendants(matching: .any)["todaySection.accommodation"]
        if transport.exists && accommodation.exists {
            XCTAssertLessThan(transport.frame.minY, accommodation.frame.minY)
        }
        app.swipeUp(velocity: .fast)
        app.swipeUp(velocity: .fast)
        XCTAssertTrue(app.descendants(matching: .any)["todayScrollableContent"].exists)
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
        app.swipeUp(velocity: .fast)
        XCTAssertTrue(app.buttons["Bewaar"].waitForExistence(timeout: 5))
        app.buttons["Bewaar"].tap()

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
        app.swipeUp(velocity: .fast)
        XCTAssertTrue(app.buttons["Bewaar"].waitForExistence(timeout: 5))
        app.buttons["Bewaar"].tap()
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
    func testTodayHeroUsesAccessibleIconOnlyActions() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Reis"].tap()
        app.buttons["Nieuw reisitem"].tap()
        app.staticTexts["Accommodatie"].tap()
        let name = app.textFields["Naam"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Icon Action Hotel")
        let place = app.textFields["Plaats"]
        place.tap(); place.typeText("Bangkok")
        app.swipeUp(velocity: .fast)
        XCTAssertTrue(app.buttons["Bewaar"].waitForExistence(timeout: 5))
        app.buttons["Bewaar"].tap()
        app.tabBars.buttons["Vandaag"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["todayHeroCard.accommodation"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Bekijk details"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Wijzig omslag"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Hotel details"].exists)
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
        app.swipeUp(velocity: .fast)
        XCTAssertTrue(app.buttons["Bewaar"].waitForExistence(timeout: 5))
        app.buttons["Bewaar"].tap()

        app.tabBars.buttons["Vandaag"].tap()
        XCTAssertTrue(app.staticTexts["In de buurt van Chiang Mai"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Bekijk alles"].waitForExistence(timeout: 5))
        app.buttons["Bekijk alles"].tap()
        XCTAssertTrue(app.navigationBars["Ontdekken"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Restaurants"].isSelected)
        XCTAssertTrue(app.staticTexts["Rond Chiang Mai"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Restaurants test 1"].waitForExistence(timeout: 5))

        let search = app.textFields["discoveryLocationField"]
        search.tap(); search.typeText("Koh Tao\n")
        XCTAssertTrue(app.staticTexts["Rond Koh Tao"].waitForExistence(timeout: 10))
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
        app.swipeUp(velocity: .fast)
        XCTAssertTrue(app.buttons["Bewaar"].waitForExistence(timeout: 5))
        app.buttons["Bewaar"].tap()

        app.tabBars.buttons["Vandaag"].tap()
        let location = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Open Chiang Mai, Thailand op kaart'")).firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 10))
        location.tap()
        XCTAssertTrue(app.navigationBars["Kaart"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Kaart Testhotel"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testViewpointFiltersAndAddToTripPrefill() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Ontdekken"].tap()
        let search = app.textFields["discoveryLocationField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Koh Tao\n")
        let viewpoints = app.buttons["Viewpoints"]
        XCTAssertTrue(viewpoints.firstMatch.waitForExistence(timeout: 5))
        viewpoints.firstMatch.tap()
        XCTAssertTrue(viewpoints.firstMatch.isSelected)
        XCTAssertTrue(app.staticTexts["Viewpoints test 1"].waitForExistence(timeout: 5))

        app.buttons["Filters"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        app.buttons["Toepassen"].tap()
        app.staticTexts["Viewpoints test 1"].tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Navigeer"].exists)
        XCTAssertTrue(app.buttons["Bewaar"].exists)
        app.buttons["Voeg aan dag toe"].tap()
        XCTAssertTrue(app.navigationBars["Voeg aan dag toe"].waitForExistence(timeout: 5))
        app.buttons["Voeg toe"].tap()
        XCTAssertTrue(app.buttons["Bekijk Vandaag"].waitForExistence(timeout: 5))
        app.buttons["Bekijk Vandaag"].tap()
        XCTAssertTrue(app.staticTexts["Viewpoints test 1"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testDiscoverDetailsSaveAddFiltersAndMapMode() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Ontdekken"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Ontdek '")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Eten"].exists)
        app.buttons["Eten"].tap()
        XCTAssertTrue(app.staticTexts["Restaurants test 1"].waitForExistence(timeout: 8))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Filters'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        app.buttons["Toepassen"].tap()
        app.staticTexts["Restaurants test 1"].tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Navigeer"].exists)
        app.buttons["Bewaar"].tap()
        XCTAssertTrue(app.buttons["Bewaard"].waitForExistence(timeout: 5))
        app.buttons["Sluit"].tap()
        app.segmentedControls.buttons["Kaart"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Lijst"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["discoveryResultList"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDiscoveryPhotoFallbackAttributionAndTransientAddToDay() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Ontdekken"].tap()
        XCTAssertTrue(app.buttons["Restaurants"].waitForExistence(timeout: 8))
        app.buttons["Restaurants"].tap()

        let photo = app.descendants(matching: .any)["discoveryPhoto.ui-restaurant-0"]
        XCTAssertTrue(photo.waitForExistence(timeout: 8))
        app.staticTexts["Restaurants test 1"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["discoveryDetailPhoto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["discoveryPhotoAttribution"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["discoveryPhotoSource"].exists)

        app.buttons["Voeg aan dag toe"].tap()
        XCTAssertTrue(app.buttons["Voeg toe"].waitForExistence(timeout: 5))
        app.buttons["Voeg toe"].tap()
        XCTAssertTrue(app.buttons["Omslag kiezen"].waitForExistence(timeout: 5),
                      "Een transient Google-preview mag niet automatisch een omslag worden")
        app.buttons["Gereed"].tap()
        app.buttons["Sluit"].tap()

        let list = app.descendants(matching: .any)["discoveryResultList"]
        list.swipeUp()
        list.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["discoveryPhotoFallback.ui-restaurant-2"]
            .waitForExistence(timeout: 5))
    }

    @MainActor
    func testDiscoverShowsEmptyStateForIncompatibleFilters() throws {
        let app = launchIsolatedApp(extraArguments: ["--ui-testing-empty-discovery"])
        app.tabBars.buttons["Ontdekken"].tap()
        XCTAssertTrue(app.staticTexts["Geen resultaten binnen deze filters"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Wis filters"].exists)
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
    func testMoreShowsVersionAndCurrentChangelog() throws {
        let app = launchIsolatedApp()
        app.tabBars.buttons["Meer"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["appVersionInfo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reizz"].exists)
        XCTAssertTrue(app.staticTexts["Ontdekken 2.1"].exists)
        app.descendants(matching: .any)["whatsNewRow"].tap()

        XCTAssertTrue(app.navigationBars["Wat is nieuw"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Echte previewfoto's bij Ontdekken-resultaten"].exists)
        XCTAssertTrue(app.staticTexts["Native fallback wanneer geen foto beschikbaar is"].exists)
    }

    @MainActor
    private func launchIsolatedApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"] + extraArguments
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
