import SwiftUI
import SwiftData

/// 设置页面
struct ImportExportView: View {
    @Environment(\.modelContext) private var modelContext

    // 存储设置
    @State private var storageLocation: StorageLocation = StorageManager.shared.currentLocation
    @State private var showingStorageChangeAlert = false

    private static let syncDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    /// 应用版本号 — 由 project.yml 的 MARKETING_VERSION 写入 Info.plist
    /// 与 git push tag 保持一致（push 前先更新 MARKETING_VERSION）
    private static let appVersion: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
        return "v\(v)"
    }()

    var body: some View {
        List {
            // MARK: - 微信读书
            Section {
                NavigationLink(destination: WeReadSyncView()) {
                    HStack {
                        Label("微信读书同步", systemImage: "book.and.wreath")
                        Spacer()
                        if let lastSync = WeReadSyncService.lastSyncDate {
                            Text(Self.syncDateFormatter.string(from: lastSync))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("微信读书")
            } footer: {
                Text("同步和批量导入微信读书书架")
            }

            // MARK: - 数据维护
            Section {
                NavigationLink(destination: DataMaintenanceView()) {
                    Label("数据维护", systemImage: "wrench.and.screwdriver")
                }
            } header: {
                Text("数据维护")
            } footer: {
                Text("管理作者、出版社、标签，批量修改名称，繁转简等")
            }

            // MARK: - 数据备份
            Section {
                NavigationLink(destination: DataBackupView()) {
                    Label("数据备份", systemImage: "externaldrive")
                }
            } header: {
                Text("数据备份")
            } footer: {
                Text("备份/恢复数据库，导入/导出书单")
            }

            // MARK: - 应用日志
            Section {
                NavigationLink(destination: LogViewerView()) {
                    Label("应用日志", systemImage: "doc.text.magnifyingglass")
                }
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

            // MARK: - 关于
            Section {
                HStack {
                    Label("版本", systemImage: "info.circle")
                    Spacer()
                    Text(Self.appVersion)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("关于")
            }
        }
        .navigationTitle("设置")
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
