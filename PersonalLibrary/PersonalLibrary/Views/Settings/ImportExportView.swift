import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 导入导出与设置视图
struct ImportExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.addedDate, order: .reverse) private var allBooks: [Book]

    @State private var showingImportPicker = false
    @State private var showingExportShare = false
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var importResult: ExcelImportExportService.ImportResult?
    @State private var showingImportResult = false
    @State private var exportFileURL: URL?
    @State private var errorMessage: String?
    @State private var showingError = false

    // 微信读书
    @State private var showingWeReadImport = false

    // 存储设置
    @State private var storageLocation: StorageLocation = StorageManager.shared.currentLocation
    @State private var showingStorageChangeAlert = false

    // 备份恢复
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var backups: [BackupInfo] = []
    @State private var showingBackupSuccess = false
    @State private var lastBackupInfo: BackupInfo?
    @State private var showingRestoreConfirm = false
    @State private var selectedBackup: BackupInfo?
    @State private var showingRestoreSuccess = false

    private let importExportService = ExcelImportExportService()

    var body: some View {
        List {
            // MARK: - 账户
            Section("账户") {
                ProfileView()
            }

            // MARK: - 存储位置
            Section {
                ForEach(StorageLocation.allCases, id: \.self) { location in
                    Button {
                        if location != storageLocation {
                            storageLocation = location
                            showingStorageChangeAlert = true
                        }
                    } label: {
                        HStack {
                            Label(location.description, systemImage: location.icon)
                                .foregroundStyle(.primary)
                            Spacer()
                            if location == storageLocation {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            } header: {
                Text("数据存储位置")
            } footer: {
                Text("切换存储位置需要重启 App 后生效。iCloud 存储可在多台设备间自动同步数据。")
            }

            // MARK: - 备份与恢复
            Section {
                Button {
                    Task { await performBackup() }
                } label: {
                    HStack {
                        Label("立即备份", systemImage: "icloud.and.arrow.up")
                        Spacer()
                        if isBackingUp {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isBackingUp || isRestoring)

                if !backups.isEmpty {
                    ForEach(backups) { backup in
                        Button {
                            selectedBackup = backup
                            showingRestoreConfirm = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(backup.formattedDate)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Text(backup.formattedSize)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isRestoring && selectedBackup?.url == backup.url {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.counterclockwise")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .disabled(isRestoring || isBackingUp)
                    }
                }
            } header: {
                Text("备份与恢复")
            } footer: {
                Text("备份数据库到 iCloud Drive，恢复后需重启 App。")
            }

            // MARK: - 微信读书
            Section {
                NavigationLink(destination: WeReadSyncView()) {
                    HStack {
                        Label("微信读书同步", systemImage: "book.and.wreath")
                        Spacer()
                        if let lastSync = WeReadSyncService.lastSyncDate {
                            Text(lastSync, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    showingWeReadImport = true
                } label: {
                    Label("批量导入（首次）", systemImage: "square.and.arrow.down.on.square")
                }
            } header: {
                Text("微信读书")
            } footer: {
                Text("同步：自动增量更新书架和阅读进度\n批量导入：首次从微信读书导入时使用，可选择导入哪些书")
            }

            // MARK: - 导入
            Section {
                Button {
                    showingImportPicker = true
                } label: {
                    HStack {
                        Label("从 Excel 导入", systemImage: "square.and.arrow.down")
                        Spacer()
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isImporting)
            } header: {
                Text("导入")
            } footer: {
                Text("支持 .xlsx 格式，兼容「私家书藏」导出的书单文件")
            }

            // MARK: - 导出
            Section {
                Button {
                    Task { await exportBooks() }
                } label: {
                    HStack {
                        Label("导出书单", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("\(allBooks.count) 本书")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isExporting || allBooks.isEmpty)
            } header: {
                Text("导出")
            } footer: {
                Text("导出为制表符分隔的文本文件（.tsv），可用 Excel 或 Numbers 打开")
            }

            // MARK: - 操作历史
            Section {
                NavigationLink(destination: ImportHistoryView()) {
                    Label("导入/添加历史", systemImage: "clock.arrow.circlepath")
                }
            }

            // MARK: - 数据统计
            Section("数据概览") {
                LabeledContent("总藏书", value: "\(allBooks.count) 本")
                LabeledContent("正在读", value: "\(allBooks.filter { $0.status == .reading }.count) 本")
                LabeledContent("已读", value: "\(allBooks.filter { $0.status == .finished }.count) 本")
                LabeledContent("想读", value: "\(allBooks.filter { $0.status == .wishlist }.count) 本")
            }
        }
        .navigationTitle("设置")
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [UTType(filenameExtension: "xlsx")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await importBooks(from: url) }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
        .sheet(isPresented: $showingWeReadImport) {
            WeReadImportView()
        }
        .sheet(isPresented: $showingExportShare) {
            if let url = exportFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert("导入完成", isPresented: $showingImportResult) {
            Button("好的") {}
        } message: {
            if let result = importResult {
                Text("成功导入 \(result.successCount) 本书" +
                     (result.failedCount > 0 ? "\n\(result.failedCount) 条记录导入失败" : ""))
            }
        }
        .alert("错误", isPresented: $showingError) {
            Button("好的") {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .alert("切换存储位置", isPresented: $showingStorageChangeAlert) {
            Button("确认切换", role: .destructive) {
                StorageManager.shared.currentLocation = storageLocation
            }
            Button("取消", role: .cancel) {
                storageLocation = StorageManager.shared.currentLocation
            }
        } message: {
            Text("将数据存储位置切换为「\(storageLocation.description)」？\n\n切换后需要重启 App 才能生效。已有数据不会自动迁移到新位置。")
        }
        .alert("备份成功", isPresented: $showingBackupSuccess) {
            Button("好的") {}
        } message: {
            if let info = lastBackupInfo {
                Text("已备份到 iCloud Drive\n大小：\(info.formattedSize)")
            }
        }
        .alert("确认恢复", isPresented: $showingRestoreConfirm) {
            Button("恢复", role: .destructive) {
                if let backup = selectedBackup {
                    Task { await performRestore(from: backup) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let backup = selectedBackup {
                Text("将恢复 \(backup.formattedDate) 的备份？\n\n当前数据将被覆盖，恢复后需重启 App。")
            }
        }
        .alert("恢复成功", isPresented: $showingRestoreSuccess) {
            Button("好的") {}
        } message: {
            Text("数据库已恢复，请重启 App 以加载恢复的数据。")
        }
        .task {
            await loadBackups()
        }
    }

    // MARK: - Backup & Restore

    private func loadBackups() async {
        do {
            backups = try await BackupService.shared.listBackups()
        } catch {
            // iCloud 不可用时静默处理
            backups = []
        }
    }

    private func performBackup() async {
        isBackingUp = true
        defer { isBackingUp = false }

        do {
            let info = try await BackupService.shared.createBackup()
            lastBackupInfo = info
            showingBackupSuccess = true
            await loadBackups()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func performRestore(from backup: BackupInfo) async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await BackupService.shared.restoreBackup(from: backup)
            showingRestoreSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    // MARK: - Import

    private func importBooks(from url: URL) async {
        isImporting = true
        defer { isImporting = false }

        do {
            let result = try await importExportService.importBooks(from: url, modelContext: modelContext)
            importResult = result

            // 记录导入历史
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

    // MARK: - Export

    private func exportBooks() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let data = try await importExportService.exportBooks(books: allBooks)

            // 保存到临时文件
            let fileName = "书单导出_\(formattedDate()).tsv"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL)

            exportFileURL = tempURL
            showingExportShare = true
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
            showingError = true
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        ImportExportView()
    }
    .modelContainer(for: [Book.self, Bookshelf.self, Tag.self, ReadingRecord.self], inMemory: true)
}
