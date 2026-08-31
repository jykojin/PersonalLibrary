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

    /// 「数据备份」页的三个文件选择按钮都必须能真的弹出文件选择器。
    ///
    /// 回归防护：三个 `.fileImporter` 曾全部挂在同一个 `List` 上，
    /// SwiftUI 只让最后一个（导入 AI介绍）生效，前两个点了没任何反应。
    @MainActor
    func testDataBackupFilePickersAllPresent() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["更多"].tap()
        let backupRow = app.buttons["数据备份"]
        XCTAssertTrue(backupRow.waitForExistence(timeout: 5), "找不到「数据备份」入口")
        backupRow.tap()

        for label in ["从备份恢复", "从 Excel 导入", "导入 AI介绍"] {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "找不到按钮「\(label)」")
            button.tap()

            let dismiss = app.descendants(matching: .button).matching(
                NSPredicate(format: "label IN {'取消', 'Cancel'}")
            ).firstMatch
            XCTAssertTrue(
                dismiss.waitForExistence(timeout: 8),
                "点「\(label)」后文件选择器没有出现"
            )
            dismiss.tap()
            XCTAssertTrue(
                button.waitForExistence(timeout: 5),
                "关掉选择器后没能回到「数据备份」页"
            )
        }
    }
}
