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
                Text("支持 XLSX 格式导入，导出为 TSV 格式（Excel 可直接打开）")
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

    private func exportBooks() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let data = try await importExportService.exportBooks(books: activeBooks)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            let fileName = "书单导出_\(formatter.string(from: Date())).tsv"
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
