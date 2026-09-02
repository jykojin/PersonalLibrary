# 私人图书馆 — 项目纪要 / 工程记忆

> 本文是面向开发者（及 AI 协作）的**知识沉淀**：当前功能全景、架构、关键设计决策与踩坑、版本演进。
> 与其它文档分工：`README.md` 对外介绍、`SETUP.md` 建工程步骤、`CLAUDE.md` 协作纪律与权限。**本文不重复这些，只记"为什么这么做 / 坑在哪"。**
> 最后更新：v0.63（git 最新 tag）。注：下方第 6 节里程碑沿用旧的开发编号（tag 序列曾重排，见 commit 7f7183e），与实际 tag 号不对应，仅作功能演进参考。

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

> 另有一套**不在 App 里**的离线工具：`tools/ai_intro/` + `.claude/skills/ai-book-intro/`，
> 用来批量重写「AI介绍」字段。见第 10 节。

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

### 4.7 「一次性结果」不能承载「持续筛选范围」⚠️

- 症状（v0.60 修）：高级搜索勾「已取消收藏的书」拿到结果后，在首页搜索框输入文字，**已归档的书一本也搜不出来**。
- 根因：范围只靠一次性的 `advancedSearchResults: [Book]?` 表达，而 `recomputeFilteredBooks` 的每个分支都无条件 `filter { !$0.isArchived }`。`onChange(of: searchText)` 清掉该数组后，范围**静默退回「未归档」**，于是输入文字变成在未归档集合里匹配。
- 对策：范围提升为持续状态 `@State archivedScope`（由 `AdvancedSearchView` 回调一并传回）；`searchText` 变化只丢弃一次性结果、**保留范围**；切书架才视为离开。
- **通则：凡是"视图当前在看哪个集合"这类语义，必须用独立的状态变量表达，不能用某次查询的结果数组兼任** —— 结果数组会被各种 `onChange` 正常清理，范围却会跟着一起丢。
- 附带教训（同一 bug 的第二层）：条幅原先只在 `advancedSearchResults != nil` 时显示，一输入文字就消失 → 用户既看不出当前范围、也没有退出出口。**特殊范围态必须常驻可见且可退出。**
- 排查方法论沉淀：先用 Core Data 变更日志（`ACHANGE.ZCOLUMNS` 位图 ↔ `ZBOOK` 列序）确认**写入侧无辜**（`isArchived` 写入事件数与归档书数 1:1、`ZBOOK` 零 delete），再回头查读取侧，避免了在写入路径上白挖。多代备份横比（归档数只增不减）也是有效的排除手段。

### 4.8 去重判定必须带 `bookType` 维度 ⚠️

- 症状（v0.60 修）：库里已有某 ISBN 的**电子书**（微信读书导入）时，扫同一本书的**纸质版**被判「ISBN 重复」，直接 `return`，纸质书加不进去。
- 根因：`ISBNDuplicateChecker.findExisting` 只比 ISBN、不看载体。而"实体书 + 微信读书电子版都收"是常态用法 —— 库里实测已有 **69 组**同 ISBN 跨载体并存，全是经 Excel 导入/微信读书同步进来的，**唯独扫码这条路被堵死**。
- 讽刺的是 `WeReadSyncService.findExistingBook` 早就按 `bookType` 区分并注明「防止电子书和纸质书混淆」—— **同一个语义在两条路径上实现不一致**，同步路径想到了，扫码路径没有。
- 对策：`findExisting` 增可选 `bookType`（默认 `nil` 保持旧行为），只有"同 ISBN + 同载体"才算重复；新增 `findOtherEditions` 用于"你已有电子书版"的温和提示（**放行不拦截**）。
- **通则：ISBN 在本库不是唯一键，`(isbn, bookType)` 才是。** 新增任何按 ISBN 查重/匹配的逻辑，先问一句"跨载体怎么办"。
- ⚠️ **该改动引入过一次更严重的回归（v0.60 → v0.62 修）**：原实现有两条路径（先 `#Predicate` 精确匹配走数据库、覆盖全库；未命中再用 `fetchLimit = 500` 捞取做归一化兜底）。合并成 `matchingBooks` 时只保留了带 500 上限的那条 → 真实库 2742 本带 ISBN 的书里，**位次靠后的 ~82% 扫码一律判"不重复"**，已存在的书被重复添加。
  - **通则一：查重/匹配必须下推到数据库 `predicate`，不能"捞一批到内存再过滤"。** 任何 `fetchLimit` 都不该决定正确性——它只该用于分页/性能，绝不能用在判定路径上。
  - **通则二：删除一条看似冗余的分支前，先证明它冗余。** 当时提交信息写的"结果不变"是错的：两条路径的**覆盖范围不同**（一条全库、一条前 500）。
  - **通则三：小数据量测试测不出上限类 bug。** 原有测试只插 1–2 本书，永远碰不到 500 边界。已补 `ISBNDuplicateLargeLibraryTests`（填充 2800 本 ≈ 真实规模、目标书放最末）。**凡是代码里出现常量上限，测试就必须造出超过该上限的数据。**
- **同 ISBN 不等于同一本书**：套书各卷常共用一个 ISBN（实测：张居正第二/三/四卷同 ISBN、曾国藩 1/2/3 同 ISBN、余罪单册与全集同 ISBN）。**任何"按 ISBN 清理重复"的脚本都必须连书名一起比，否则会误删不同卷。**

### 4.9 筛选条件叠加会把要找的东西藏起来

- 归档视图（已取消收藏）**忽略** `paperOnly` 纸质书筛选。原因：归档里电子书占多数（实测 15 电子 / 10 纸质），而该视图的用途是"找回某一本具体的书"，按载体预筛只会让用户以为书丢了（真实案例：《惊呆了！哲学这么好》是电子书，开着纸质书筛选就永远看不到）。
- **通则：回收站/找回类视图，少叠加隐式筛选。** 若坚持叠加，必须在 UI 上显式说明"N 本被隐藏"，否则就是静默丢结果。

### 4.10 全局静态状态的测试要用纯函数

- `syncLockPreventsDoubleTrigger` 断言全局 `WeReadSyncService.isSyncing == false`，在并行全量跑时随机失败：Swift Testing 的 `.serialized` **只保证 suite 内串行，suite 之间仍并行**，别的 suite 正在 `sync()` 持锁时该断言就翻（碰这把锁的 8 个 suite 里它是唯一没加 `.serialized` 的）。而且它并未真正验证判定逻辑，只是读了个环境值。
- 对策：照 `shouldAutoSync` 的既有做法抽纯函数 `shouldProceed(isSyncing:skipLockCheck:)`，**并让 `sync()` 的实际 guard 走它** —— 保证被测的就是生产用的判定，而不是一个平行实现。
- **通则：测判定逻辑就抽纯函数 + 显式入参；断言全局可变状态的环境值必然 flaky。**
- 后续复查（v0.63）纠正了上面的归因：**真正的隐患不是那把同步锁** —— 20 处 `sync()` 里 19 处传了 `skipLockCheck: true`，压根不碰锁。跨 suite 污染源实际是两个：
  - **`AppLogger.currentMode`**（UserDefaults 支撑的进程级全局）：3 个用例改全局模式 + 断言共享 `FileLogger` 的**整文件内容**。改模式会非确定性影响并行 suite 的日志行为；`.verbose` 期间并行 suite 涌出 perf/debug，叠加 2MB 轮转可能把断言要找的 marker 挤出文件。→ 抽 `shouldLog(level:mode:)` / `shouldLogPerf(mode:)`，`log()`/`perf()` 的 guard 走它们，用例改为纯函数真值表。
  - **`syncWithoutLogin`**：唯一不传 `skipLockCheck` 的调用，且删共享 Keychain 的 `wereadCookieKey`。→ 给已有的 `MockWeReadDataSource` 加可配置 `connected`，用"未连接的 mock"表达未登录，不碰 Keychain 与锁。
- **通则：判断 flaky 根因时，先统计"到底哪些调用真的碰了那个全局态"，别凭 `.serialized` 标记推断。** 标记的存在往往只说明有人怀疑过，不代表它是真凶（这里 7 个 suite 的标记都不是必需的）。
- **通则：UserDefaults 支撑的属性就是进程级全局态**，测试改它等于改整个测试进程的行为，`.serialized` 无法约束（该 trait 只管 suite 内）。

### 4.11 其它约定
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

> 以下按实际 tag 号（tag 序列已于 commit 7f7183e 重排对齐）：

- **v0.57**：数据备份导出改为真正的 XLSX（Objects2XLSX）。
- **v0.58**：标签去重（启动一次性合并同名标签）+ 四处打标签 UI 统一为 `TagSelectionEditor`。
- **v0.59**：**首页搜索保留「已取消收藏」范围**（见 4.7）。
- **v0.60**：**扫码添加不再被同 ISBN 的其它载体拦住**（见 4.8）+ 归档视图忽略纸质书筛选（见 4.9）+ 同步锁测试 flaky 修复（见 4.10）。
- **v0.61**：归档视图找回已取消收藏的电子书（`7f2ed34`，见 4.9）。
- **v0.62**：修复大库下查重漏比 —— `fetchLimit=500` 让 2742 本里位次靠后的约 82% 不参与比对（`5bb722a`，见 4.8）。
- **v0.63**：备份恢复不再丢 WAL 里未 checkpoint 的改动（`d483691`）；消除生产/测试双份筛选逻辑；CI 干净 checkout 修复（`0c3531b`）。
- **v0.64**：**「AI介绍」字段 + 一次性回填 2853 条**（`343b671`）—— 详情页展示、编辑页可改、Excel 第 32 列（AF）；真机实测 2853 条全命中。详见第 9 节 v0.64 小节。
- **v0.65**：数据备份页新增「**导入 AI介绍**」（`03e115b`）—— 可按 xlsx 批量回填已有书籍，只补空值、绝不新增书。
- **v0.66**：**豆瓣简介只抓到折叠版的 bug**（`97379e0`）—— 删掉重复解析器，正文不再被截断在约 400 字（见 9.2）。
- **v0.67**：**「从备份恢复」「从 Excel 导入」点了没反应的 bug** —— 三个 `.fileImporter` 挂在同一个 `List` 上，SwiftUI 只让最后一个生效（见第 9 节第 9 行）。同轮完成 **AI介绍 全量重写 2897 条**（工具链见 `.claude/skills/ai-book-intro/` 与 `tools/ai_intro/`）。

---

## 7. 未来扩展点

- iCloud 同步：SwiftData + CloudKit（容器已留 `.automatic` 分支）。
- 书架管理 UI（增/改/删书架）。
- 可选：对迁移后仍有空闲页的 store 做一次性 VACUUM（纯回收磁盘，非性能必需）。
- 封面入口已收敛到 `CoverImageProcessor`，后续若加新来源，复用即可。

## 8. 已知技术债（审计记录，暂不处理）

- **大列表 body 内重算（性能，低优先）**：`AdvancedSearchView.results` 与 `StatisticsView` 的 `totalPagesRead`/`totalMinutesRead` 在 body 求值时过滤/求和全量数据。当前库规模（~2300 本）实测无感（recompute ~16ms），统计主体已做后台缓存。待藏书量上万、出现可感卡顿时，再把 `results` 改为 `@State + onChange` 触发、把两个小计入缓存。属预防性优化（YAGNI），暂不动。
- **enum 中文 rawValue 存库（国际化前置，中风险迁移）**：`BookType`/`ReadingStatus`/`AddSource` 用中文 rawValue（"正在读"/"纸质书"）直接作为 SwiftData 持久化 key。`AddSource` 已有一次兼容补丁（"导入"→"文件导入"）。只要不改字面就不影响运行；一旦要改文案或做多语言，需写数据迁移把存量中文值转为稳定英文 key + 加 `displayName` 显示层。迁移高风险（改错会损坏存量藏书状态），留待真有国际化需求时专项设计。

---

## 9. 修复追踪表（v0.59–v0.67，2026-08-09 ~ 09-01）

一轮集中排查修掉的 6 个问题。每行给出 **症状 → 版本 → commit → 根因 → 防护测试**，
细节见第 4 节对应小节。查历史时从这张表入手，比翻 git log 快。

| # | 症状（用户可见） | 版本 | commit | 根因一句话 | 防护测试 | 详情 |
|---|---|---|---|---|---|---|
| 1 | 高级搜索勾「已取消收藏」后，一在首页输入文字就一本都搜不到 | v0.59 | `6a7bbb6` | 范围只靠一次性结果数组承载，`onChange(of: searchText)` 清掉它时范围一起丢 | `BookListFilterArchivedScopeTests` | 4.7 |
| 2 | 已有电子书时扫同一本书的纸质版，被判「ISBN 重复」加不进去 | v0.60 | `bab432a` | 去重只比 ISBN、不看 `bookType`（库里实测 69 组同 ISBN 跨载体并存） | `ISBNDuplicateCrossTypeTests` | 4.8 |
| 3 | 已取消收藏的电子书在归档视图里看不到（以为书丢了） | v0.61 | `7f2ed34` | `paperOnly` 在归档视图仍生效，而归档里电子书占多数（15 电子/10 纸质） | `BookListFilterArchivedScopeTests` | 4.9 |
| 4 | **已存在的书又被重复添加**（《我已经没有烦恼了》）| v0.62 | `5bb722a` | ⚠️ #2 的回归：合并查重分支时只留下带 `fetchLimit=500` 的那条，2742 本里位次靠后的 ~82% 不参与比对 | `ISBNDuplicateLargeLibraryTests`（填充 2800 本、目标放最末） | 4.8 |
| 5 | 从备份恢复后，最近的改动没了 | v0.63 | `d483691` | 备份写出了 `.plbackup-wal`，恢复却从不读回 → WAL 里未 checkpoint 的改动静默丢失 | `BackupWALSidecarTests` | — |
| 6 | 全量测试偶发失败（非用户可见） | v0.60 / v0.63 | `0880221` `4b03a8e` | 测试断言/改写进程级全局态（`isSyncing`、`AppLogger.currentMode`、共享 Keychain），`.serialized` 只管 suite 内 | `SyncLockDecisionTests`、`AppLoggerLevelDecisionTests` | 4.10 |
| 7 | 导出的书单里空字段全都显示成 `"34"`（ISBN／总页数／微信读书ID 等） | v0.64 | — | ⚠️ **误报，App 无 bug**：App 写出的是真正的空串 `<si><t></t></si>`；那份 xlsx 被外部工具改写时，把空串换成了它自己的 sharedString 索引号 —— 31 列布局下空串正好落在索引 34，于是显示 "34" | `空字段往返后仍为空`、`批量导出时空字段依然全空` | 9.1 |
| 8 | **书籍简介/作者简介被截断**，尾部是 `...` 加一行 `(展开全部)` | v0.66 | `97379e0` | 两套豆瓣解析器不一致：`ISBNLookupService` 取「内容简介」后第一个 `<div class="intro">`，而豆瓣把它放在 `<span class="short">` 里（约 400 字折叠版）；正确的 `DoubanDescriptionFetcher` 优先取 `<span class="all hidden">`。完整正文本就在同一份 HTML 里 | `DoubanCollapsedIntroTests` | 9.2 |
| 9 | **数据备份页「从备份恢复」「从 Excel 导入」点了完全没反应**（「导入 AI介绍」正常）| v0.67 | `8647239` | 三个 `.fileImporter` 全挂在同一个 `List` 上，SwiftUI 只让**最后一个**生效，前两个静默失效。判据很干净：「从 Excel 导入」用的是完全合法的 `.xlsx` 类型也照样弹不出来 → 问题在挂载位置与顺序，不在 `allowedContentTypes`。修法是三个 importer 各自挂到对应的 Button 上 | `testDataBackupFilePickersAllPresent`（UI 测试，已验证在修复前失败、修复后通过）| 9.3 |

同轮的工程改进（非用户可见 bug）：

- **`d483691`** 消除生产/测试双份筛选逻辑：`BookListFilter.apply`/`matches` 原先只有测试在调用，生产 `BookListView` 用自己的一套 —— 测试全绿也不保证生产正确。现已统一走同一批判定函数。
- **`0c3531b`** CI 自 2026-05-25 起失败并被手动禁用，查出**两个独立故障**：① GitHub 账单/额度（job 压根没启动，需在 Billing & plans 处理，代码改不了）；② `Config.xcconfig` 被 gitignore 排除，干净 checkout 上 `xcodegen` 直接失败 —— **这个坑同时影响任何 fork 本项目的人**。已修 ②，并加 `paths-ignore`/tag 限定/`concurrency`/`workflow_dispatch` 降低 macOS runner（10× 计费）消耗。

### v0.64 新增功能（非 bug 修复，2026-08-13）

`343b671` **「AI介绍」字段 + 一次性回填**。用户在 App 外为每本书整理了一段结构化介绍，
放在旧导出 xlsx 的最后一列（AF）。

- `Book.bookIntroduction`（optional → SwiftData 轻量迁移，`Schema` 未改，无 migration plan）
- 详情页只读展示（复用 `descriptionSection`），编辑页「描述」区可编辑
- 随包资源 `Resources/BookIntroductionSeed.json`（2853 条 / 3.33 MB）+ `BookIntroductionSeeder`：
  首启按 **微信读书ID → ISBN → 书名+作者** 顺序匹配，命中多本就都写，**只补空值、绝不新增书**，
  `UserDefaults` 键 `book_introduction_seed_v1_done` 保证只跑一次
- **真机实测**：`seed 2853 条，更新 2854 本，未匹配 0 条`（更新数 > 条数是因为一对重复书共用同一 ISBN 键）
- Excel 第 32 列（AF）表头为「AI介绍」，导入端保留旧表头「书籍介绍」兜底，
  否则 0.64 之前导出的文件会静默丢这一列

### v0.65 新增功能（非 bug 修复，2026-08-13）

`03e115b` **数据备份页「导入 AI介绍」**。v0.64 的 seed 只在首启跑一次，之后新加的书
没有补 AI介绍 的路径：启动回填被 `UserDefaults` 键锁死，而「从 Excel 导入」走的是
`insert` 新建书，拿它导会造出一堆重复书。故补一个只回填、不新增的入口。

- `ExcelImportExportService.parseIntroductionEntries(data:/from:)`：只读
  书名/作者/ISBN/微信读书ID/AI介绍 五列（复用 `buildColumnMap`/`getCellValue`），
  兼容旧表头「书籍介绍」；介绍为空或一个匹配键都没有的行跳过；CRLF 归一为 LF
- 匹配与写入直接交给已有的 `BookIntroductionSeeder.backfill` —— 匹配顺序与
  「只补空值、绝不新增书」的语义**一行未重写**
- 结果同时进弹窗（文件 X 条 / 更新 Y 本 / 未匹配 Z 条）与 `AppLogger`（category `IntroImport`）
- 使用流程：导出书单 → 在 Excel 的 AI介绍 列填新书 → 导入 AI介绍

### 9.1 「34」误报的排查经过（别再挖第二遍）

现象：用户那份 `书单导出_20260812_含书籍介绍.xlsx` 里，所有空字段读出来都是字符串 `"34"`
（127 行的 ISBN、2328 行的微信读书ID 等）。最初误判为 `XLSXWriter`／Objects2XLSX 写空串的 bug。

**结论：不是 App 产生的。** 判据（按 TDD 先写复现测试 → 没复现 → 再 dump 原始 XML 对证）：

| | 空单元格指向的 sharedString |
|---|---|
| 当场新导出（32 列） | `[35] <si><t></t></si>` ← 真正的空串 |
| 用户那份（31 列） | `[34] <si><t>34</t></si>` ← 文本就是 "34" |

31 列布局下空串落在索引 34，加一列后后移到 35 —— 索引与假值完全对应，说明是**导出之后**
某个改写工具把空串替换成了自身索引；该文件 `docProps` 显示最后由 Microsoft Excel for Mac
于 2026-08-12 16:32Z 保存。

**真实规模复验**（2853 本 × 32 列，9755 条 sharedString）：解析条数 == 声明 `uniqueCount`；
「文本 == 自身索引」的条目 **0 条**；空串以唯一一条空文本正确存在；17 个本该全空的列 × 2853 行
出现的非空值 **0 个**。

**复现手法**（以后要再验就照这个来）：写个临时 `@Suite` 调 `exportBooks` 把 xlsx 落到 `/tmp`，
再用 python 解 `xl/sharedStrings.xml`（注意 `<si/>` 自闭合标签也要计入，否则索引整体错位，
我第一次就是这么误判的）+ `xl/worksheets/sheet1.xml`，检查上面三个特征。

seed 生成脚本已把 `"34"` 当空值过滤，所以那些假 ISBN／假微信读书ID 没有进入匹配逻辑。

### 9.2 折叠版简介的判据与一次重置事故（2026-08-14）

**判据**：豆瓣 `内容简介` 区块同时下发两份正文 —— `<span class="short">` 里是约 400 字的
折叠版（末尾 `(展开全部)` 锚点在 `<div class="intro">` **内部**，剥标签后成为正文的一行），
`<span class="all hidden">` 里是完整版。抓错节点的症状：简介长度集中在 391–406 字且尾部带该标记。
2026-08-12 的导出快照里 47 条图书简介 + 41 条作者简介命中。

**教训**：这是第二次因"同一件事两套实现"踩坑（第一次见 `d483691` 的筛选逻辑）。
本次直接删掉重复实现、把正确那套提为 `static`，而不是把修复复制第二遍。

**一次重置事故**：`resetEnrichmentForCollapsedIntros()` 最初用 `needs*Refresh` 过滤，
而该判定对**空简介也返回 true**，于是真机上标记了 **344 本**而非预期的约 88 本。
只动了 `lastEnrichmentDate` 时间戳，正文无损，但批量补全要多跑 250+ 本无用请求，
且原时间戳未备份、无法还原。已新增 `Book.hasCollapsedIntro`（只认折叠残留）并补测试锁住区别。
**教训**：一次性迁移的过滤条件要和函数名表达的语义严格对齐，宁窄勿宽 —— 迁移只跑一次，跑错没有第二次机会。

**验证结果（2026-08-15）**：v0.66 装真机后跑批量补全，简介恢复为完整正文，问题闭环。

### 9.3 同一视图挂多个 `.fileImporter` 只有最后一个生效（2026-09-01）

**症状**：数据备份页点「从备份恢复」和「从 Excel 导入」完全没反应 —— 不弹文件选择器、不报错、
无日志。同页的「导入 AI介绍」正常。

**根因**：三个 `.fileImporter` 都挂在同一个 `List` 上（`DataBackupView.swift` 原 `:132/:143/:153`），
SwiftUI 只让最后一个（AI介绍）生效。第三个 importer 是 v0.65 的 `03e115b` 加的 —— 也就是说
**加第三个入口的那次提交，静默弄坏了前两个**，而当时没人点恢复所以没发现。

**判据（这条最省时间）**：「从 Excel 导入」用的是完全合法的 `.xlsx` 类型，照样弹不出来 →
问题在 modifier 的挂载位置与顺序，不在 `allowedContentTypes`。
反过来，两个 `.sheet`（备份分享、导出分享）同层却都正常，所以**不能笼统说"presentation modifier 同层必冲突"**，
`.fileImporter` 是特例。

**修法**：三个 importer 各自挂到对应的 Button 上（不同视图各挂一个即不冲突），
参数与回调逻辑不动，+31/−31。

**防护测试**：`PersonalLibraryUITests.testDataBackupFilePickersAllPresent` —— 依次点三个按钮，
断言系统选择器的「取消／Cancel」出现。**已验证它能抓住这个 bug**：把 `DataBackupView.swift`
还原成 HEAD 版本后测试失败（报「点『从备份恢复』后文件选择器没有出现」），改回修复版即通过。
这是本仓库第一个真正验证过判别力的 UI 测试（此前只有启动 smoke test）。

**顺带留下的一个未验证隐患**：`allowedContentTypes: [UTType(filenameExtension: "plbackup") ?? .data]`
里的 `?? .data` 是**死代码** —— `project.yml` 从未声明 `.plbackup` 类型，而
`UTType(filenameExtension:)` 对未注册扩展名返回动态 UTI（`dyn.*`）而不是 nil，兜底永不触发。
真机实测能正常选中 `.plbackup` 并恢复成功（iOS 把磁盘文件解析成同一个动态 UTI，两边对得上），
所以**当前不影响功能**，未改。若将来选择器出现「文件是灰的选不中」，从这里查。

### 遗留事项（下次接手先看这里）

- [ ] **GitHub 账单未处理** → CI 仍处 `disabled_manually`。修好账单后 `gh workflow enable CI && gh workflow run CI` 验证。
- [ ] **重复数据未清理**：v0.60–v0.62 期间手动扫码添加的书可能有重复（已知《我已经没有烦恼了》）。⚠️ **不要按 ISBN 批量清理** —— 套书各卷共用 ISBN（张居正第二/三/四卷、曾国藩 1/2/3、余罪单册与全集），必须连书名一起比。建议手工删。
- [x] ~~344 本待重抓简介~~ **已完成（2026-08-15）**：v0.66 装机后跑过 数据维护 → 批量补全，用户确认简介已变为完整正文，`(展开全部)` 残留消失。若之后又出现该标记，说明豆瓣页面结构变了，按 9.2 的判据重查。
- [ ] **`BookIntroductionSeed.json`（3.33 MB）回填完成后可删**：真机已确认 2853 条全部落库，该资源只在首启用一次。v0.65 已提供常驻的「导入 AI介绍」入口，删掉 seed 后仍能随时按 xlsx 回填。删除时要连 `BookIntroductionSeeder.seedURL()` 的调用与两条依赖它的测试（`随包 seed 资源存在且可解析`、`用随包真实 seed 回填`）一起处理，否则 CI 会红。
- [ ] **旧表头兜底何时可以去掉**：`ExcelImportExportService.legacyIntroHeader`（「书籍介绍」）只为读 0.64 之前的导出文件而存在，等确认不再需要导入历史文件即可删。
- [ ] `PersonalLibraryUITests` 现有 3 个测试（启动 smoke、添加书流程、v0.67 的文件选择器回归）。「归档范围 + 输入文字」这类交互仍未覆盖，要长期防护还得补。

### 本轮沉淀的排查手法（可复用）

- **先证"写入侧无辜"再查读取侧**：用 Core Data 变更日志定位字段位图（`ACHANGE.ZCOLUMNS` ↔ `PRAGMA table_info(ZBOOK)` 列序），统计某字段的写入事件数与当前行数是否 1:1、有无 delete 记录。问题 #1 靠这招排除了写入路径，没白挖。
- **多代备份横比**：同一字段在几代 `.plbackup` 里的计数趋势（只增/有减）能快速判断是"丢数据"还是"没写进去"。
- **灌真实数据到模拟器走查**：`xcrun simctl get_app_container` 拿沙盒路径 → 覆盖 `PersonalLibrary.store` → 跑 XCUITest 驱动真实 UI。问题 #1 的修复就是这样在 2872 本真实数据上确认的。
- **上限类 bug 必须造超限数据**：问题 #4 躲过旧测试的唯一原因是测试只插 1–2 本书。凡代码里有常量上限，测试数据量就必须越过它。

---

## 10. 内部工具：AI介绍 批量重写管线（2026-08-31 ~ 09-01）

**不是 App 功能**，是一套离线工具，用来把 `Book.bookIntroduction`（Excel 第 32 列「AI介绍」）
从 v0.64 那批模板货全量重写成人写的介绍。App 侧不需要任何改动 —— 成品经
「数据备份 → 从备份恢复」或「导入 AI介绍」进库。

### 构成

| 位置 | 作用 |
|---|---|
| `.claude/skills/ai-book-intro/SKILL.md` | 怎么跑（九步流程、两条轨道、踩过的坑） |
| `.claude/skills/ai-book-intro/PROMPT.md` | **写作契约** —— 唯一的质量标准，含《平面国》标杆样板与反面样板 |
| `.claude/skills/ai-book-intro/AGENT_TASK.md` | 派给单个批次 agent 的任务卡 |
| `tools/ai_intro/pipeline.py` | 九步流水线：`archive`→`clear`→`export-batches`→（生成）→`ingest-text`→`merge`→`write-db`→`checkpoint`→`verify`→`export-xlsx`→`publish` |
| `tools/ai_intro/validate.py` | 纯函数校验器（篇幅、结构、抄袭、占位符、模板句、书名、重复 pk） |
| `tools/ai_intro/test_validate.py` | 57 条测试，两端都锁：标杆样板必须过、真实模板垃圾必须被打回 |

### 本轮结果

2897 / 2904 本（99.8%），字数 625–998、均值 794（标杆样板 694）。7 本联网也查不到，
按契约写成 `[资料不足]` 合法留空。`verify` 通过：只有 `ZBOOKINTRODUCTION` 变了，
`ZBOOKDESCRIPTION`（豆瓣简介）/`ZAUTHORDESCRIPTION`（作者简介）/封面/阅读进度全部 0 行差异。

### 铁律（违反会造成不可逆损失）

- **原始 `.plbackup` 绝不改**，所有操作在 `work.sqlite` 副本上做，`original.sqlite` 留作比对基准。
- **按 `Z_PK` 写回，不要按 ISBN 匹配** —— 套书各卷共用 ISBN（张居正、曾国藩、余罪都是），
  按 ISBN 回填会一条介绍写到多本书上（v0.64 就出现过 2853 条写了 2854 本）。
- **`checkpoint` 不能省**：库是 WAL 模式，不 checkpoint 会留 `-wal` 边车，
  用户只传主文件时改动静默丢失（见第 9 节问题 #5）。
- **只碰 `ZBOOKINTRODUCTION` 一列**，另两个 description 字段是生成用的原料。

### 这轮踩的坑（下次直接看这里）

- **`WORKDIR` 硬编码在 `/tmp`，重启清空 → 丢了 40 批约 1000 段稿件**。
  Mac 死机重启后 `/private/tmp` 被系统清掉，`tmutil` 无快照（/tmp 不在 Time Machine 范围）。
  agent 只回报统计数字、正文从不进上下文（这是对的，否则撑爆编排层），所以**稿件一丢就没有副本**。
  → 跑长批前把 `WORKDIR` 改到持久目录，或每完成约 10 批就 `export-xlsx` + `publish` 存增量。
- **agent 的完工汇报不可信**。多批报「写了 25 段、校验全部合格」而盘上根本没有文件，
  或报 25 段实际 15 段。成因多半是 API 流被截断后 harness 拿到残缺响应，不是故意编造。
  → **编排层每收一次汇报都要核盘**（`grep -c '^### ' text/batch_NNN.txt` 或跑 `merge`），
  不能转述 agent 的自报数字。
- **并发 12 路会集体挂**（同时 stalled + 超时），10 路较稳；19 路必挂。
- **派接手 agent 前先看文件 mtime**：没有完成通知 ≠ 已经死掉。两个 agent 并发 Edit
  同一份稿件会写出重复的 `### pk`，更糟的是用整文件 `Write` 覆盖会冲掉先写方的段落。
  → 接手提示里写死「只用 Edit 追加，绝不整文件 Write」。重复 pk 的检测已在 `2690d62` 补上。
- **subagent 的 toolset 里没有 `WebSearch`**（既不在工具表也不在延迟工具表），
  track B 的联网查证实际全部靠 `mcp__plugin_ecc_exa__web_search_exa`。
  Exa 并行两个查询会撞免费额度限流，**改串行即恢复**；`WebFetch` 打搜索引擎页返回无关内容，不能当回退。
- **最有效的查证入口是 ISBN，不是书名**：多本 `author` 为「未知」的书靠 ISBN 精确命中
  图书馆馆藏，拿到真实编者、出版社、年份甚至完整目录（有目录后写分节最稳）。
- **agent 会估错自己写了多少字**：某批以为在写 85 字/条，实测只有 59–73 字，整段掉到 682–714。
  → 任务卡要求它**用 `len(re.sub(r'\s','',正文))` 量**，而不是凭感觉估；
  并且要讲明「`ingest-text` 说合格只代表过了 600 闸门，不等于到了 700 目标」。

### 顺带查出的库内脏数据（建议人工抽查）

库里的豆瓣简介/作者简介**存在串书**，至少 7 条：`pk 2586`（挂 Nate Silver 的书，
简介却是 Claire Harman 写 Katherine Mansfield 的另一本）、`pk 2420`《盛世》（作者简介是陈冠中，
书籍简介是一部黑帮小说）、`pk 2714`（哈利·波特电子合集混进插画师 Jim Kay 的简介）、
`pk 2754`《一读就上瘾的逻辑学》（简介整段是心理学发展史）、`pk 2769`《范仲淹传》
（`ZAUTHOR` 是邢超、作者简介却是程应镠）、`pk 62`、`pk 1160`。
这几段正文都改按 `title + author + publisher` 三项互证的那本书写、只用可靠公共事实。
另有几处顺带查出的库内错值：`pk 589` 作者应为「沈寂」（库里写「沉寂」）、
`pk 1196` 应为 1985 年学林出版社（库里 year=1999）、`pk 568`《现代汉语词典》
库里 1982 实为印次（初版 1978-12）。

### 续跑/补写的正确姿势

从 iCloud 的成品 `.plbackup` 复制成 `work.sqlite`、原始备份复制成 `original.sqlite`，
**不要再跑 `archive` / `clear`**（会清掉已完成的介绍），直接
`export-batches --only-empty` 重新切批。重新切批后批次号会重排，
旧的 `text/batch_NNN.txt` 会和新的 `in/batch_NNN.json` 对不上 —— 先把旧稿件挪走备份。
