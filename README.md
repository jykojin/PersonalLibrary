# PersonalLibrary (私人图书馆)

> iOS 个人图书管理应用，帮助你追踪纸质书、电子书和有声书的收藏和阅读进度。
> 当前版本: **v0.68**

## 功能特性

### 图书管理
- **多类型** — 纸质书 / 电子书 / 有声书
- **多入口添加** — 手动 / 扫码 / Excel 导入 / 微信读书同步
- **扫码录入** — 扫描 ISBN 条形码自动获取书籍信息
- **统一智能补全** — 单本、批量、添加和编辑共用同一能力，按豆瓣 → Goodreads → Open Library 顺序只补空值
- **AI 智能补全** — 普通来源仍有空缺时可继续联网核实；也可单独触发，并生成经来源和内容规则校验的「AI简介」，内容会按图书特点从综合情况、主题与写法、阅读体验、推荐与延伸等方向灵活组织
- **后台连续性** — 添加、编辑和批量补全切到后台时不会主动取消，并使用 iOS 短时后台额度；回到前台可继续，用户仍可明确停止

### 微信读书集成
- **两种连接方式** — Web 扫码登录 / Skill API Key
- **批量导入** — 一键导入微信读书全部书架
- **增量同步** — 自动检查更新，只补全缺失字段
- **AI简介** — 同步时自动为缺失的书生成 AI简介；微信平台书不额外抓取普通网页，用户导入书复用完整补全链
- **进度同步** — 阅读时长、TTS 时长、完成日期、开始日期
- **划线笔记** — 自动同步划线到本地备注
- **同步历史** — 查看每次同步的统计与结果
- **限速保护** — 全局豆瓣 5 秒间隔避免 IP 封禁
- **顺序节流** — 补全按单本顺序处理；普通网页补全每本间隔 2 秒，AI 批量不另加固定等待；stop 按钮可取消

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
- **Excel 导入导出** — XLSX 格式，含微信读书元数据字段；出版日期兼容年/年月/完整日期、点号、斜杠、中文年月日和英文月份等常见格式
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
| 测试 | Swift Testing framework（552 个单元/集成测试 + 3 个 UI 测试） |

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
│   ├── AIConfig.swift              # AI 平台、Endpoint、模型与安全存储配置
│   ├── Enrichment/                 # 统一补全协调器、普通来源与 AI 证据/内容校验
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
  -project PersonalLibrary.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/PersonalLibrary-DerivedData build

# 5. 运行测试
xcodebuild -scheme PersonalLibrary \
  -project PersonalLibrary.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/PersonalLibrary-DerivedData test
```

生成后可直接用 Xcode 打开 `PersonalLibrary.xcodeproj`。本机若还保留历史工程（例如 `PersonalLibrary 2.xcodeproj`），命令行构建和测试必须显式传入上面的 `-project PersonalLibrary.xcodeproj`，避免选中旧工程。

## 版本管理

- 版本号在 `project.yml` 的 `MARKETING_VERSION`
- `Info.plist` 用 `$(MARKETING_VERSION)` 占位，xcodegen 自动注入
- App 设置页底部 "关于" 显示当前版本号
- 每次 push tag 前需保持三处一致（详见 `CLAUDE.md`）

## 测试

Swift Testing 框架，当前共 552 个单元/集成测试和 3 个 UI 测试，0 失败；应用目标行覆盖率 25.04%（8135/32485，2026-09-22 最终全量模拟器测试），覆盖：

- 数据模型与枚举逻辑
- 微信读书 Web/Skill 双源同步
- 增量同步去重与字段保护
- 取消传播与并发控制
- ISBN 多源查询解析
- 豆瓣 → Goodreads → Open Library 顺序、译者提取和串书拒绝
- AI Endpoint、平台请求体、错误分类、证据验证和 AI简介合同
- 单本/批量/微信读书统一补全、取消传播和时间戳策略
- 页面生命周期与 iOS 短时后台执行租约
- 豆瓣限速器（DoubanRateLimiter）
- Excel XLSX 导入导出（含字段往返）
- 数据维护工具（繁转简、分隔符规范化）
- 封面裁剪几何（坐标映射、朝向烘焙、90° 旋转、限尺寸解码）
- 容错启动（容器创建失败降级内存兜底）
- 安全测试（SSRF 含数值 IP 编码、CSV 公式注入、HTTP 头注入、pixel-bomb、路径遍历）

## 安全设计

- 微信读书 Cookie、Skill API Key 和 AI API Key 均存于 iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)；AI Key 绑定平台与 Endpoint，切换目标后必须重新输入
- AI Endpoint 仅允许无内嵌凭据的公网 HTTPS 地址；TLS 连接固定到本次 DNS 校验通过的数值 IP，同时保留原域名做 SNI、证书与 `Host` 校验，重定向逐跳重新解析并只允许同主机、同端口 HTTPS。仅内置平台和联网验证域名可在 VPN 下使用 `198.18.0.0/15` Fake-IP，自定义域名仍严格阻断，避免密钥泄漏
- `Retry-After` 只接受有限数值并限制到 0–10 秒；`NaN`、`Infinity` 等异常值统一回退到 1 秒，避免非法 `Duration` 导致崩溃
- AI 请求同时限制逐字段显示字符、Unicode scalar、UTF-8 字节和最终 HTTP 请求体（256 KB）；响应使用最多 2 MB 的有界内存分块缓冲，超限立即取消并在解码前拒绝，降低异常输入和超大响应的内存风险
- 自定义 Endpoint/模型必须通过结构化联网证据测试后才能启用；AI 事实字段必须逐字段附有效来源，AI简介还需通过身份、基本结构、纯文本、3000 字安全上限和抄袭校验；1000–1100 字只是生成建议，精炼正文不设最低字数；对比与扩展阅读只是可选写作方向，不要求独立结构化字段，也不作为整篇简介的采用闸门
- AI简介保持深度思考：百炼限制思考预算并预留完整 JSON 输出空间；事实或简介遇到模型长度截断会扩大预算重试，瞬时连接中断会自动重试一次
- 正式事实检索和 AI简介使用真正的阶段硬截止；即使底层网络任务不响应取消，调用方也会按 60/600 秒预算返回可重试超时
- 输入含有效 ISBN 时，普通来源和 AI 事实结果都必须提供匹配的来源侧 ISBN 凭据；冲突或缺少凭据时不会直接采用，存在书名时继续执行书名/作者回退
- 普通元数据重定向只允许同主机、同端口的 HTTPS；微信书在 AI 与划线调用前重新检查归档状态，归档记录不会继续外发
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

AI 智能补全在“设置 → 导入导出与 AI → AI 智能补全”中配置。默认平台为百炼，也可选择 OpenAI、DeepSeek、OpenRouter 或自定义 OpenAI 兼容 Endpoint；模型可读取列表选择或手动填写。只有支持联网检索的配置会启用补全，调用会消耗所选平台的 token。

## License

[MIT](LICENSE) © 2026 jykojin
