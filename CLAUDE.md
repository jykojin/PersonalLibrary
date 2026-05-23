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

## Future Expansion Points

- iCloud sync via SwiftData CloudKit integration
- Bookshelf management UI (create/edit/delete bookshelves)
