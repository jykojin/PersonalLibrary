# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**私人图书馆 (PersonalLibrary)** — iOS app for personal book collection management and reading progress tracking. Built with SwiftUI + SwiftData, targeting iOS 17+.

## Build & Run

Requires Xcode (not just Command Line Tools). See `PersonalLibrary/SETUP.md` for initial Xcode project creation steps.

```bash
# Regenerate Xcode project (after changing project.yml)
cd PersonalLibrary && xcodegen generate

# Build
xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData build

# Run tests
xcodebuild -scheme PersonalLibrary -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/PersonalLibrary-DerivedData test
```

## Architecture

**Pattern:** SwiftUI + SwiftData (MVVM-lite — views query data directly via `@Query`)

- **Models** (`Models/`): SwiftData `@Model` classes — `Book`, `ReadingRecord`, `Bookshelf`, `Tag`
- **Views** (`Views/`): SwiftUI views organized by feature (Books, Reading, Scanner, Settings)
- **Services** (`Services/`): `ISBNLookupService` (Open Library + Google Books), `ExcelImportExportService` (XLSX import, TSV export), `BookService`

**Data flow:** `PersonalLibraryApp` creates a shared `ModelContainer` → views use `@Query` to read and `@Environment(\.modelContext)` to write. No external database — SwiftData persists to the app sandbox automatically.

**Key conventions:**
- UI text is in Chinese (zh-Hans)
- `ReadingStatus` enum drives book state transitions: unread → reading → finished (or paused)
- Recording a reading session auto-updates `book.currentPage` and may auto-transition status
- All `#Preview` blocks use `inMemory: true` containers

## Dependencies

- **CoreXLSX** (SPM) — XLSX file parsing for book import

## Development Discipline (Karpathy Rules)

每次写代码前 **必须** 过以下检查，不通过不准动手：

### 动手前（每个需求）— 不输出以下内容就禁止写任何代码

1. **复述需求** — 用自己的话说"我理解你要的是 X"，等用户确认或纠正
2. **方案概述** — 列出要改哪几个文件、大概怎么改（2-5 行足够），让用户看到再动手
3. **最小范围** — 明确说"本次只做 A，不做 B/C"。如果能 50 行解决就不写 200 行
4. **成功标准** — "做完后我会通过 X 命令/操作来验证"

⚠️ 规则：在用户说"确认/好/可以"之前，不准打开任何文件编辑。"需求很简单不用确认"是不成立的理由。

### 写代码时

4. **只改必须改的** — 每一行改动都能追溯到用户的请求。不顺手重构、不改邻近代码风格
5. **不重复** — 新写一个函数前先 grep 有没有现成的。有就复用
6. **不预测未来** — 没被要求的 configurability、flexibility、edge case 防御一律不加

### 交付前

7. **build + test 必须通过**（`xcodebuild build` + `xcodebuild test`）
8. **diff 自审** — 跑 `git diff` 检查有没有越界改动，有就回滚
9. **设备验证**（如果改了 UI / 功能流程）— 在模拟器或真机上走一遍完整路径

### 违反时怎么办

如果发现自己要做超出范围的事（如重复代码提取、预防性错误处理、改进相邻代码），**先说出来让用户决定**，不要静默地做。

## Future Expansion Points

- iCloud sync via SwiftData CloudKit integration
- Bookshelf management UI (create/edit/delete bookshelves)
