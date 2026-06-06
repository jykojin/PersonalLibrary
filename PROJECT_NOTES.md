# 私人图书馆 — 项目纪要 / 工程记忆

> 本文是面向开发者（及 AI 协作）的**知识沉淀**：当前功能全景、架构、关键设计决策与踩坑、版本演进。
> 与其它文档分工：`README.md` 对外介绍、`SETUP.md` 建工程步骤、`CLAUDE.md` 协作纪律与权限。**本文不重复这些，只记"为什么这么做 / 坑在哪"。**
> 最后更新：v0.81（main @ 提交 e96df1c）。

---

## 1. 项目定位与核心需求

iOS 个人藏书管理 + 阅读进度跟踪 App。SwiftUI + SwiftData，iOS 17+，UI 全中文。

核心诉求（从需求与历史归纳）：
- **录入省事**：扫码 ISBN / 手动 / Excel 批量导入 / **从微信读书同步**。
- **信息齐全**：自动从 Open Library、Google Books、豆瓣/Goodreads 补全（出版社、页数、定价、出版日期、书籍简介、作者简介、封面）。
- **微信读书深度集成**：同步书架、阅读进度/时长、状态、**划线/笔记**，并能**增量**同步（少请求、少发热）。
- **数据自主**：本地 SwiftData（可选 iCloud/CloudKit），支持导出（TSV/XLSX）和整库备份/恢复。
- **流畅**：大书库（数千本）下列表滚动、详情打开、输入都不能卡。

---

## 2. 功能模块全景（当前已落地）

| 模块 | 关键文件 | 说明 |
|---|---|---|
| 藏书管理 | `Views/Books/*` | 列表(`BookListView`)、详情(`BookDetailView`)、增/改、高级搜索、筛选、批量操作(评分/标签/书架/归档) |
| 书架 | `Views/Bookshelf/`, `Models/Bookshelf` | 卡片式 Dashboard，书数排除已归档 |
| 阅读记录/统计 | `Views/Reading/*`, `Models/ReadingRecord` | 记录阅读会话；详情页"阅读时间线"(加入→开始→累计时长→读完)；统计 Dashboard(分段图表，懒加载) |
| 扫码 | `Views/Scanner/BarcodeScannerView` | 摄像头扫 ISBN |
| ISBN/资料补全 | `ISBNLookupService`, `DoubanDescriptionFetcher` | Open Library + Google Books；`smartFill` 对用户导入书(CB_)补豆瓣/Goodreads 简介 |
| 封面抓取 | `CoverFetchService`, `CoverImageProcessor` | 豆瓣/OpenLibrary 多源；限流；**统一压缩略图**(见踩坑) |
| 微信读书同步 | `WeReadDataSource`(协议) + `WeReadSkillProvider`(Skill) + `WeReadService`(Web) + `WeReadSyncService`(编排) | 双模式；增量同步；同步历史；自动同步 |
| 导入导出/备份 | `ExcelImportExportService`, `BackupService`, `Views/Settings/*` | XLSX 导入(CoreXLSX)、TSV 导出；整库备份到 iCloud Drive + 恢复 |
| 存储 | `StorageManager`, `Models/*` | SwiftData 容器(本地/iCloud)；一次性数据迁移 |
| 日志/诊断 | `AppLogger`, `FileLogger`, `SystemMetrics`, `LogViewerView` | 统一日志 + 轮转 + 运行时开关(verbose/normal/off) + 导出 |
| 认证 | `WeChatAuthManager`, `AuthService`, `KeychainService` | 微信 OAuth；凭证存 Keychain |

数据模型（`Schema`，6 个 `@Model`）：`Book`、`Bookshelf`、`Tag`、`ReadingRecord`、`ImportRecord`、`SyncHistoryRecord`。

---

## 3. 架构与数据流

- **SwiftUI + SwiftData（MVVM-lite）**：视图用 `@Query` 直接读、`@Environment(\.modelContext)` 写。
- `PersonalLibraryApp` 持有共享 `ModelContainer`（`StorageManager.createModelContainer()`，配置名 `"PersonalLibrary"`，本地 `cloudKitDatabase: .none` / iCloud `.automatic`），注入环境。
- **微信读书双模式**：统一协议 `WeReadDataSource`；`WeReadConnectionMode`(web/skill)，**默认 Skill**。
  - Skill：经 Agent Gateway `https://i.weread.qq.com/api/agent/gateway`，`Authorization: Bearer wrk-...`，Key 存 Keychain。
  - Web：扫码登录 Cookie。
- **同步编排**：`WeReadSyncService`(actor) — 全局锁防并发、进度静态属性供 UI 轮询、可外部取消、写同步历史。后台 `ModelContext` 批处理，`autosaveEnabled=false`。

---

## 4. 关键设计决策与踩坑（最重要，务必先读）

### 4.1 封面绝不能"大图内联"进 SwiftData ⚠️
- `@Attribute(.externalStorage)` 只对**超过 ~128KB** 的 blob 才外置；封面平均才 ~49KB → **全部内联进 Book 行**。
- 后果（真实事故）：库膨胀到 **196MB（其中封面 139MB）**，列表 `@Query` 把全部书 fault 进内存 → RSS 达 **435MB**；主线程 `modelContext.save()` 要 bridge 这些大对象 → **卡顿 + 看门狗崩溃(0x8BADF00D) + 磁盘写入告警 + jetsam**。
- 对策（v0.79）：
  - `CoverImageProcessor.thumbnailData(from:)` 在**所有图片入口**统一压成 ≤400px JPEG（3 个下载器 `CoverFetchService.downloadImage`/`downloadWithReferer`/`BookService.downloadImage` + 相册选择）。
  - `Book.hasCoverData`：**<1KB 视为无封面**（历史写过 38 字节坏占位），使其重抓自愈。
  - `StorageManager.migrateOversizedCoversIfNeeded`：启动后台分批把存量超大/坏封面压缩（每批独立 context 控内存）。结果：封面 139MB→75MB，最大单图 1426KB→81KB。
  - **新增任何写 `book.coverImageData` 的地方，必须经 `CoverImageProcessor`。**

### 4.2 主线程 `modelContext.save()` 是性能炸弹 ⚠️
- 主 context 被列表 `@Query` 注册了全部书；`save()` 会遍历/bridge 所有已注册对象。库越大越慢。
- 详情页"打开有备注的书就卡"根因：`onAppear` 设 `notesText` 触发 `onChange` → 在主线程存一次盘（即使没改）。
- 对策（v0.79）：备注保存 = **没真改就不存** + 用**后台 `ModelContext(container)` 按 `persistentModelID` 写**（新 context 只挂 1 个对象，快且不阻塞主线程）。**所有频繁/大数据写操作都应走后台 context，不要在主线程 save 大上下文。**

### 4.3 微信读书字段坑 ⚠️
- `noteCount` = **划线/高亮条数**（`/book/bookmarklist` 可导出内容）；`bookmarkCount` = **书签**（阅读位置，不导出）。
- 增量同步签名**用 `noteCount`**：`Book.wereadBookmarkCount` 存上次同步的 noteCount，每次 sync 先拉 `/user/notebooks`（**`lastSort` 游标分页**，`hasMore` 控制）得到每本现值，**只有变化的书才重拉 bookmarklist**。修复了"老书新增划线同步不回来"，并大幅减少请求/发热。

### 4.4 Swift 协议动态派发坑
- 经 `any WeReadDataSource` 调用、希望走 Skill 覆盖实现的方法，**必须声明为协议要求 + 扩展提供默认实现**；只放在扩展里不会动态派发（Web 模式拿默认 nil，Skill 覆盖返回真实数据，如 `fetchNotebookCounts`）。

### 4.5 "加入日期" vs "阅读记录"
- 概念上 **加入日期 ≠ 一条 ReadingRecord**（想读没读的书也有加入日期）。"第一次阅读"对应 `startedReadingDate`。
- 但 WeRead 书 `enrichBook` 里 `addedTime = startReadingTime`（两者重合），所以详情页把"加入"作为**阅读时间线第一行展示**很自然（v0.81，纯展示，不改数据模型）。

### 4.6 网络与安全
- **SSRF 防护**：封面/简介抓取走域名白名单 + 仅 https（覆盖从 og:image 抓到的 URL）。
- **豆瓣限流**：`DoubanRateLimiter`（等待上限 30s，避免陈旧预约卡死）+ 分源延迟日志。
- 批量补全节流：与 WeRead 同步 QPS 对齐（顺序 + 2s 间隔），曾因并发/burst 导致发热，最终回退到稳的方案。

### 4.7 其它约定
- 版本号三处同步（详见 CLAUDE.md）：`project.yml` 的 `MARKETING_VERSION` → `xcodegen generate` → `git tag`。`Info.plist` 用 `$(MARKETING_VERSION)` 占位，勿手改。
- 所有 `#Preview` 用 `inMemory: true` 容器。
- 阅读状态机：unread/idle → reading → finished（或 paused/dropped）；记录阅读会自动更新 `currentPage` 并可能自动转状态。

---

## 5. 设备问题诊断手段（本次排查沉淀，很有用）

真机性能/崩溃问题可**离线**分析，不必盲猜：
- 拉应用沙盒数据：`xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier com.example.PersonalLibrary --source "Library/Application Support/PersonalLibrary.store"`（连 `-wal`/`-shm`）。
- 用 `sqlite3` 直接量字段大小：如 `SELECT SUM(LENGTH(ZCOVERIMAGEDATA))...`，定位是哪类数据撑大了库。
- 拉崩溃/诊断日志：`--domain-type systemCrashLogs --source /`，看 `.ips`：
  - `bug_type 309` + `FRONTBOARD 0x8BADF00D` = **看门狗杀**（主线程超时）；看 triggered thread 栈定位卡点（本次卡在 `SwiftData…performAndWait`）。
  - `bug_type 145` = 磁盘写入过量；`JetsamEvent` = 内存压力（看进程 RSS）。
- 偏好开关存活检测：拉 `Library/Preferences/<bundleid>.plist`，`plutil -p` 查标志位（如迁移完成标志）。
- `xctrace` 看不到设备 ≠ 设备没连；`devicectl` 能 install/copy 即可用上述手段。

---

## 6. 版本演进时间线（按里程碑）

- **起步**：藏书 CRUD、扫码、书架/统计 Dashboard 重构、微信读书同步大修（状态/匹配/书架/性能）、批量评分、安全加固、测试、CI/CD、滚动性能优化（节流封面/防抖/缓存）。
- **v0.5–0.6**：iCloud Drive 整库备份/恢复；作者/出版社维护（多值拆分）；后台同步实时进度；统一同步控制（接管后台同步、单一停止按钮、可取消）；导入完成 UX + 自动开启同步；自动同步（12h）；**同步历史记录**；默认 Skill 模式。
- **v0.7**：README/回顾性 PRD；批量补全性能调优（burst→并发→最终顺序 2s、跳过 Google Books）；豆瓣限流 + 分源延迟日志；系统指标日志（verbose）；设置页显示版本号。
- **v0.71–0.76**：`startedReadingDate` 估算标记持久化 + 一致化；备注防抖(800ms) + 竞态修复；`doubanURL` SSRF 防护；`ModelContext` 移出热循环（内存/发热）；`DoubanRateLimiter` 30s 上限。
- **v0.78**：**微信读书增量划线同步**（`/user/notebooks` 的 noteCount 驱动，只在划线数变化时重拉划线）。
- **v0.79**：**详情页备注卡顿根治 + 封面缩略图化 + 一次性迁移**（库内封面 139MB→75MB，消除看门狗崩溃/内存压力）。
- **v0.80**：上述两功能合并上线。
- **v0.81**：加入日期并入阅读时间线（纯展示）。

---

## 7. 未来扩展点

- iCloud 同步：SwiftData + CloudKit（容器已留 `.automatic` 分支）。
- 书架管理 UI（增/改/删书架）。
- 可选：对迁移后仍有空闲页的 store 做一次性 VACUUM（纯回收磁盘，非性能必需）。
- 封面入口已收敛到 `CoverImageProcessor`，后续若加新来源，复用即可。

## 8. 已知技术债（审计记录，暂不处理）

- **大列表 body 内重算（性能，低优先）**：`AdvancedSearchView.results` 与 `StatisticsView` 的 `totalPagesRead`/`totalMinutesRead` 在 body 求值时过滤/求和全量数据。当前库规模（~2300 本）实测无感（recompute ~16ms），统计主体已做后台缓存。待藏书量上万、出现可感卡顿时，再把 `results` 改为 `@State + onChange` 触发、把两个小计入缓存。属预防性优化（YAGNI），暂不动。
- **enum 中文 rawValue 存库（国际化前置，中风险迁移）**：`BookType`/`ReadingStatus`/`AddSource` 用中文 rawValue（"正在读"/"纸质书"）直接作为 SwiftData 持久化 key。`AddSource` 已有一次兼容补丁（"导入"→"文件导入"）。只要不改字面就不影响运行；一旦要改文案或做多语言，需写数据迁移把存量中文值转为稳定英文 key + 加 `displayName` 显示层。迁移高风险（改错会损坏存量藏书状态），留待真有国际化需求时专项设计。
