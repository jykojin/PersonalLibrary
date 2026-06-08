# PersonalLibrary (私人图书馆)

> iOS 个人图书管理应用，帮助你追踪纸质书、电子书和有声书的阅读进度。
> 当前版本: **v0.57**

## 功能特性

### 图书管理
- **多类型** — 纸质书 / 电子书 / 有声书
- **多入口添加** — 手动 / 扫码 / Excel 导入 / 微信读书同步
- **扫码录入** — 扫描 ISBN 条形码自动获取书籍信息
- **多源智能补全** — 豆瓣 → Open Library → Google Books → Goodreads 串联查询

### 微信读书集成
- **两种连接方式** — Web 扫码登录 / Skill API Key
- **批量导入** — 一键导入微信读书全部书架
- **增量同步** — 自动检查更新，只补全缺失字段
- **进度同步** — 阅读时长、TTS 时长、完成日期、开始日期
- **划线笔记** — 自动同步划线到本地备注
- **同步历史** — 查看每次同步的统计与结果
- **限速保护** — 全局豆瓣 5 秒间隔避免 IP 封禁
- **后台并发** — 批量补全 3 路并发，stop 按钮可即时取消

### 封面管理
- **多来源** — 网络搜索（内置浏览器 Google/百度/Bing 长按取图）/ 相册 / 拍照 / ISBN 自动下载
- **内置浏览器搜图** — WKWebView 加载真实图片搜索页，长按图片确认后选用，相关性由搜索引擎负责
- **裁剪编辑器** — 选定图片后可缩放、平移、自由比例裁剪、90° 旋转，确定后再设为封面
- **统一缩略图化** — 所有来源的封面统一压成 ≤800px JPEG，避免大图内联导致数据库膨胀

### 阅读追踪
- **状态机** — 想读 / 闲置 / 正在读 / 已读 / 弃读
- **阅读记录** — 按日记录页数、时长，自动更新当前页和状态
- **统计图表** — 年度/月度入库与读完趋势，柱状图可点击查看对应书籍

### 组织与搜索
- **书架与标签** — 自定义书架 + 多标签
- **批量操作** — 多选后批量打标签 / 移动书架 / 改状态 / 评分
- **高级搜索** — 多维度筛选（书名、作者、出版社、标签、ISBN）
- **数据维护** — 作者/出版社/标签清单 + 繁转简 + 分隔符规范化 + 批量补全

### 数据安全
- **数据库备份/恢复** — 一键备份 SwiftData 存储 + WAL 文件
- **Excel 导入导出** — XLSX 格式，含微信读书元数据字段
- **iCloud 同步** — SwiftData CloudKit 集成（可选）
- **应用日志** — 三档日志模式，可导出排查问题

## 技术栈

| 层级 | 技术 |
|------|------|
| UI | SwiftUI (iOS 17+) |
| 数据持久化 | SwiftData (SQLite) |
| 云同步 | CloudKit (可选) |
| 项目管理 | XcodeGen (`project.yml`) |
| 依赖 | CoreXLSX (SPM) |
| 安全存储 | Keychain Services |
| 网络 | URLSession (async/await) |
| 并发 | Swift Concurrency (actors, TaskGroup) |
| 测试 | Swift Testing framework (291+ tests) |

## 项目结构

```
PersonalLibrary/
├── Models/                  # SwiftData @Model
│   ├── Book.swift                  # 主体模型
│   ├── Bookshelf.swift             # 书架
│   ├── Tag.swift                   # 标签
│   ├── ReadingRecord.swift         # 阅读记录
│   ├── ImportRecord.swift          # 导入历史
│   └── SyncHistoryRecord.swift     # 同步历史
├── Services/                # 业务逻辑
│   ├── ISBNLookupService.swift     # 多源 ISBN 查询 + DoubanRateLimiter
│   ├── DoubanDescriptionFetcher.swift  # 豆瓣 HTML 解析
│   ├── CoverFetchService.swift     # 封面下载与缓存
│   ├── WeReadService.swift         # 微信读书 Web API
│   ├── WeReadSkillProvider.swift   # 微信读书 Skill API
│   ├── WeReadDataSource.swift      # Web/Skill 抽象协议
│   ├── WeReadSyncService.swift     # 同步引擎（含取消支持）
│   ├── ExcelImportExportService.swift  # XLSX 导入导出
│   ├── BackupService.swift         # 数据库备份恢复
│   ├── BookService.swift           # 共享操作（标签查找、图片下载）
│   ├── CoverImageProcessor.swift   # 封面统一缩略图化（≤800px）
│   ├── StorageManager.swift        # SwiftData 容器 + 容错启动兜底
│   ├── KeychainService.swift       # 安全凭证存储
│   ├── AppLogger.swift             # 三档日志接口
│   └── FileLogger.swift            # 文件日志（rotation）
├── Views/
│   ├── Books/                      # 列表/详情/编辑/添加/筛选/高级搜索 + 封面裁剪（CoverCropView/CoverCropGeometry）
│   ├── Bookshelf/                  # 书架管理
│   ├── Reading/                    # 阅读记录/统计
│   ├── WeRead/                     # 同步页/导入页/登录/Skill 配置/同步历史
│   ├── Scanner/                    # 条码扫描
│   ├── Settings/                   # 设置/数据维护/备份/导入导出/日志查看
│   └── Components/                 # 共享 UI 组件
└── PersonalLibraryApp.swift        # App 入口 + 数据迁移 + 自动同步触发
```

## 构建与运行

### 环境要求

- macOS 14+ / Xcode 15+
- iOS 17+ (模拟器或真机)

### 步骤

> 需要先安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

```bash
# 1. 克隆仓库
git clone https://github.com/jykojin/PersonalLibrary.git
cd PersonalLibrary/PersonalLibrary

# 2. 配置签名（首次必做）
#    复制示例配置，填入你自己的 Apple Developer Team ID 和 Bundle ID
cp Config.xcconfig.example Config.xcconfig
#    然后编辑 Config.xcconfig：
#      DEVELOPMENT_TEAM = 你的 Team ID（Xcode → Settings → Accounts 可查）
#      PRODUCT_BUNDLE_IDENTIFIER = com.yourname.PersonalLibrary
#    （Config.xcconfig 已被 .gitignore 排除，不会提交）

# 3. 生成 Xcode 项目（.xcodeproj 是生成产物，不在仓库中）
xcodegen generate

# 4. 构建（模拟器）
xcodebuild -scheme PersonalLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/PersonalLibrary-DerivedData build

# 5. 运行测试
xcodebuild -scheme PersonalLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/PersonalLibrary-DerivedData test
```

生成后可直接用 Xcode 打开 `PersonalLibrary.xcodeproj`。

## 版本管理

- 版本号在 `project.yml` 的 `MARKETING_VERSION`
- `Info.plist` 用 `$(MARKETING_VERSION)` 占位，xcodegen 自动注入
- App 设置页底部 "关于" 显示当前版本号
- 每次 push tag 前需保持三处一致（详见 `CLAUDE.md`）

## 测试

Swift Testing 框架，291+ 测试覆盖：

- 数据模型与枚举逻辑
- 微信读书 Web/Skill 双源同步
- 增量同步去重与字段保护
- 取消传播与并发控制
- ISBN 多源查询解析
- 豆瓣限速器（DoubanRateLimiter）
- Excel XLSX 导入导出（含字段往返）
- 数据维护工具（繁转简、分隔符规范化）
- 封面裁剪几何（坐标映射、朝向烘焙、90° 旋转、限尺寸解码）
- 容错启动（容器创建失败降级内存兜底）
- 安全测试（SSRF 含数值 IP 编码、CSV 公式注入、HTTP 头注入、pixel-bomb、路径遍历）

## 安全设计

- Cookie / API Key 存于 iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- WeRead API 请求参数格式校验
- XLSX 导入限 10MB
- WKWebView 用非持久化 DataStore
- 无硬编码密钥
- 全局豆瓣速率限制器防 IP 封禁
- 封面下载 SSRF 防护：仅 https + 阻断内网/本地/IPv6 ULA + 数值 IP 编码规范化校验
- 封面字节限尺寸解码（≤2048px）防 pixel-bomb OOM
- 下载请求头 sanitize（剥离 CRLF）防 HTTP 头注入
- 数据导出对 `=+-@` 开头字段转义，防 CSV/公式注入
- 启动容器创建失败降级内存安全模式（不闪退），提示用户备份/重试

## 配置

微信读书功能可二选一，均在 app 内完成，无需额外配置：
- **Web 扫码登录**：内置 WKWebView 扫码登录微信读书，Cookie 存 Keychain
- **Skill API**：在 app 内输入 Skill API Key

## License

[MIT](LICENSE) © 2026 jykojin
