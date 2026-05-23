import XCTest

final class PersonalLibraryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesSuccessfully() throws {
        let app = XCUIApplication()
        app.launch()

        // 验证 TabBar 存在
        XCTAssertTrue(app.tabBars.buttons["藏书"].exists)
        XCTAssertTrue(app.tabBars.buttons["书架"].exists)
        XCTAssertTrue(app.tabBars.buttons["统计"].exists)
        XCTAssertTrue(app.tabBars.buttons["更多"].exists)
    }

    @MainActor
    func testAddBookFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // 点击添加按钮
        app.navigationBars.buttons["plus"].tap()

        // 验证添加书籍表单出现
        XCTAssertTrue(app.navigationBars["添加新书"].exists)
    }
}
