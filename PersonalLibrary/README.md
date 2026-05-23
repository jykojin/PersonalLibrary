# PersonalLibrary (私人图书馆)

iOS 个人图书管理应用，帮助你追踪纸质书、电子书和有声书的阅读进度。

## 功能特性

- **多类型书籍管理** — 纸质书 / 电子书 / 有声书分类管理
- **扫码录入** — 扫描 ISBN 条形码自动获取书籍信息（Open Library / Google Books / 豆瓣）
- **微信读书同步** — 一键导入微信读书书架，自动同步阅读进度
- **阅读记录** — 按日记录阅读页数、时长，生成统计图表
- **书架与标签** — 自定义书架分组 + 多标签管理
- **批量操作** — 多选后批量打标签、移动书架、修改状态、评分
- **Excel 导入导出** — XLSX 格式批量导入/导出书单
- **高级搜索** — 按书名、作者、出版社、标签等多维度筛选

## 技术栈

| 层级 | 技术 |
|------|------|
| UI | SwiftUI (iOS 17+) |
| 数据持久化 | SwiftData |
| 项目管理 | XcodeGen (`project.yml`) |
| 依赖 | CoreXLSX (SPM) |
| 安全存储 | Keychain Services |
| 网络 | URLSession (async/await) |
| 测试 | Swift Testing framework |

## 项目结构

```
PersonalLibrary/
├── Models/          # SwiftData 数据模型 (Book, Tag, Bookshelf, ReadingRecord)
├── Services/        # 业务逻辑
│   ├── WeReadService.swift        # 微信读书 API
│   ├── WeReadSyncService.swift    # 微信读书同步引擎
│   ├── ISBNLookupService.swift    # ISBN 查询（多源）
│   ├── ExcelImportExportService.swift  # XLSX 导入导出
│   ├── KeychainService.swift      # 安全凭证存储
│   └── StorageManager.swift       # SwiftData 容器管理
├── Views/           # SwiftUI 视图
│   ├── Books/       # 书籍列表、详情、编辑
│   ├── Bookshelf/   # 书架管理
│   ├── Reading/     # 阅读记录与统计
│   ├── WeRead/      # 微信读书登录/导入/同步
│   ├── Scanner/     # 条码扫描
│   └── Settings/    # 设置、导入导出
└── PersonalLibraryApp.swift  # 应用入口 + 数据迁移
```

## 构建与运行

### 环境要求

- macOS 14+ / Xcode 15+
- iOS 17+ (模拟器或真机)

### 步骤

```bash
# 1. 克隆仓库
git clone https://github.com/jykojin/PersonalLibrary.git
cd PersonalLibrary

# 2. 生成 Xcode 项目
xcodegen generate

# 3. 构建
xcodebuild -scheme PersonalLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/PersonalLibrary-DerivedData build

# 4. 运行测试
xcodebuild -scheme PersonalLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/PersonalLibrary-DerivedData test
```

也可以直接用 Xcode 打开 `PersonalLibrary.xcodeproj` 运行。

## 测试

项目使用 Swift Testing 框架，覆盖：

- 数据模型 (Book, Tag, Bookshelf, ReadingRecord)
- 枚举逻辑 (ReadingStatus, BookType, AddSource)
- 微信读书同步逻辑
- 微信读书导入去重
- Excel 导入导出
- ISBN 查询结果解析
- 评分功能

运行：`xcodebuild test -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`

## 安全设计

- Cookie 存储在 iOS Keychain（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`）
- WeRead API 请求参数经过格式校验，防止注入
- XLSX 导入限制 50MB 文件大小
- WKWebView 使用非持久化 DataStore，防止 session 泄露
- 无硬编码密钥（微信 AppID 需自行配置）

## 配置

微信读书功能需要在 `WeChatAuthManager.swift` 中配置有效的微信 AppID/AppSecret（建议通过后端代理 token 交换）。

## License

Private project. All rights reserved.
