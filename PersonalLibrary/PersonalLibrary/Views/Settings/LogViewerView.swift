import SwiftUI

/// 日志查看与导出视图
struct LogViewerView: View {
    @State private var logFiles: [LogFileInfo] = []
    @State private var totalSize: String = ""
    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    @State private var showingClearConfirm = false
    @State private var previewContent: String = ""
    @State private var showingPreview = false

    var body: some View {
        List {
            // MARK: - 概览
            Section {
                HStack {
                    Label("日志文件数", systemImage: "doc.text")
                    Spacer()
                    Text("\(logFiles.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("总大小", systemImage: "internaldrive")
                    Spacer()
                    Text(totalSize)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("概览")
            }

            // MARK: - 文件列表
            Section {
                if logFiles.isEmpty {
                    Text("暂无日志文件")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logFiles, id: \.url) { file in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.subheadline)
                                Text(file.sizeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            } header: {
                Text("文件列表")
            }

            // MARK: - 操作
            Section {
                Button {
                    previewRecentLogs()
                } label: {
                    Label("预览最近日志", systemImage: "eye")
                }
                .disabled(logFiles.isEmpty)

                Button {
                    exportLogs()
                } label: {
                    Label("导出全部日志", systemImage: "square.and.arrow.up")
                }
                .disabled(logFiles.isEmpty)

                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Label("清空日志", systemImage: "trash")
                }
                .disabled(logFiles.isEmpty)
            } header: {
                Text("操作")
            }
        }
        .navigationTitle("应用日志")
        .onAppear { refreshFileList() }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showingPreview) {
            NavigationStack {
                ScrollView {
                    Text(previewContent)
                        .font(.system(.caption2, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle("最近日志")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { showingPreview = false }
                    }
                }
            }
        }
        .alert("确认清空", isPresented: $showingClearConfirm) {
            Button("清空", role: .destructive) {
                FileLogger.shared.clearAll()
                // 延迟刷新，等 queue 执行完
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    refreshFileList()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有日志文件，此操作不可恢复。")
        }
    }

    // MARK: - Private

    private func refreshFileList() {
        let files = FileLogger.shared.logFiles
        logFiles = files.map { url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            return LogFileInfo(url: url, name: url.lastPathComponent, size: size)
        }
        totalSize = formatSize(FileLogger.shared.totalSize)
    }

    private func previewRecentLogs() {
        let content = FileLogger.shared.mergedContent()
        // 只显示最后 200 行
        let lines = content.components(separatedBy: "\n")
        let tail = lines.suffix(200)
        previewContent = tail.joined(separator: "\n")
        showingPreview = true
    }

    private func exportLogs() {
        let content = FileLogger.shared.mergedContent()
        let fileName = "PersonalLibrary_logs_\(exportDateString()).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        shareURL = tempURL
        showingShareSheet = true
    }

    private func formatSize(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func exportDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}

// MARK: - Model

private struct LogFileInfo: Identifiable {
    let url: URL
    let name: String
    let size: UInt64

    var id: URL { url }

    var sizeText: String {
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / (1024 * 1024))
    }
}

#Preview {
    NavigationStack {
        LogViewerView()
    }
}
