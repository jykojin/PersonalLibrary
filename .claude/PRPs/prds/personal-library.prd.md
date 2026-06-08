# PersonalLibrary (私人图书馆)

> 注：本 PRD 是**回顾性产品文档** — 基于 v0.83 已实现状态整理而非前瞻规划。问题陈述、用户特征、成功指标都是事后归纳的假设，未经过结构化用户访谈验证。

## Problem Statement

**重度阅读者**（年读 100+ 本、跨纸质/电子/有声三种形态、用微信读书又有大量纸质收藏）缺少一个**统一**追踪藏书与阅读进度的工具。微信读书覆盖不了纸质书，豆瓣读书的"想读/在读/读过"三档状态无法精细化（如"闲置"、"弃读"），市面 app 大多缺少**与微信读书的实时同步**和**多源元数据自动补全**。

## Evidence

- **个人需求驱动** — 作者本人是目标用户，使用微信读书 + 纸质混合阅读模式
- **代码痕迹** — 千本量级的混合藏书真实数据规模来自单一用户使用记录
- **行为信号** — v0.6 → v0.351 间数十次小版本迭代多围绕"同步取消"、"批量补全速度"、"重置状态准确性"等真实使用痛点
- **假设 - 需要验证**: 是否存在足够大的同类用户群体（重度多形态阅读者 + 微信读书重度用户 + 接受 iOS 私有部署）

## Proposed Solution

iOS 原生 app（SwiftUI + SwiftData），承担三类工作：

1. **统一收藏库** — 纸质 / 电子 / 有声三类共用一个数据模型，状态机覆盖 5 档（想读/闲置/正在读/已读/弃读）
2. **微信读书桥接** — 双通道（Web 扫码 + Skill API）拉取书架、进度、划线，增量同步，可手动取消
3. **元数据增强** — 多源 ISBN 查询（豆瓣 → OL → Google → Goodreads）+ 限速保护，把"裸数据"自动补成"完整书目"

选择 SwiftUI + SwiftData 的核心理由是**单设备私有部署 + iCloud 同步**，避开自建后端的运维成本。

## Key Hypothesis

我们相信**多源自动补全 + 微信读书双向同步 + 5 档阅读状态**会让**重度多形态阅读者**少花时间在"录入与维护"，多花时间在"阅读与回顾"。

成功的衡量：
- 添加一本新书的中位手动输入字段数 ≤ 2（书名 + ISBN/扫码）
- 微信读书已有书的本地导入零干预
- 用户每周至少打开一次 app（不只是同步）

## What We're NOT Building

- **后端服务** — 不做账号系统、不做云端书库；用户数据存本地 + iCloud
- **社交功能** — 不做评论、关注、动态流；这是个人工具
- **跨平台 web/Android 版本** — 仅 iOS；用 SwiftData 锁定生态
- **DRM 内容播放** — 不读电子书内容（PDF/EPUB），只管理元数据
- **手动标记电子书阅读进度** — 全靠微信读书同步，不接受脱离 WeRead 的手动维护
- **图书推荐 / 算法发现** — 用户自己决定读什么
- **微信账号登录体系** — 不做账号/OAuth；v0.83 已移除未完成的微信登录入口，数据归属设备本地 + iCloud

## Success Metrics

| Metric | Target | How Measured |
|--------|--------|--------------|
| 新书录入完整度 | ≥ 95% 字段填齐（书名/作者/出版社/页数/封面） | 抽样 100 本扫码或同步导入的书 |
| 同步成功率 | ≥ 99%（已连接状态下的同步任务最终完成或正确取消） | SyncHistoryRecord 的 errorMessage 占比 |
| 取消响应时间 | 用户点 Stop 后 ≤ 5 秒实际停止 | 手动测试 + 日志验证 |
| 批量补全 1500 本耗时 | ≤ 2 小时（充电+亮屏+并发 3） | 实测 |
| 单本书智能补全 | 95% 在 10 秒内返回 | 日志统计 smartFill latency |

## Open Questions

- [ ] 是否扩展给非 WeRead 用户使用？（当前架构紧耦合 WeRead）
- [ ] 是否支持手动维护电子书进度（脱离 WeRead）？
- [ ] 是否提供数据导出标准格式（JSON/Calibre OPDS）以便迁移？
- [ ] 后台任务（BGProcessingTask）是否值得加 — 当前结论是 ROI 太低

---

## Users & Context

### Primary User

- **Who**: 30-50 岁的重度阅读者，年读 100+ 本，跨纸质/电子/有声三类
- **Current behavior**:
  - 微信读书 + Kindle + 纸质三栈并行
  - 用 Excel/Notion 试过维护书单，体验差
  - 想看自己年度阅读统计但没工具
- **Trigger**: 买了一本新书 / 读完一本想标记 / 想知道"过去 3 个月读了什么"
- **Success state**: 一个 App 内能看到所有藏书、所有阅读历史、所有进度

### Job to Be Done

> When 我读完一本书 / 添加一本新书 / 想回顾过去阅读，我想要在一个统一的 app 里**最少手动输入**地完成记录、统计、回顾，so I can 把时间花在阅读本身而不是数据维护。

### Non-Users

- **轻度读者**（年读 < 10 本）— 用豆瓣记录就够，不需要这种重武器
- **纯电子书用户**（仅 Kindle / 微信读书）— 微信读书 app 自身够用
- **不接受私有部署的用户** — 没有云端账号，跨设备只走 iCloud
- **想要社交分享的用户** — 没有 feed、没有评论

### Constraints

- 单人维护，开发资源有限
- iOS-only（无服务器，无运维预算）
- 微信读书 API 是逆向接口，可能随时改变
- 豆瓣/Goodreads 反爬政策不可控

---

## Solution Detail

### Core Capabilities (MoSCoW)

| Priority | Capability | Rationale |
|----------|------------|-----------|
| Must | 三类书统一数据模型 + 5 档状态机 | 核心数据结构 |
| Must | 微信读书 Web/Skill 双通道同步 | 解决最大痛点 |
| Must | 多源 ISBN 智能补全 | 减少手动输入 |
| Must | Excel 批量导入 | 老用户从 Excel/Notion 迁移 |
| Must | 数据库备份恢复 | 数据安全底线 |
| Must | 取消支持的并发批量任务 | 大规模操作必备 |
| Should | 阅读统计图表 | 提供回顾价值 |
| Should | 高级搜索 + 标签管理 | 大库后必需 |
| Should | iCloud 多设备同步 | 跨 iPhone/iPad 体验 |
| Could | 同步历史 / 应用日志查看 | 排查工具 |
| Could | 数据维护（繁转简、分隔符规范化） | 长尾清理工具 |
| Won't | 后端账号系统 | 增加运维负担 |
| Won't | Android/Web 客户端 | 单人维护不可持续 |
| Won't | 电子书内容阅读 | 避开 DRM 复杂度 |

### MVP Scope

> 已经超出 MVP，目前是 **v0.83** 的稳定版

最小验证版（已发布）：
- 单本书添加 + 编辑
- 扫码识别
- 微信读书一次性导入
- 阅读记录与状态变更
- iCloud 备份

### User Flow

**典型新书录入路径**:
```
打开 app → 扫码 → ISBN → ISBNLookupService.smartFill() → 自动填齐 → 用户选 (1) 评分 (2) 书架 → 保存
```
中位手动操作 ≤ 5 次点击。

**典型微信读书同步路径**:
```
打开 app → (auto trigger if > 12h) → fetchAllBooks → diff against local → 每本 enrichBook + 划线 → 写入历史
```
零用户干预（除了首次配置连接方式）。

---

## Technical Approach

**Feasibility**: 已实现（v0.83 已发布）

### Architecture Notes

- **SwiftUI + SwiftData** — 选择苹果原生栈，零自定义后端
- **Actor isolation** — `ISBNLookupService` / `WeReadSyncService` / `DoubanRateLimiter` 用 actor 保证线程安全
- **TaskGroup 并发** — 批量任务用 `withTaskGroup` 限制并发数（一般 3）
- **withTaskCancellationHandler** — 跨 detached task 桥接取消
- **per-task ModelContext** — 每个并发任务用独立 context 避免 SwiftData 线程不安全
- **Per-source rate limiter** — 全局 `DoubanRateLimiter` actor，5 秒间隔
- **xcodegen + project.yml** — 项目文件不手写，避免 .pbxproj 合并冲突

### Technical Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| 微信读书 API 变化 | 高 | 双通道（Web/Skill），一个挂掉切另一个 |
| 豆瓣反爬升级 | 中 | DoubanRateLimiter 全局 5s 间隔 + UA 伪装 |
| SwiftData 迁移 | 中 | 所有字段有默认值，Lightweight migration |
| iCloud 同步冲突 | 低 | SwiftData 自带 last-write-wins |
| 后台任务 iOS 限制 | 已知 | 不依赖后台，前台亮屏跑 |

---

## Implementation Phases

> 注：以下阶段是已完成的回顾，不是规划。

| # | Phase | Description | Status |
|---|-------|-------------|--------|
| 1 | 核心数据模型 | Book/Tag/Bookshelf/ReadingRecord 模型 + SwiftData 迁移 | complete |
| 2 | 基础 CRUD UI | 列表/详情/编辑/添加视图 | complete |
| 3 | 扫码 + ISBN 多源查询 | BarcodeScannerView + ISBNLookupService | complete |
| 4 | Excel 导入导出 | ExcelImportExportService | complete |
| 5 | 阅读记录与统计 | ReadingRecord + StatisticsView 图表 | complete |
| 6 | 微信读书同步 v1 | WeReadService + Cookie 登录 + 一次性导入 | complete |
| 7 | 微信读书同步 v2 | 增量同步 + 进度/划线 + 取消支持 + Skill API | complete |
| 8 | 数据维护工具 | 作者/出版社/标签管理 + 批量补全 + 繁转简 | complete |
| 9 | 数据安全 | Keychain + 备份恢复 + iCloud | complete |
| 10 | 性能优化 | DoubanRateLimiter + 并发 3 批量补全 | complete |
| 11 | 版本管理 | 设置页显示版本号 + project.yml 占位 | complete |
| 12 | 封面缩略图化 | CoverImageProcessor 统一压缩（≤800px），根治库膨胀/卡顿 | complete (v0.79) |
| 13 | 封面体验 | 内置浏览器搜图（WKWebView 长按取图）+ 裁剪编辑器（缩放/裁剪/90° 旋转） | complete (v0.82) |
| 14 | 安全加固 | SSRF（含数值 IP）/ CSV 注入 / HTTP 头注入 / pixel-bomb 防护 + 全量审计 | complete (v0.82) |
| 15 | 健壮性与精简 | 容器创建失败容错启动（不闪退）+ 移除未完成的微信账号登录 | complete (v0.83) |

### Future Phases (TBD)

| # | Phase | Description | Status |
|---|-------|-------------|--------|
| 16 | 后台任务 | BGProcessingTask 充电时唤醒补全 | deferred (low ROI) |
| 17 | 数据导出标准格式 | JSON / Calibre OPDS | pending |
| 18 | 阅读时间深度分析 | 按时段、按类别拆解 | pending |
| 19 | 大库性能 / 国际化 | body 重算优化、enum 中文 rawValue 迁移（见 PROJECT_NOTES 技术债） | pending |

---

## Decisions Log

| Decision | Choice | Alternatives | Rationale |
|----------|--------|--------------|-----------|
| 后端架构 | 无后端，仅本地 + iCloud | Firebase / 自建 | 单人维护，避免运维 |
| UI 栈 | SwiftUI | UIKit | 现代代码、SwiftData 原生集成 |
| 数据持久化 | SwiftData | Core Data / Realm | 苹果官方、Swift 原生、未来兼容性 |
| 项目文件管理 | XcodeGen | 直接 commit .pbxproj | 避免合并冲突 |
| 微信读书接入 | Web Cookie + Skill API 双通道 | 仅 Web | Skill API 更稳定，Web 是兜底 |
| 元数据补全策略 | 串联多源 + 限速器 | 并行多源 | 串联减少不必要请求；限速保命 |
| 批量任务并发数 | 3 | 1 / 5 | 平衡速度与封禁风险 |
| 取消机制 | withTaskCancellationHandler 桥接 detached | 共享变量 + isCancelled 轮询 | 标准 Swift 并发模式 |
| 版本号管理 | project.yml MARKETING_VERSION 单源 | 散在多处 | xcodegen 自动注入 Info.plist |
| 封面搜图实现 | 内置浏览器 WKWebView 长按取图 | 自己抓 URL 拼九宫格 | 相关性交给搜索引擎，规避防盗链与排序难题 |
| 封面下载安全 | 域名/数值IP 规范化校验 + 限尺寸解码 | 仅 hasSuffix 白名单 | 防后缀冒充 SSRF 与 pixel-bomb OOM |
| 微信账号登录 | 移除（保留微信读书 cookie 同步） | 做完 OAuth + 自建后端 | 功能未完成、与本地工具定位不符，同步已由 iCloud + 微信读书覆盖 |
| 启动失败处理 | 降级内存安全模式 + 提示 | fatalError 闪退 | 不让用户误以为数据丢失，给备份/重试出路 |

---

## Research Summary

### Market Context

- **微信读书 app 自身**: 不管理纸质书，无导出
- **豆瓣读书**: 三档状态太粗，无微信读书同步
- **Notion / Excel**: 灵活但完全手动
- **Goodreads**: 国内无支付，中文书少
- **私家书藏 / Bookrack**: iOS 上有同类，但元数据补全和 WeRead 集成弱

### Technical Context

- SwiftUI + SwiftData 是苹果在 iOS 17+ 的官方推荐栈
- Swift Concurrency (actor / TaskGroup / async let) 已经是大型 app 的事实标准
- 豆瓣 / OpenLibrary / Google Books / Goodreads 都有可用的开放接口或可解析页面
- iOS 后台任务能力非常受限，不适合长任务批处理

---

*Generated: 2026-05-30 (retrospective)，更新至 v0.83 (2026-06-06)*
*Status: REFLECTIVE - documenting v0.83 as built, not pre-build planning*
