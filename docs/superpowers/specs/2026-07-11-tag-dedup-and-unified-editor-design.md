# 标签去重 + 打标签 UI 统一 — 设计文档

**日期：** 2026-07-11
**状态：** 已批准，待实现
**涉及范围：** 标签（Tag）的创建、去重、以及四处打标签 UI

## 背景与问题

用户报告两个问题：

1. **标签冗余** —— 数据维护里能看到多个同名「签名」标签，实际上一个就够了。
2. **打标签行为不一致** —— 右滑快速打标签是「输入文本 + 添加按钮 + 全量列表」，而添加新书页是「输入即过滤已有标签、可点选、创建去重」。两种交互不一致，且前者容易造重复。

## 根因分析

标签在 6+ 处被创建，存在性检查方式不一致：

| 位置 | 创建方式 | 问题 |
|------|---------|------|
| `BookService.findOrCreateTag` | 先 fetch 再创建 | 安全（但未 trim 名称） |
| `AddBookView.saveBook` | 后台 context fetch + map | 安全 |
| `BatchTagView.applyTags` | 后台 context fetch + map | 安全 |
| `EditBookView.saveChanges` | 查 `@Query allTags` | **stale @Query → 造重复** |
| `QuickTagView.addTag` | 查 `@Query existingTags` | 依赖 @Query（但 toggle 用 persistentModelID，风险较低） |
| `ExcelImportExportService` | fetch 播种 cache | 安全 |
| `DataMaintenanceView.addTag` | 查 `@Query allTags` | 手动新增，风险低 |

造成重复的两股力量：

- **stale `@Query` 检查** —— 后台 context（微信读书同步、批量导入）里插入的标签，视图的 `@Query` 尚未刷新可见，于是又创建一个同名的。这是 `EditBookView` 最可能的造重复路径。
- **CloudKit（`cloudKitDatabase: .automatic`）** —— CloudKit 无法强制唯一约束，跨时间/跨设备同步时同名标签可能落成两行。
- **精确字符串匹配** —— `$0.name == name` 使得 `签名` 与 `签名␣`（带尾随空格）被当作不同标签。

## 方案

### Part 1 — 去重（两个方向）

#### A. 启动时一次性合并（用户已选）

新增纯函数 `TagMaintenance.mergeDuplicateTags(in context: ModelContext) -> Int`：

- 取出所有 `Tag`，按 `name.trimmingCharacters(in: .whitespaces)` 分组
- 每组：保留 `createdDate` 最早的一个作为 canonical，把它的 name 规范化为 trim 后的形式；把所有重复标签上的书籍重新指向 canonical（去重，避免同一本书重复引用）；删除其余重复标签
- 返回被删除（合并掉）的标签数量，供日志使用

在 `PersonalLibraryApp` 中通过 `UserDefaults` guard 的一次性迁移调用（key：`tag_dedup_migration_v1_done`），完全复刻现有 `migrateWeReadBookshelf` 的模式（同样在 `startupError == nil` 时、`.task` 里执行）。

> **已知限制（不在本次修复范围）：** CloudKit 跨设备同步之后仍可能重新产生同名标签，一次性迁移不会再触发。这与用户「自动合并一次」的选择一致，明确记录、不在此修复。

#### B. 阻止今后继续产生重复（集中创建）

- `BookService.findOrCreateTag` 增加名称 trim（查找与创建都用 trim 后的名字）。
- `EditBookView.saveChanges` 当前用 stale 的 `allTags.first(where:)` —— 改为走 `findOrCreateTag`（新鲜 fetch）。**这是真正的持续性 bug 修复。**
- `AddBookView` / `BatchTagView` 的提交逻辑本身已在后台 context 新鲜 fetch，保持不变，仅在收集标签名时做 trim 保持一致。

### Part 2 — 统一打标签编辑器（四处全改）

新增自包含组件 `TagSelectionEditor`：

- **输入：** `@Binding var selectedTags: Set<String>` + `allTags: [Tag]`（宿主传入自己已有的 `@Query`）。组件**不做持久化**，由宿主提交，因此是纯组件、可独立测试。
- **UI（= 今天 AddBook 的行为）：**
  - 顶部：可移除的已选标签 chips
  - 中间：搜索输入框
  - 输入时：按大小写不敏感过滤已有标签（排除已选），以可点选 chips 展示；点选即加入
  - 无匹配时：显示 `创建「X」` 按钮，点击后把 trim 后的名字加入 `selectedTags`
  - 因 `selectedTags` 是 `Set<String>`，加入已存在的名字天然不重复
- 该组件把「创建标签」折叠进搜索框，所以 `AddBookView` 原本独立的「添加新标签」alert（`showingNewTag` / `newTagName` / `createNewTag`）**移除** —— 代码更少、行为单一。

四处接入，各自保留原有提交逻辑：

| 宿主 | selectedTags 初始化 | 提交 |
|------|--------------------|------|
| `AddBookView` | 空 | 现有后台 context save（trim） |
| `EditBookView` | 由 `book.tags` 载入 | 改用 `findOrCreateTag`（替换 stale 检查） |
| `QuickTagView`（右滑） | 由 `book.tags` 载入 | 「完成」时通过 `findOrCreateTag` 提交；新增「取消」按钮 |
| `BatchTagView`（批量） | 空 | 现有后台 context `applyTags`（增量式，trim） |

## 测试 / 成功标准

- **单元测试（TDD, RED-GREEN）：** 内存容器，往若干本书上插入 3 个相同的 `签名` 标签 → 调 `mergeDuplicateTags` → 断言只剩 1 个、且所有书都指向它、返回值为被合并数。再补一个带尾随空格 `签名␣` 的用例断言也被并入。
- **build + test 全绿**（`xcodebuild build` + `xcodebuild test`）。
- **设备走查：** 四处打标签流程的搜索过滤行为完全一致；加已存在标签不产生重复；重启后 `设置→数据维护→标签` 只显示一个 `签名`。

## 范围红线（本次不做）

- 不加常驻的「合并重复标签」按钮（用户选了「启动自动合并一次」）
- 不改 Tag 模型结构
- 不改 CloudKit 配置
- 不改 Excel 导入的 cache 逻辑（除 trim 外）
- 不顺手重构相邻代码
