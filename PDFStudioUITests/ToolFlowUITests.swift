import XCTest

/// Runs real tool flows end to end on the sample documents (demo mode, no ads prompts).
final class ToolFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", screen]
        app.launch()
        return app
    }

    private func assertResult(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let ready = app.staticTexts["Your file is ready"].waitForExistence(timeout: 60)
            || app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'files are ready'")).firstMatch.exists
        XCTAssertTrue(ready, "result sheet did not appear", file: file, line: line)
        XCTAssertTrue(app.staticTexts["Saved to My Files."].exists, file: file, line: line)
    }

    func testMerge() {
        let app = launch("merge")
        app.buttons["Merge PDF"].firstMatch.tap()
        assertResult(app)
    }

    func testCompress() {
        let app = launch("compress")
        app.buttons["Compress PDF"].firstMatch.tap()
        assertResult(app)
    }

    func testEditAndSave() {
        let app = launch("edit")
        let save = app.navigationBars.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        assertResult(app)
    }

    func testScanToPDF() {
        let app = launch("scan")
        let save = app.buttons["Save as PDF"]
        app.swipeUp()
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        assertResult(app)
    }

    func testConvertPDFToWord() {
        let app = launch("convert")
        let word = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Word'")).firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10))
        word.tap()
        let convert = app.buttons["Convert to Word"]
        if !convert.isHittable { app.swipeUp() }
        XCTAssertTrue(convert.waitForExistence(timeout: 5))
        convert.tap()
        assertResult(app)
    }

    func testResultAppearsInMyFiles() {
        let app = launch("merge")
        app.buttons["Merge PDF"].firstMatch.tap()
        assertResult(app)
        app.buttons["Close"].tap()
        app.tabBars.buttons["My Files"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '_merged'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }
}
