# 标签去重 + 打标签 UI 统一 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除同名重复标签，并把四处打标签 UI 统一为「输入即过滤已有标签、可点选、创建去重」的行为。

**Architecture:** Part 1 用一个纯函数 `TagMaintenance.mergeDuplicateTags` 合并同名标签，在 App 启动时通过 `UserDefaults` guard 的一次性迁移调用；同时把 `EditBookView` 的 stale `@Query` 检查改走 `BookService.findOrCreateTag`（新鲜 fetch + trim）堵住持续造重复的口子。Part 2 抽一个自持 `@Query` 的 `TagSelectionEditor` 组件，四处宿主接入、各自保留原有提交逻辑。

**Tech Stack:** SwiftUI + SwiftData, Swift Testing（`import Testing`, `@Suite`/`@Test`/`#expect`）, xcodegen。

## Global Constraints

- iOS 部署目标 17.0；SWIFT_VERSION 5.0（见 `project.yml`）。
- UI 文案一律中文（zh-Hans）。
- 测试用 Swift Testing，且在测试文件中必须用 `PersonalLibrary.Tag` 引用模型（避免与 `Testing.Tag` 冲突）。
- 新增 `.swift` 文件在 `PersonalLibrary/` 目录下会被 glob 自动纳入，但必须 `cd PersonalLibrary && xcodegen generate` 重生成 `.xcodeproj` 后才会进 target。
- 每个任务结束跑 build + test 全绿再 commit。
- 不改 Tag 模型、不改 CloudKit 配置、不加常驻合并按钮、不顺手重构相邻代码。
- Build 命令：`xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData build`
- Test 命令：`xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData test`

---

### Task 1: `TagMaintenance.mergeDuplicateTags` 合并函数 + `findOrCreateTag` 加 trim

**Files:**
- Create: `PersonalLibrary/PersonalLibrary/Services/TagMaintenance.swift`
- Modify: `PersonalLibrary/PersonalLibrary/Services/BookService.swift:54-67`（`findOrCreateTag`）
- Test: `PersonalLibrary/PersonalLibraryTests/PersonalLibraryTests.swift`（新增 `@Suite("Tag Maintenance Tests")`）

**Interfaces:**
- Produces:
  - `enum TagMaintenance { @discardableResult static func mergeDuplicateTags(in context: ModelContext) -> Int }` — 合并同名（trim 后）重复标签，保留每组 `createdDate` 最早者作为 canonical，把重复标签上的书重新指向 canonical（去重），删除多余标签并规范化 canonical 名称；返回被删除的标签数。
  - `BookService.findOrCreateTag(name:modelContext:)` 现有签名不变，但内部按 trim 后的名字查找/创建。

- [ ] **Step 1: 先写失败测试**

在 `PersonalLibraryTests.swift` 末尾（文件尾部）追加：

```swift
// MARK: - Tag Maintenance Tests

@Suite("Tag Maintenance Tests")
struct TagMaintenanceTests {

    @Test("合并同名重复标签：只剩一个且所有书都指向保留项")
    func mergesDuplicates() throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let base = Date(timeIntervalSince1970: 1_000_000)
        let t1 = PersonalLibrary.Tag(name: "签名"); t1.createdDate = base
        let t2 = PersonalLibrary.Tag(name: "签名"); t2.createdDate = base.addingTimeInterval(10)
        let t3 = PersonalLibrary.Tag(name: "签名"); t3.createdDate = base.addingTimeInterval(20)
        context.insert(t1); context.insert(t2); context.insert(t3)

        let b1 = Book(title: "书1", author: "A")
        let b2 = Book(title: "书2", author: "B")
        context.insert(b1); context.insert(b2)
        b1.tags = [t2]
        b2.tags = [t3]
        try context.save()

        let removed = TagMaintenance.mergeDuplicateTags(in: context)

        #expect(removed == 2)
        let tags = try context.fetch(FetchDescriptor<PersonalLibrary.Tag>())
        #expect(tags.count == 1)
        #expect(tags.first?.name == "签名")
        #expect(tags.first?.createdDate == base)  // 保留最早创建的
        #expect(b1.tags?.count == 1)
        #expect(b2.tags?.count == 1)
        #expect(b1.tags?.first?.persistentModelID == tags.first?.persistentModelID)
        #expect(b2.tags?.first?.persistentModelID == tags.first?.persistentModelID)
    }

    @Test("带尾随空格的同名标签也被并入并规范化")
    func mergesWhitespaceVariants() throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let base = Date(timeIntervalSince1970: 2_000_000)
        let t1 = PersonalLibrary.Tag(name: "签名"); t1.createdDate = base
        let t2 = PersonalLibrary.Tag(name: "签名 "); t2.createdDate = base.addingTimeInterval(10)
        context.insert(t1); context.insert(t2)
        try context.save()

        let removed = TagMaintenance.mergeDuplicateTags(in: context)

        #expect(removed == 1)
        let tags = try context.fetch(FetchDescriptor<PersonalLibrary.Tag>())
        #expect(tags.count == 1)
        #expect(tags.first?.name == "签名")  // 规范化去掉尾随空格
    }

    @Test("无重复时不改动、返回 0")
    func noDuplicatesReturnsZero() throws {
        let schema = Schema([Book.self, Bookshelf.self, PersonalLibrary.Tag.self, ReadingRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        context.insert(PersonalLibrary.Tag(name: "签名"))
        context.insert(PersonalLibrary.Tag(name: "绝版"))
        try context.save()

        let removed = TagMaintenance.mergeDuplicateTags(in: context)

        #expect(removed == 0)
        let tags = try context.fetch(FetchDescriptor<PersonalLibrary.Tag>())
        #expect(tags.count == 2)
    }
}
```

- [ ] **Step 2: 跑测试确认失败（编译不过 = 预期失败）**

Run: `xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData test`
Expected: 编译失败，`cannot find 'TagMaintenance' in scope`。

- [ ] **Step 3: 创建 `TagMaintenance.swift`**

```swift
import Foundation
import SwiftData

/// 标签维护工具 — 合并同名重复标签。
enum TagMaintenance {

    /// 合并同名（trim 后）重复标签。
    /// 每组保留 `createdDate` 最早者作为 canonical，规范化其名称为 trim 后的形式，
    /// 把重复标签上的书籍重新指向 canonical（去重避免同一本书重复引用），删除多余标签。
    /// - Returns: 被删除（合并掉）的标签数量。
    @discardableResult
    static func mergeDuplicateTags(in context: ModelContext) -> Int {
        guard let allTags = try? context.fetch(FetchDescriptor<Tag>()) else { return 0 }

        // 按 trim 后名字分组
        var groups: [String: [Tag]] = [:]
        for tag in allTags {
            let key = tag.name.trimmingCharacters(in: .whitespaces)
            groups[key, default: []].append(tag)
        }

        var removed = 0
        for (trimmedName, tags) in groups {
            // 组内按创建时间升序，最早的作为 canonical
            let sorted = tags.sorted { $0.createdDate < $1.createdDate }
            guard let canonical = sorted.first else { continue }

            // 规范化 canonical 名称（去掉可能的尾随/前导空格）
            if canonical.name != trimmedName {
                canonical.name = trimmedName
            }

            // 组内只有一个就无需合并
            guard sorted.count > 1 else { continue }

            for dup in sorted.dropFirst() {
                for book in dup.books ?? [] {
                    var bookTags = book.tags ?? []
                    bookTags.removeAll { $0.persistentModelID == dup.persistentModelID }
                    if !bookTags.contains(where: { $0.persistentModelID == canonical.persistentModelID }) {
                        bookTags.append(canonical)
                    }
                    book.tags = bookTags
                }
                context.delete(dup)
                removed += 1
            }
        }

        if removed > 0 {
            try? context.save()
        }
        return removed
    }
}
```

- [ ] **Step 4: 给 `findOrCreateTag` 加 trim**

修改 `BookService.swift:54-67`，把整段替换为：

```swift
    /// 查找或创建标签（供 WeReadService / WeReadSyncService 等共用）
    /// 按 trim 后的名字查找/创建，避免「签名」与「签名 」被当作两个标签。
    static func findOrCreateTag(name: String, modelContext: ModelContext) throws -> Tag {
        let tagName = name.trimmingCharacters(in: .whitespaces)
        var descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.name == tagName }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let tag = Tag(name: tagName)
        modelContext.insert(tag)
        return tag
    }
```

- [ ] **Step 5: 重生成工程并跑测试确认通过**

Run:
```bash
cd PersonalLibrary && xcodegen generate && cd ..
xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData test
```
Expected: `Tag Maintenance Tests` 三个用例全 PASS，其余测试不回归。

- [ ] **Step 6: Commit**

```bash
git add PersonalLibrary/PersonalLibrary/Services/TagMaintenance.swift \
        PersonalLibrary/PersonalLibrary/Services/BookService.swift \
        PersonalLibrary/PersonalLibraryTests/PersonalLibraryTests.swift \
        PersonalLibrary/PersonalLibrary.xcodeproj
git commit -m "feat: 新增 TagMaintenance 合并同名重复标签 + findOrCreateTag 加 trim"
```

---

### Task 2: 启动时一次性合并迁移

**Files:**
- Modify: `PersonalLibrary/PersonalLibrary/PersonalLibraryApp.swift`（`body` 的 `.task` 第 25 行 + 新增私有方法，仿 `migrateWeReadBookshelf`）

**Interfaces:**
- Consumes: `TagMaintenance.mergeDuplicateTags(in:)`（Task 1）。

- [ ] **Step 1: 新增迁移方法**

在 `PersonalLibraryApp.swift` 中，`migrateWeReadBookshelf()` 方法（结束于第 119 行 `}`）之后、`triggerAutoSyncIfNeeded()` 之前，插入：

```swift
    /// 一次性迁移：合并同名重复标签（历史遗留 + 早期 CloudKit 合并产生的重复）
    @MainActor
    private func mergeDuplicateTags() {
        let migrationKey = "tag_dedup_migration_v1_done"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let removed = TagMaintenance.mergeDuplicateTags(in: modelContainer.mainContext)
        if removed > 0 {
            AppLogger.info("已合并 \(removed) 个重复标签", category: "Migration")
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
```

- [ ] **Step 2: 在启动 `.task` 里调用**

把 `body` 中这一行（第 25 行）：

```swift
                .task { if startupError == nil { migrateOldAddSource(); migrateWeReadBookshelf() } }
```

改为：

```swift
                .task { if startupError == nil { migrateOldAddSource(); migrateWeReadBookshelf(); mergeDuplicateTags() } }
```

- [ ] **Step 3: build 确认通过**

Run: `xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData build`
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: Commit**

```bash
git add PersonalLibrary/PersonalLibrary/PersonalLibraryApp.swift
git commit -m "feat: App 启动时一次性合并同名重复标签"
```

---

### Task 3: `TagSelectionEditor` 共享组件

**Files:**
- Create: `PersonalLibrary/PersonalLibrary/Views/Components/TagSelectionEditor.swift`

**Interfaces:**
- Consumes: `TagChip`、`FlowLayout`（均在 `AddBookView.swift` 中已定义，同 target 可直接引用）。
- Produces: `struct TagSelectionEditor: View { init(selectedTags: Binding<Set<String>>) }` — 自持 `@Query(sort: \Tag.name) allTags`；渲染「已选 chips + 搜索框 + 匹配结果/创建按钮」；不做持久化，只改 `selectedTags` 绑定。宿主需把它放进一个 `Section`。

- [ ] **Step 1: 创建组件文件**

```swift
import SwiftUI
import SwiftData

/// 统一的标签选择编辑器：输入即过滤已有标签、可点选加入、无匹配时创建。
/// 只维护 `selectedTags`（标签名集合），不做持久化 —— 由宿主提交。
/// 使用方式：放进宿主的一个 Section 里，例如 `Section("标签") { TagSelectionEditor(selectedTags: $selectedTags) }`。
struct TagSelectionEditor: View {
    @Binding var selectedTags: Set<String>
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var searchText = ""

    var body: some View {
        // 已选标签
        if !selectedTags.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(Array(selectedTags).sorted(), id: \.self) { tagName in
                    TagChip(name: tagName, isSelected: true) {
                        selectedTags.remove(tagName)
                    }
                }
            }
            .padding(.vertical, 4)
        }

        // 搜索框
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索或创建标签", text: $searchText)
        }

        // 搜索结果 / 创建按钮
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let matched = allTags.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                && !selectedTags.contains($0.name)
            }
            if matched.isEmpty {
                Button {
                    selectedTags.insert(trimmed)
                    searchText = ""
                } label: {
                    Label("创建「\(trimmed)」", systemImage: "plus.circle")
                }
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(matched) { tag in
                        TagChip(name: tag.name, isSelected: false) {
                            selectedTags.insert(tag.name)
                            searchText = ""
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
```

- [ ] **Step 2: 重生成工程并 build 确认通过**

Run:
```bash
cd PersonalLibrary && xcodegen generate && cd ..
xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData build
```
Expected: BUILD SUCCEEDED（此时组件尚未被使用，仅确认可编译）。

- [ ] **Step 3: Commit**

```bash
git add PersonalLibrary/PersonalLibrary/Views/Components/TagSelectionEditor.swift \
        PersonalLibrary/PersonalLibrary.xcodeproj
git commit -m "feat: 新增 TagSelectionEditor 共享标签编辑组件"
```

---

### Task 4: AddBookView 接入 TagSelectionEditor（移除旧 alert 路径）

**Files:**
- Modify: `PersonalLibrary/PersonalLibrary/Views/Books/AddBookView.swift`（标签 Section 212-264；状态 47-49；alert 298-302；`createNewTag` 505-514）

**Interfaces:**
- Consumes: `TagSelectionEditor`（Task 3）。

- [ ] **Step 1: 替换标签 Section**

把 `AddBookView.swift` 第 212-264 行整段（`// MARK: - 标签` 到该 Section 的闭合 `}`）替换为：

```swift
                // MARK: - 标签
                Section("标签") {
                    TagSelectionEditor(selectedTags: $selectedTags)
                }
```

- [ ] **Step 2: 删除不再需要的状态与 alert**

删除第 47-49 行的：

```swift
    @State private var showingNewTag = false
    @State private var newTagName = ""
    @State private var tagSearchText = ""
```

删除第 298-302 行的：

```swift
            .alert("新标签", isPresented: $showingNewTag) {
                TextField("标签名称", text: $newTagName)
                Button("取消", role: .cancel) { newTagName = "" }
                Button("添加") { createNewTag() }
            }
```

- [ ] **Step 3: 删除 `createNewTag` 方法**

删除第 505-514 行的 `// MARK: - Tag Creation` 与 `createNewTag()` 方法整段（`TagChip` 结构体保留）。

- [ ] **Step 4: build 确认通过**

Run: `xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData build`
Expected: BUILD SUCCEEDED，无 `showingNewTag`/`newTagName`/`tagSearchText`/`createNewTag` 未使用或未定义报错。

- [ ] **Step 5: Commit**

```bash
git add PersonalLibrary/PersonalLibrary/Views/Books/AddBookView.swift
git commit -m "refactor: AddBookView 改用 TagSelectionEditor"
```

---

### Task 5: EditBookView 接入 + 提交走 findOrCreateTag

**Files:**
- Modify: `PersonalLibrary/PersonalLibrary/Views/Books/EditBookView.swift`（标签区 325-385；`newTagName` 状态 39；保存逻辑 798-809）

**Interfaces:**
- Consumes: `TagSelectionEditor`（Task 3）、`BookService.findOrCreateTag`（Task 1）。

- [ ] **Step 1: 替换标签编辑区**

把 `EditBookView.swift` 第 325-385 行（`// 已选标签` 起到 `// 已有标签快捷选择` 的 `DisclosureGroup` 闭合）整段替换为：

```swift
            // 标签
            TagSelectionEditor(selectedTags: $selectedTags)
```

保留其上方的书架 `Picker`（318-323 行）。

- [ ] **Step 2: 删除不再使用的 `newTagName` 状态**

删除第 39 行：

```swift
    @State private var newTagName: String = ""
```

- [ ] **Step 3: 保存逻辑改走 findOrCreateTag**

把 `saveChanges` 中第 798-809 行的更新标签段替换为：

```swift
        // 更新标签（走 findOrCreateTag：新鲜 fetch + trim，避免 stale @Query 造重复）
        var bookTags: [Tag] = []
        for tagName in selectedTags {
            if let tag = try? BookService.findOrCreateTag(name: tagName, modelContext: modelContext) {
                bookTags.append(tag)
            }
        }
        book.tags = bookTags
```

- [ ] **Step 4: build 确认通过**

Run: `xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData build`
Expected: BUILD SUCCEEDED，无 `newTagName` 未定义/未使用报错。

- [ ] **Step 5: Commit**

```bash
git add PersonalLibrary/PersonalLibrary/Views/Books/EditBookView.swift
git commit -m "refactor: EditBookView 改用 TagSelectionEditor 并走 findOrCreateTag 提交"
```

---

### Task 6: QuickTagView（右滑快速打标签）接入 + 加取消

**Files:**
- Modify: `PersonalLibrary/PersonalLibrary/Views/Books/BookListView.swift`（`QuickTagView` 1159-1236）

**Interfaces:**
- Consumes: `TagSelectionEditor`（Task 3）、`BookService.findOrCreateTag`（Task 1）。

- [ ] **Step 1: 重写 QuickTagView**

把 `BookListView.swift` 第 1159-1236 行整个 `struct QuickTagView` 替换为：

```swift
struct QuickTagView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var book: Book
    @State private var selectedTags: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("标签") {
                    TagSelectionEditor(selectedTags: $selectedTags)
                }
            }
            .navigationTitle("为「\(book.title)」打标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { commit() }
                }
            }
            .onAppear {
                selectedTags = Set((book.tags ?? []).map(\.name))
            }
        }
    }

    private func commit() {
        var bookTags: [Tag] = []
        for tagName in selectedTags {
            if let tag = try? BookService.findOrCreateTag(name: tagName, modelContext: modelContext) {
                bookTags.append(tag)
            }
        }
        book.tags = bookTags
        try? modelContext.save()
        dismiss()
    }
}
```

- [ ] **Step 2: build 确认通过**

Run: `xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData build`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: Commit**

```bash
git add PersonalLibrary/PersonalLibrary/Views/Books/BookListView.swift
git commit -m "refactor: QuickTagView 改用 TagSelectionEditor 并新增取消按钮"
```

---

### Task 7: BatchTagView（批量打标签）接入

**Files:**
- Modify: `PersonalLibrary/PersonalLibrary/Views/Books/BookListView.swift`（`BatchTagView` 797-911）

**Interfaces:**
- Consumes: `TagSelectionEditor`（Task 3）。
- 保留现有 `applyTags()` 后台 context 增量提交逻辑（868-910 行不变）。

- [ ] **Step 1: 替换 body 与删除 addNewTag**

把 `BatchTagView` 的 `body`（806-854 行）与 `addNewTag()`（856-866 行）替换为下面的 `body`（`addNewTag` 整个删除，`applyTags` 868-910 行保持不变）：

```swift
    var body: some View {
        NavigationStack {
            Form {
                Section("标签") {
                    TagSelectionEditor(selectedTags: $selectedTags)
                }
            }
            .navigationTitle("为 \(books.count) 本书打标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        applyTags()
                    }
                    .disabled(selectedTags.isEmpty)
                }
            }
        }
    }
```

- [ ] **Step 2: 删除不再使用的状态与 @Query**

删除 `BatchTagView` 第 804 行：

```swift
    @State private var newTagName = ""
```

以及第 800 行（`applyTags` 不再引用 `existingTags`，它在后台 context 自己 fetch）：

```swift
    @Query private var existingTags: [Tag]
```

- [ ] **Step 3: build 确认通过**

Run: `xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData build`
Expected: BUILD SUCCEEDED，无 `newTagName`/`existingTags` 未使用报错。

- [ ] **Step 4: 全量 test 确认不回归**

Run: `xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData test`
Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add PersonalLibrary/PersonalLibrary/Views/Books/BookListView.swift
git commit -m "refactor: BatchTagView 改用 TagSelectionEditor"
```

---

### Task 8: 设备走查（UI 一致性 + 去重验证）

**Files:** 无代码改动，纯手动验证。

- [ ] **Step 1: 装到模拟器/真机跑一遍**

Run: `xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData build` 后在模拟器运行，或按 SETUP 走真机。

- [ ] **Step 2: 逐项核对**

  - 启动后进 `设置 → 数据维护 → 标签`，确认原本多个「签名」已合并为一个。
  - 右滑一本书 → 「标签」：搜索框输入即过滤已有标签，可点选；输入不存在的名字显示「创建「X」」；有「取消」和「完成」。
  - 添加新书页「标签」区：行为同上。
  - 编辑书籍页「标签」区：行为同上；保存后不产生重复标签。
  - 多选 → 批量「标签」：行为同上；确定后标签增量生效、无重复。

- [ ] **Step 3: 无代码改动，无需 commit。若发现问题回到对应任务修复。**

---

## Self-Review

**1. Spec coverage:**
- Part 1-A 启动一次性合并 → Task 1（函数）+ Task 2（迁移接入）✓
- Part 1-B 集中创建防重复：`findOrCreateTag` trim → Task 1；`EditBookView` 走 findOrCreateTag → Task 5 ✓
- Part 2 统一编辑器 → Task 3（组件）+ Task 4/5/6/7（四处接入）✓
- 测试/成功标准 → Task 1（单测 RED-GREEN）+ Task 8（设备走查）✓
- 范围红线：无任务触碰 Tag 模型/CloudKit/常驻按钮/Excel cache（除 trim）✓

**2. Placeholder scan:** 无 TBD/TODO；每个改代码步骤都给了完整代码。✓

**3. Type consistency:**
- `TagMaintenance.mergeDuplicateTags(in:) -> Int` — Task 1 定义，Task 2 调用，签名一致。✓
- `BookService.findOrCreateTag(name:modelContext:)` — Task 1 改内部实现，Task 5/6 调用，签名不变。✓
- `TagSelectionEditor(selectedTags: Binding<Set<String>>)` — Task 3 定义，Task 4/5/6/7 以 `$selectedTags` 传入，类型一致（各宿主的 `selectedTags` 均为 `@State Set<String>`）。✓
- `TagChip` / `FlowLayout` — 复用 `AddBookView.swift` 既有定义，Task 4 明确保留 `TagChip`。✓
