import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 数据备份页面：备份数据库、恢复数据库、导入书单、导出书单
struct DataBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.addedDate, order: .reverse) private var allBooks: [Book]

    // Backup/Restore state
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var showingBackupShare = false
    @State private var backupFileURL: URL?
    @State private var showingRestoreConfirm = false
    @State private var restoreFileURL: URL?
    @State private var showingRestoreSuccess = false
    @State private var showingRestorePicker = false

    // Import/Export state
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var showingImportPicker = false
    @State private var showingImportResult = false
    @State private var importResult: ExcelImportExportService.ImportResult?
    @State private var showingExportShare = false
    @State private var exportFileURL: URL?

    // AI介绍 回填 state
    @State private var isImportingIntros = false
    @State private var showingIntroPicker = false
    @State private var introParsedCount = 0
    @State private var introResult: BookIntroductionSeeder.Result?
    @State private var showingIntroResult = false

    // Error
    @State private var errorMessage = ""
    @State private var showingError = false

    private let importExportService = ExcelImportExportService()

    private var activeBooks: [Book] {
        allBooks.filter { !$0.isArchived }
    }

    var body: some View {
        List {
            // MARK: - 数据库备份/恢复
            Section {
                Button {
                    Task { await performBackup() }
                } label: {
                    HStack {
                        Label("备份数据库", systemImage: "arrow.up.doc")
                        Spacer()
                        if isBackingUp {
                            ProgressView()
                        }
                    }
                }
                .disabled(isBackingUp)

                Button {
                    showingRestorePicker = true
                } label: {
                    HStack {
                        Label("从备份恢复", systemImage: "arrow.down.doc")
                        Spacer()
                        if isRestoring {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRestoring)
            } header: {
                Text("数据库")
            } footer: {
                Text("备份整个数据库文件，恢复后需重启 App")
            }

            // MARK: - 书单导入/导出
            Section {
                Button {
                    showingImportPicker = true
                } label: {
                    HStack {
                        Label("从 Excel 导入", systemImage: "square.and.arrow.down")
                        Spacer()
                        if isImporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isImporting)

                Button {
                    showingIntroPicker = true
                } label: {
                    HStack {
                        Label("导入 AI介绍", systemImage: "sparkles")
                        Spacer()
                        if isImportingIntros {
                            ProgressView()
                        }
                    }
                }
                .disabled(isImportingIntros)

                Button {
                    Task { await exportBooks() }
                } label: {
                    HStack {
                        Label("导出书单", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                        Text("\(activeBooks.count) 本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isExporting)
            } header: {
                Text("书单")
            } footer: {
                Text("导入导出均为 XLSX 格式，导出的文件可被本应用重新导入。\n「导入 AI介绍」只按 微信读书ID／ISBN／书名+作者 把该列回填到已有书籍，只补空值、不会新增书。")
            }
        }
        .navigationTitle("数据备份")
        // File picker for restore
        .fileImporter(
            isPresented: $showingRestorePicker,
            allowedContentTypes: [UTType(filenameExtension: "plbackup") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                restoreFileURL = url
                showingRestoreConfirm = true
            }
        }
        // File picker for import
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await importBooks(from: url) }
            }
        }
        // File picker for AI介绍 回填
        .fileImporter(
            isPresented: $showingIntroPicker,
            allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await importIntroductions(from: url) }
            }
        }
        // Share sheet for backup
        .sheet(isPresented: $showingBackupShare) {
            if let url = backupFileURL {
                ShareSheet(items: [url])
            }
        }
        // Share sheet for export
        .sheet(isPresented: $showingExportShare) {
            if let url = exportFileURL {
                ShareSheet(items: [url])
            }
        }
        // Alerts
        .alert("确认恢复", isPresented: $showingRestoreConfirm) {
            Button("恢复", role: .destructive) {
                if let url = restoreFileURL {
                    Task { await performRestore(from: url) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前数据将被覆盖，恢复后需重启 App 才能生效。确认恢复？")
        }
        .alert("恢复成功", isPresented: $showingRestoreSuccess) {
            Button("好的") {}
        } message: {
            Text("数据库已恢复，请重启 App 以加载恢复的数据。")
        }
        .alert("导入完成", isPresented: $showingImportResult) {
            Button("好的") {}
        } message: {
            if let r = importResult {
                Text("成功导入 \(r.successCount) 本书" + (r.failedCount > 0 ? "，\(r.failedCount) 本失败" : ""))
            }
        }
        .alert("AI介绍 回填完成", isPresented: $showingIntroResult) {
            Button("好的") {}
        } message: {
            if let r = introResult {
                Text("文件里有 \(introParsedCount) 条介绍，已更新 \(r.updated) 本书"
                     + (r.unmatched > 0 ? "，\(r.unmatched) 条在书库里找不到对应书籍" : "")
                     + "。\n已有内容的书不会被覆盖。")
            }
        }
        .alert("错误", isPresented: $showingError) {
            Button("好的") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Backup & Restore

    private func performBackup() async {
        isBackingUp = true
        defer { isBackingUp = false }

        do {
            let info = try await BackupService.shared.createBackup()
            backupFileURL = info.url
            showingBackupShare = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func performRestore(from url: URL) async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await BackupService.shared.restoreBackup(from: url)
            showingRestoreSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    // MARK: - Import & Export

    private func importBooks(from url: URL) async {
        isImporting = true
        defer { isImporting = false }

        do {
            let result = try await importExportService.importBooks(from: url, modelContext: modelContext)
            importResult = result

            let record = ImportRecord(
                source: "文件导入",
                totalCount: result.successCount + result.failedCount,
                successCount: result.successCount,
                skippedCount: result.failedCount,
                note: url.lastPathComponent
            )
            modelContext.insert(record)
            try? modelContext.save()

            showingImportResult = true
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
            showingError = true
        }
    }

    /// 用选中的 xlsx 回填「AI介绍」到已有书籍：只补空值、绝不新增书。
    private func importIntroductions(from url: URL) async {
        isImportingIntros = true
        defer { isImportingIntros = false }

        do {
            let entries = try await importExportService.parseIntroductionEntries(from: url)
            let result = BookIntroductionSeeder.backfill(entries, into: modelContext)
            if result.updated > 0 {
                try modelContext.save()
            }
            AppLogger.info(
                "AI介绍 导入：文件 \(entries.count) 条，更新 \(result.updated) 本，未匹配 \(result.unmatched) 条",
                category: "IntroImport"
            )
            introParsedCount = entries.count
            introResult = result
            showingIntroResult = true
        } catch {
            errorMessage = "导入 AI介绍 失败：\(error.localizedDescription)"
            showingError = true
        }
    }

    private func exportBooks() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let data = try await importExportService.exportBooks(books: activeBooks)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            let fileName = "书单导出_\(formatter.string(from: Date())).xlsx"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL)

            exportFileURL = tempURL
            showingExportShare = true
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
            showingError = true
        }
    }
}

#Preview {
    NavigationStack {
        DataBackupView()
    }
    .modelContainer(for: [Book.self, Bookshelf.self, Tag.self, ReadingRecord.self, ImportRecord.self], inMemory: true)
}
