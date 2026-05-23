import SwiftUI
import SwiftData

/// 微信读书同步管理视图
/// 显示同步状态、开关自动同步、手动触发同步、登录/登出
struct WeReadSyncView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isLoggedIn = false
    @State private var autoSyncEnabled = WeReadSyncService.autoSyncEnabled
    @State private var isSyncing = false
    @State private var syncProgress: WeReadSyncService.SyncProgress?
    @State private var syncResult: WeReadSyncService.SyncResult?
    @State private var showingLogin = false
    @State private var showingLogoutAlert = false

    private let service = WeReadService()
    private let syncService = WeReadSyncService()

    var body: some View {
        List {
            // MARK: - 登录状态
            Section {
                if isLoggedIn {
                    HStack {
                        Label("已登录", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("退出登录") {
                            showingLogoutAlert = true
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                } else {
                    Button {
                        showingLogin = true
                    } label: {
                        Label("扫码登录微信读书", systemImage: "qrcode")
                    }
                }
            } header: {
                Text("账号")
            } footer: {
                if !isLoggedIn {
                    Text("登录后可自动同步微信读书中的电子书和有声书")
                }
            }

            // MARK: - 同步设置
            if isLoggedIn {
                Section {
                    Toggle(isOn: $autoSyncEnabled) {
                        Label("自动同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .onChange(of: autoSyncEnabled) { _, newValue in
                        WeReadSyncService.autoSyncEnabled = newValue
                    }

                    // 手动同步按钮
                    Button {
                        Task { await performSync() }
                    } label: {
                        HStack {
                            Label("立即同步", systemImage: "arrow.clockwise")
                            Spacer()
                            if isSyncing {
                                if let progress = syncProgress, progress.total > 0 {
                                    Text("\(progress.current)/\(progress.total)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isSyncing)

                    // 同步进度详情
                    if isSyncing, let progress = syncProgress {
                        HStack {
                            Text(progress.phase)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if progress.total > 0 {
                                Spacer()
                                ProgressView(value: Double(progress.current), total: Double(progress.total))
                                    .frame(width: 100)
                            }
                        }
                    }

                    // 上次同步时间
                    if let lastSync = WeReadSyncService.lastSyncDate {
                        HStack {
                            Label("上次同步", systemImage: "clock")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("同步")
                } footer: {
                    Text("开启自动同步后，每次打开 App 会自动检查微信读书更新（间隔不少于 1 小时）")
                }

                // MARK: - 同步结果
                if let result = syncResult {
                    Section("同步结果") {
                        if let error = result.error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.subheadline)
                        } else {
                            HStack {
                                Label("远程书架", systemImage: "books.vertical")
                                Spacer()
                                Text("\(result.totalRemote) 本")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)

                            if result.newBooksImported > 0 {
                                HStack {
                                    Label("新增导入", systemImage: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                    Spacer()
                                    Text("\(result.newBooksImported) 本")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }

                            if result.progressUpdated > 0 {
                                HStack {
                                    Label("进度更新", systemImage: "chart.line.uptrend.xyaxis")
                                        .foregroundStyle(.blue)
                                    Spacer()
                                    Text("\(result.progressUpdated) 本")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }

                            if result.statusUpdated > 0 {
                                HStack {
                                    Label("状态变更", systemImage: "arrow.right.circle.fill")
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Text("\(result.statusUpdated) 本")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }

                            if !result.hasChanges {
                                Label("已是最新，无需更新", systemImage: "checkmark.circle")
                                    .foregroundStyle(.green)
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                // MARK: - 同步说明
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("新书自动导入", systemImage: "plus.square")
                        Label("阅读进度自动更新", systemImage: "chart.bar.fill")
                        Label("读完状态自动同步", systemImage: "checkmark.seal")
                        Label("不会覆盖本地手动修改", systemImage: "hand.raised")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("同步规则")
                }
            }
        }
        .navigationTitle("微信读书同步")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoggedIn = await service.isLoggedIn()
        }
        .sheet(isPresented: $showingLogin) {
            WeReadLoginView { cookies in
                Task {
                    await service.setCookies(cookies)
                    isLoggedIn = true
                    await performSync()
                }
            }
        }
        .alert("退出登录", isPresented: $showingLogoutAlert) {
            Button("取消", role: .cancel) {}
            Button("确认退出", role: .destructive) {
                Task {
                    await service.logout()
                    isLoggedIn = false
                    autoSyncEnabled = false
                    WeReadSyncService.autoSyncEnabled = false
                    syncResult = nil
                }
            }
        } message: {
            Text("退出后将停止自动同步，已导入的书籍不受影响")
        }
    }

    // MARK: - Sync Action

    private func performSync() async {
        isSyncing = true
        syncProgress = nil
        defer {
            isSyncing = false
            syncProgress = nil
        }

        let result = await syncService.sync(modelContext: modelContext) { progress in
            Task { @MainActor in
                syncProgress = progress
            }
        }
        syncResult = result

        if result.error?.contains("过期") == true || result.error?.contains("登录") == true {
            isLoggedIn = false
        }
    }
}

#Preview {
    NavigationStack {
        WeReadSyncView()
    }
    .modelContainer(for: [Book.self, Tag.self], inMemory: true)
}
