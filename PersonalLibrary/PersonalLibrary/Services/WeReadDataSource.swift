import Foundation

// MARK: - 连接模式

/// 微信读书连接方式
enum WeReadConnectionMode: String, CaseIterable {
    case web = "web"
    case skill = "skill"

    var displayName: String {
        switch self {
        case .web: return "Web 登录"
        case .skill: return "Skill API"
        }
    }

    var description: String {
        switch self {
        case .web: return "通过扫码登录微信读书网页版，使用 Cookie 访问"
        case .skill: return "通过 API Key 调用微信读书 Skill 接口"
        }
    }

    // MARK: - Persistence

    private static let key = "weread_connection_mode"

    static var current: WeReadConnectionMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let mode = WeReadConnectionMode(rawValue: raw) else {
                return .skill
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

// MARK: - 数据源协议

/// 微信读书数据源统一协议
/// Web 模式和 Skill 模式各实现一个 Provider
protocol WeReadDataSource: Sendable {
    /// 是否已连接（Web: 有有效 Cookie; Skill: 有 API Key）
    func isConnected() async -> Bool

    /// 获取所有可导入的书籍（合并书架+进度信息）
    func fetchAllBooks() async throws -> [WeReadImportItem]

    /// 补全单本书信息（详情+阅读时长）
    func enrichBook(bookId: String) async throws -> WeReadEnrichResult

    /// 获取书籍划线/高亮列表
    func fetchBookmarks(bookId: String) async throws -> [WeReadBookmark]

    /// 获取书籍详情
    func fetchBookInfo(bookId: String) async throws -> WeReadShelfBook

    /// 一次性拉取"每本书的划线数"（bookId → noteCount），用于增量检测划线变化。
    /// 默认实现返回 nil，表示该数据源不支持 notebooks 概览（如 Web Cookie 模式）。
    /// Skill 模式覆盖此方法返回真实数据。
    /// （声明为协议要求 + 扩展默认实现，确保通过 any WeReadDataSource 调用时走动态派发）
    func fetchNotebookCounts() async throws -> [String: Int]?

    /// 断开连接（清除凭证）
    func disconnect() async
}

extension WeReadDataSource {
    func fetchNotebookCounts() async throws -> [String: Int]? { nil }
}
