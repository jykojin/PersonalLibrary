import Foundation
import Objects2XLSX

/// XLSX 写入器 —— 把表头 + 字符串行写成标准 .xlsx 数据。
///
/// 单独成文件、仅 `import Objects2XLSX`，避免它导出的 `Row`/`Cell` 类型与
/// `ExcelImportExportService` 里 `import CoreXLSX` 的同名类型冲突。
enum XLSXWriter {

    /// 一行导出数据，字段顺序与表头对齐。Sendable 以配合 Objects2XLSX 的并发要求。
    private struct ExportRow: Sendable {
        let fields: [String]
    }

    /// 把表头和数据行写成 xlsx，返回文件的二进制数据。
    /// - Parameters:
    ///   - headers: 列标题
    ///   - rows: 每行的字段数组（长度应与 headers 一致）
    ///   - sheetName: 工作表名
    static func write(headers: [String], rows: [[String]], sheetName: String) throws -> Data {
        let exportRows = rows.map { ExportRow(fields: $0) }

        let sheet = Sheet<ExportRow>(name: sheetName, dataProvider: { exportRows }) {
            for col in headers.indices {
                Column(name: headers[col], keyPath: \ExportRow.fields[col])
            }
        }

        // 直接用 [AnySheet] 初始化并 append，避开 @SheetBuilder 单元素变参的类型推断问题
        let book = Objects2XLSX.Book(style: BookStyle(), sheets: [])
        book.append(sheet: sheet)

        // Objects2XLSX 只写文件：写到临时目录后读回为 Data。
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try book.write(to: tempURL)
        return try Data(contentsOf: tempURL)
    }
}
