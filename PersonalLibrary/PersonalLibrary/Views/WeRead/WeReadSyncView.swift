import SwiftUI
import SwiftData

/// 微信读书同步管理视图
/// 显示连接方式选择、同步状态、开关自动同步、手动触发同步、登录/登出
struct WeReadSyncView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var connectionMode = WeReadConnectionMode.current
    @State private var isConnected = false
    @State private var autoSyncEnabled = WeReadSyncService.autoSyncEnabled
    @State private var isSyncing = false
    @State private var syncCancelled = false
    @State private var syncProgress: WeReadSyncService.SyncProgress?
    @State private var syncResult: WeReadSyncService.SyncResult?
    @State private var syncTask: Task<Void, Never>?
    @State private var showingLogin = false
    @State private var showingLogoutAlert = false
    @State private var showingWeReadImport = false
    @State private var showingSkillSetup = false

    private let webService = WeReadService()
    private let skillService = WeReadSkillProvider()

    /// 当前活跃的 provider
    private var activeProvider: any WeReadDataSource {
        connectionMode == .web ? webService : skillService
    }

    private var syncService: WeReadSyncService {
        WeReadSyncService(provider: activeProvider)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        List {
            // MARK: - 连接方式
            Section {
                Picker("连接方式", selection: $connectionMode) {
                    ForEach(WeReadConnectionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: connectionMode) { _, newValue in
                    WeReadConnectionMode.current = newValue
                    Task { await checkConnection() }
                }

                Text(connectionMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("连接方式")
            }

            // MARK: - 账号/连接状态
            Section {
                if connectionMode == .web {
                    webAccountSection
                } else {
                    skillAccountSection
                }
            } header: {
                Text("账号")
            } footer: {
                if !isConnected {
                    Text(connectionMode == .web
                         ? "登录后可自动同步微信读书中的电子书和有声书"
                         : "输入 API Key 后可同步微信读书数据")
                }
            }

            // MARK: - 批量导入
            if isConnected {
                Section {
                    Button {
                        showingWeReadImport = true
                    } label: {
                        Label("批量导入（首次使用）", systemImage: "square.and.arrow.down.on.square")
                    }
                } footer: {
                    Text("首次从微信读书导入时使用，可选择导入哪些书")
                }
            }

            // MARK: - 同步设置
            if isConnected {
                Section {
                    Toggle(isOn: $autoSyncEnabled) {
                        Label("自动同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .onChange(of: autoSyncEnabled) { _, newValue in
                        WeReadSyncService.autoSyncEnabled = newValue
                    }

                    Button {
                        if isSyncing {
                            syncCancelled = true
                            syncTask?.cancel()
                        } else {
                            syncCancelled = false
                            syncTask = Task { await performSync() }
                        }
                    } label: {
                        HStack {
                            Label(
                                isSyncing ? (syncCancelled ? "正在停止…" : "停止同步") : "立即同步",
                                systemImage: isSyncing ? "stop.circle" : "arrow.clockwise"
                            )
                            .foregroundStyle(isSyncing ? .red : .accentColor)
                            Spacer()
                            if isSyncing {
                                if let progress = syncProgress, progress.total > 0 {
                                    Text("\(progress.current)/\(progress.total)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(syncCancelled)

                    if isSyncing, let progress = syncProgress {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(progress.phase)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if progress.total > 0 {
                                    Spacer()
                                    Text("\(progress.current)/\(progress.total)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if progress.total > 0 {
                                ProgressView(value: Double(progress.current), total: Double(progress.total))
                            }
                            if let detail = progress.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    if let lastSync = WeReadSyncService.lastSyncDate {
                        HStack {
                            Label("上次同步", systemImage: "clock")
                            Spacer()
                            Text(Self.dateFormatter.string(from: lastSync))
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
                    syncResultSection(result)
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
        .task { await checkConnection() }
        .sheet(isPresented: $showingLogin) {
            WeReadLoginView { cookies in
                Task {
                    await webService.setCookies(cookies)
                    isConnected = true
                    await performSync()
                }
            }
        }
        .sheet(isPresented: $showingSkillSetup) {
            WeReadSkillSetupView(skillService: skillService) {
                Task { await checkConnection() }
            }
        }
        .sheet(isPresented: $showingWeReadImport) {
            WeReadImportView()
        }
        .alert("断开连接", isPresented: $showingLogoutAlert) {
            Button("取消", role: .cancel) {}
            Button("确认断开", role: .destructive) {
                Task {
                    await activeProvider.disconnect()
                    isConnected = false
                    autoSyncEnabled = false
                    WeReadSyncService.autoSyncEnabled = false
                    syncResult = nil
                }
            }
        } message: {
            Text("断开后将停止自动同步，已导入的书籍不受影响")
        }
    }

    // MARK: - Sub Views

    @ViewBuilder
    private var webAccountSection: some View {
        if isConnected {
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
    }

    @ViewBuilder
    private var skillAccountSection: some View {
        if isConnected {
            HStack {
                Label("已连接", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("断开") {
                    showingLogoutAlert = true
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        } else {
            Button {
                showingSkillSetup = true
            } label: {
                Label("配置 API Key", systemImage: "key")
            }
        }
    }

    @ViewBuilder
    private func syncResultSection(_ result: WeReadSyncService.SyncResult) -> some View {
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

                if result.booksArchived > 0 {
                    HStack {
                        Label("已移除", systemImage: "trash.circle.fill")
                            .foregroundStyle(.red)
                        Spacer()
                        Text("\(result.booksArchived) 本")
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

    // MARK: - Actions

    private func checkConnection() async {
        isConnected = await activeProvider.isConnected()
    }

    private func performSync() async {
        isSyncing = true
        syncProgress = nil
        syncResult = nil
        defer {
            isSyncing = false
            syncCancelled = false
            syncProgress = nil
            syncTask = nil
        }

        let result = await syncService.sync(modelContext: modelContext) { progress in
            Task { @MainActor in
                syncProgress = progress
            }
        }
        syncResult = result

        if result.error?.contains("过期") == true || result.error?.contains("登录") == true {
            isConnected = false
        }
    }
}

#Preview {
    NavigationStack {
        WeReadSyncView()
    }
    .modelContainer(for: [Book.self, Tag.self], inMemory: true)
}
