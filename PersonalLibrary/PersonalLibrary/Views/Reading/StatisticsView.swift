import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @Query private var records: [ReadingRecord]
    @Query(sort: \Bookshelf.sortOrder) private var bookshelves: [Bookshelf]

    @State private var cachedStats: CachedStatistics?
    @State private var selectedTab: StatsTab = .overview

    enum StatsTab: String, CaseIterable {
        case overview = "概览"
        case trends = "趋势"
        case distribution = "分布"
    }

    /// 按书籍类型分组的状态统计
    struct TypeStatusStats {
        let total: Int
        let reading: Int
        let finished: Int
        let wishlist: Int
        let dropped: Int
        let idle: Int
    }

    /// 书架统计条目
    struct BookshelfStats: Identifiable {
        let id: String
        let name: String
        let total: Int
        let finished: Int
        let reading: Int
        let paperCount: Int
        let ebookCount: Int
        let audiobookCount: Int
    }

    /// 缓存的统计数据结构
    private struct CachedStatistics {
        let bookCount: Int
        let totalBooks: Int
        let booksRead: Int
        let booksReading: Int
        let booksWishlist: Int
        let booksDropped: Int
        let booksIdle: Int
        let paperCount: Int
        let ebookCount: Int
        let audiobookCount: Int
        let paperStats: TypeStatusStats
        let ebookStats: TypeStatusStats
        let audiobookStats: TypeStatusStats
        let ratedBooks: [(rating: Int, count: Int)]
        let averageRating: Double
        let monthlyFinished: [(month: String, count: Int)]
        let yearlyAdded: [(year: String, count: Int)]
        let monthlyAdded: [(month: String, count: Int)]
        let topTags: [(name: String, count: Int)]
        let bookshelfStats: [BookshelfStats]
        let manualCount: Int
        let scannedCount: Int
        let importedCount: Int
    }

    private var stats: CachedStatistics {
        cachedStats ?? computeStats()
    }

    // MARK: - 基础统计

    private var totalBooks: Int { stats.totalBooks }
    private var booksRead: Int { stats.booksRead }
    private var booksReading: Int { stats.booksReading }
    private var booksWishlist: Int { stats.booksWishlist }
    private var booksDropped: Int { stats.booksDropped }
    private var booksIdle: Int { stats.booksIdle }

    private var totalPagesRead: Int { records.reduce(0) { $0 + $1.pagesRead } }
    private var totalMinutesRead: Int { records.reduce(0) { $0 + $1.durationMinutes } }

    private var paperCount: Int { stats.paperCount }
    private var ebookCount: Int { stats.ebookCount }
    private var audiobookCount: Int { stats.audiobookCount }

    private var ratedBooks: [(rating: Int, count: Int)] { stats.ratedBooks }
    private var ratedBooksTotal: Int { stats.ratedBooks.reduce(0) { $0 + $1.count } }
    private var averageRating: Double { stats.averageRating }
    private var monthlyFinished: [(month: String, count: Int)] { stats.monthlyFinished }
    private var yearlyAdded: [(year: String, count: Int)] { stats.yearlyAdded }
    private var topTags: [(name: String, count: Int)] { stats.topTags }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroSection
                    tabPicker
                    tabContent
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("阅读统计")
            .onAppear { cachedStats = computeStats() }
            .onChange(of: books.count) { _, _ in cachedStats = computeStats() }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        HStack(spacing: 0) {
            heroItem(value: "\(totalBooks)", label: "总藏书", color: .blue)
            heroDivider
            heroItem(value: "\(booksRead)", label: "已读完", color: .green)
            heroDivider
            heroItem(value: "\(booksReading)", label: "在读中", color: .orange)
        }
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.systemGray6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func heroItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 0.5, height: 40)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(StatsTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .trends:
            trendsTab
        case .distribution:
            distributionTab
        }
    }

    // MARK: - 概览 Tab

    private var overviewTab: some View {
        VStack(spacing: 20) {
            readingStatusSection
            bookTypeSection
            if totalMinutesRead > 0 || totalPagesRead > 0 {
                readingTimeSection
            }
            addSourceSection
        }
    }

    // MARK: - 趋势 Tab

    private var trendsTab: some View {
        VStack(spacing: 20) {
            if monthlyFinished.contains(where: { $0.count > 0 }) {
                chartCard(title: "月度完读", icon: "checkmark.circle") {
                    Chart {
                        ForEach(Array(monthlyFinished.enumerated()), id: \.offset) { _, item in
                            BarMark(
                                x: .value("月份", item.month),
                                y: .value("数量", item.count)
                            )
                            .foregroundStyle(.green.gradient)
                            .cornerRadius(4)
                        }
                    }
                    .frame(height: 220)
                }
            }

            if stats.monthlyAdded.contains(where: { $0.count > 0 }) {
                chartCard(title: "月度入库", icon: "arrow.down.to.line") {
                    Chart {
                        ForEach(Array(stats.monthlyAdded.enumerated()), id: \.offset) { _, item in
                            BarMark(
                                x: .value("月份", item.month),
                                y: .value("数量", item.count)
                            )
                            .foregroundStyle(.blue.gradient)
                            .cornerRadius(4)
                        }
                    }
                    .frame(height: 220)
                }
            }

            if yearlyAdded.count > 1 {
                chartCard(title: "年度入库", icon: "calendar") {
                    Chart {
                        ForEach(Array(yearlyAdded.enumerated()), id: \.offset) { _, item in
                            BarMark(
                                x: .value("年份", item.year),
                                y: .value("数量", item.count)
                            )
                            .foregroundStyle(.purple.gradient)
                            .cornerRadius(4)
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    // MARK: - 分布 Tab

    private var distributionTab: some View {
        VStack(spacing: 20) {
            if ratedBooksTotal > 0 {
                ratingSection
            }
            if !topTags.isEmpty {
                tagRankingSection
            }
            if !stats.bookshelfStats.isEmpty {
                bookshelfSection
            }
            typeDetailSection
        }
    }

    // MARK: - 阅读状态

    private var readingStatusSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(title: "阅读状态", icon: "list.bullet")

                VStack(spacing: 8) {
                    StatusRow(label: "正在读", count: booksReading, total: totalBooks, color: .orange)
                    StatusRow(label: "已读", count: booksRead, total: totalBooks, color: .green)
                    StatusRow(label: "想读", count: booksWishlist, total: totalBooks, color: .blue)
                    StatusRow(label: "闲置", count: booksIdle, total: totalBooks, color: .gray)
                    StatusRow(label: "弃读", count: booksDropped, total: totalBooks, color: .red)
                }
            }
        }
    }

    // MARK: - 书籍类型

    private var bookTypeSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(title: "书籍类型", icon: "square.stack.3d.up")

                HStack(spacing: 0) {
                    if paperCount > 0 {
                        TypeBar(color: .brown, ratio: CGFloat(paperCount) / CGFloat(max(totalBooks, 1)))
                    }
                    if ebookCount > 0 {
                        TypeBar(color: .blue, ratio: CGFloat(ebookCount) / CGFloat(max(totalBooks, 1)))
                    }
                    if audiobookCount > 0 {
                        TypeBar(color: .purple, ratio: CGFloat(audiobookCount) / CGFloat(max(totalBooks, 1)))
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())

                HStack(spacing: 16) {
                    TypePill(label: "纸质书", count: paperCount, color: .brown)
                    TypePill(label: "电子书", count: ebookCount, color: .blue)
                    TypePill(label: "有声书", count: audiobookCount, color: .purple)
                }
            }
        }
    }

    // MARK: - 阅读时间

    private var readingTimeSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(title: "阅读数据", icon: "clock")

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    miniStat(value: formatTotalTime(totalMinutesRead), label: "累计时长")
                    miniStat(value: "\(totalPagesRead) 页", label: "累计页数")
                    miniStat(value: "\(uniqueReadingDays) 天", label: "阅读天数")
                    miniStat(value: dailyPages, label: "日均页数")
                }
            }
        }
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 加入方式

    private var addSourceSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(title: "加入方式", icon: "arrow.down.to.line")

                HStack(spacing: 0) {
                    if stats.manualCount > 0 {
                        TypeBar(color: .green, ratio: CGFloat(stats.manualCount) / CGFloat(max(totalBooks, 1)))
                    }
                    if stats.scannedCount > 0 {
                        TypeBar(color: .orange, ratio: CGFloat(stats.scannedCount) / CGFloat(max(totalBooks, 1)))
                    }
                    if stats.importedCount > 0 {
                        TypeBar(color: .blue, ratio: CGFloat(stats.importedCount) / CGFloat(max(totalBooks, 1)))
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())

                HStack(spacing: 16) {
                    TypePill(label: "手动", count: stats.manualCount, color: .green)
                    TypePill(label: "扫码", count: stats.scannedCount, color: .orange)
                    TypePill(label: "导入", count: stats.importedCount, color: .blue)
                }
            }
        }
    }

    // MARK: - 评分分布

    private var ratingSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(title: "评分分布", icon: "star")

                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(ratedBooks, id: \.rating) { item in
                        VStack(spacing: 4) {
                            Text("\(item.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(.yellow.gradient)
                                .frame(width: 36, height: max(CGFloat(item.count) / CGFloat(max(ratedBooksTotal, 1)) * 80, 4))

                            HStack(spacing: 1) {
                                Text("\(item.rating)")
                                    .font(.caption2)
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Text("平均评分 \(String(format: "%.1f", averageRating)) 分 · 共 \(ratedBooksTotal) 本已评分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 标签排行

    private var tagRankingSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(title: "标签 Top 10", icon: "tag")

                VStack(spacing: 6) {
                    ForEach(Array(topTags.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .center)

                            Text(item.name)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            Text("\(item.count) 本")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.blue.opacity(0.3))
                                    .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(max(topTags.first?.count ?? 1, 1)))
                            }
                            .frame(width: 60, height: 8)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - 书架统计

    private var bookshelfSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(title: "书架统计", icon: "books.vertical")

                VStack(spacing: 10) {
                    ForEach(stats.bookshelfStats) { shelf in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(shelf.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(shelf.total) 本")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 0) {
                                if shelf.paperCount > 0 {
                                    TypeBar(color: .brown, ratio: CGFloat(shelf.paperCount) / CGFloat(max(shelf.total, 1)))
                                }
                                if shelf.ebookCount > 0 {
                                    TypeBar(color: .blue, ratio: CGFloat(shelf.ebookCount) / CGFloat(max(shelf.total, 1)))
                                }
                                if shelf.audiobookCount > 0 {
                                    TypeBar(color: .purple, ratio: CGFloat(shelf.audiobookCount) / CGFloat(max(shelf.total, 1)))
                                }
                            }
                            .frame(height: 6)
                            .clipShape(Capsule())

                            HStack(spacing: 12) {
                                if shelf.paperCount > 0 {
                                    miniLabel("纸质 \(shelf.paperCount)", color: .brown)
                                }
                                if shelf.ebookCount > 0 {
                                    miniLabel("电子 \(shelf.ebookCount)", color: .blue)
                                }
                                if shelf.audiobookCount > 0 {
                                    miniLabel("有声 \(shelf.audiobookCount)", color: .purple)
                                }
                                Spacer()
                                Text("已读 \(shelf.finished) · 在读 \(shelf.reading)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // MARK: - 分类型阅读状态

    private var typeDetailSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(title: "分类型阅读状态", icon: "rectangle.split.3x1")

                VStack(spacing: 12) {
                    if stats.paperStats.total > 0 {
                        typeStatusRow(title: "纸质书", stats: stats.paperStats, color: .brown)
                    }
                    if stats.ebookStats.total > 0 {
                        typeStatusRow(title: "电子书", stats: stats.ebookStats, color: .blue)
                    }
                    if stats.audiobookStats.total > 0 {
                        typeStatusRow(title: "有声书", stats: stats.audiobookStats, color: .purple)
                    }
                }
            }
        }
    }

    private func typeStatusRow(title: String, stats: TypeStatusStats, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(stats.total) 本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                if stats.finished > 0 {
                    TypeBar(color: .green, ratio: CGFloat(stats.finished) / CGFloat(max(stats.total, 1)))
                }
                if stats.reading > 0 {
                    TypeBar(color: .orange, ratio: CGFloat(stats.reading) / CGFloat(max(stats.total, 1)))
                }
                if stats.wishlist > 0 {
                    TypeBar(color: .blue, ratio: CGFloat(stats.wishlist) / CGFloat(max(stats.total, 1)))
                }
                if stats.idle > 0 {
                    TypeBar(color: .gray, ratio: CGFloat(stats.idle) / CGFloat(max(stats.total, 1)))
                }
                if stats.dropped > 0 {
                    TypeBar(color: .red, ratio: CGFloat(stats.dropped) / CGFloat(max(stats.total, 1)))
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            HStack(spacing: 10) {
                if stats.finished > 0 { miniLabel("已读 \(stats.finished)", color: .green) }
                if stats.reading > 0 { miniLabel("在读 \(stats.reading)", color: .orange) }
                if stats.wishlist > 0 { miniLabel("想读 \(stats.wishlist)", color: .blue) }
                if stats.idle > 0 { miniLabel("闲置 \(stats.idle)", color: .gray) }
                if stats.dropped > 0 { miniLabel("弃读 \(stats.dropped)", color: .red) }
            }
            .font(.caption2)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func miniLabel(_ text: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).foregroundStyle(.secondary)
        }
    }

    // MARK: - Card Containers

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            )
            .padding(.horizontal)
    }

    private func chartCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(title: title, icon: icon)
                content()
            }
        }
    }

    private func cardHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .fontWeight(.semibold)
    }

    // MARK: - Helpers

    private var uniqueReadingDays: Int {
        let calendar = Calendar.current
        let days = Set(records.map { calendar.startOfDay(for: $0.date) })
        return days.count
    }

    private var dailyPages: String {
        guard uniqueReadingDays > 0 else { return "0" }
        let avg = Double(totalPagesRead) / Double(uniqueReadingDays)
        return String(format: "%.1f 页", avg)
    }

    private func formatTotalTime(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes) 分钟"
    }

    /// 一次遍历计算所有统计数据
    private func computeStats() -> CachedStatistics {
        let calendar = Calendar.current
        let now = Date()

        var booksRead = 0, booksReading = 0, booksWishlist = 0, booksDropped = 0, booksIdle = 0
        var paperCount = 0, ebookCount = 0, audiobookCount = 0
        var manualCount = 0, scannedCount = 0, importedCount = 0
        var ratingCounts = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        var ratingSum = 0, ratingTotal = 0
        var yearCounts: [Int: Int] = [:]
        var tagCounts: [String: Int] = [:]

        var paperReading = 0, paperFinished = 0, paperWishlist = 0, paperDropped = 0, paperIdle = 0
        var ebookReading = 0, ebookFinished = 0, ebookWishlist = 0, ebookDropped = 0, ebookIdle = 0
        var audioReading = 0, audioFinished = 0, audioWishlist = 0, audioDropped = 0, audioIdle = 0

        var shelfMap: [String: (total: Int, finished: Int, reading: Int, paper: Int, ebook: Int, audio: Int)] = [:]

        var monthlyMap: [String: Int] = [:]
        var monthlyAddedMap: [String: Int] = [:]
        for i in (0..<12).reversed() {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                let key = "\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))"
                monthlyMap[key] = 0
                monthlyAddedMap[key] = 0
            }
        }

        for book in books {
            switch book.status {
            case .finished: booksRead += 1
            case .reading: booksReading += 1
            case .wishlist: booksWishlist += 1
            case .dropped: booksDropped += 1
            case .idle: booksIdle += 1
            }

            switch book.bookType {
            case .paper:
                paperCount += 1
                switch book.status {
                case .reading: paperReading += 1
                case .finished: paperFinished += 1
                case .wishlist: paperWishlist += 1
                case .dropped: paperDropped += 1
                case .idle: paperIdle += 1
                }
            case .ebook:
                ebookCount += 1
                switch book.status {
                case .reading: ebookReading += 1
                case .finished: ebookFinished += 1
                case .wishlist: ebookWishlist += 1
                case .dropped: ebookDropped += 1
                case .idle: ebookIdle += 1
                }
            case .audiobook:
                audiobookCount += 1
                switch book.status {
                case .reading: audioReading += 1
                case .finished: audioFinished += 1
                case .wishlist: audioWishlist += 1
                case .dropped: audioDropped += 1
                case .idle: audioIdle += 1
                }
            }

            if let shelf = book.bookshelf {
                var entry = shelfMap[shelf.name] ?? (0, 0, 0, 0, 0, 0)
                entry.total += 1
                if book.status == .finished { entry.finished += 1 }
                if book.status == .reading { entry.reading += 1 }
                switch book.bookType {
                case .paper: entry.paper += 1
                case .ebook: entry.ebook += 1
                case .audiobook: entry.audio += 1
                }
                shelfMap[shelf.name] = entry
            }

            if let rating = book.rating, (1...5).contains(rating) {
                ratingCounts[rating, default: 0] += 1
                ratingSum += rating
                ratingTotal += 1
            }

            switch book.addSource {
            case .manual: manualCount += 1
            case .scanned: scannedCount += 1
            case .imported: importedCount += 1
            }

            let year = calendar.component(.year, from: book.addedDate)
            yearCounts[year, default: 0] += 1

            let addedKey = "\(calendar.component(.year, from: book.addedDate))-\(calendar.component(.month, from: book.addedDate))"
            if monthlyAddedMap[addedKey] != nil {
                monthlyAddedMap[addedKey]! += 1
            }

            for tag in book.tags ?? [] {
                tagCounts[tag.name, default: 0] += 1
            }

            if book.status == .finished, let finished = book.finishedDate {
                let key = "\(calendar.component(.year, from: finished))-\(calendar.component(.month, from: finished))"
                if monthlyMap[key] != nil {
                    monthlyMap[key]! += 1
                }
            }
        }

        var monthlyFinished: [(String, Int)] = []
        for i in (0..<12).reversed() {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                let month = calendar.component(.month, from: date)
                let key = "\(calendar.component(.year, from: date))-\(month)"
                monthlyFinished.append(("\(month)月", monthlyMap[key] ?? 0))
            }
        }

        var monthlyAddedArr: [(String, Int)] = []
        for i in (0..<12).reversed() {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                let month = calendar.component(.month, from: date)
                let key = "\(calendar.component(.year, from: date))-\(month)"
                monthlyAddedArr.append(("\(month)月", monthlyAddedMap[key] ?? 0))
            }
        }

        let yearly = yearCounts.sorted { $0.key < $1.key }
            .suffix(5)
            .map { ("\($0.key)", $0.value) }

        let topTagsList = tagCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { ($0.key, $0.value) }

        let ratedList = (1...5).map { (rating: $0, count: ratingCounts[$0] ?? 0) }
        let avgRating = ratingTotal > 0 ? Double(ratingSum) / Double(ratingTotal) : 0

        let bookshelfStatsList = shelfMap
            .sorted { $0.value.total > $1.value.total }
            .map { BookshelfStats(
                id: $0.key, name: $0.key,
                total: $0.value.total, finished: $0.value.finished, reading: $0.value.reading,
                paperCount: $0.value.paper, ebookCount: $0.value.ebook, audiobookCount: $0.value.audio
            ) }

        return CachedStatistics(
            bookCount: books.count,
            totalBooks: books.count,
            booksRead: booksRead,
            booksReading: booksReading,
            booksWishlist: booksWishlist,
            booksDropped: booksDropped,
            booksIdle: booksIdle,
            paperCount: paperCount,
            ebookCount: ebookCount,
            audiobookCount: audiobookCount,
            paperStats: TypeStatusStats(total: paperCount, reading: paperReading, finished: paperFinished, wishlist: paperWishlist, dropped: paperDropped, idle: paperIdle),
            ebookStats: TypeStatusStats(total: ebookCount, reading: ebookReading, finished: ebookFinished, wishlist: ebookWishlist, dropped: ebookDropped, idle: ebookIdle),
            audiobookStats: TypeStatusStats(total: audiobookCount, reading: audioReading, finished: audioFinished, wishlist: audioWishlist, dropped: audioDropped, idle: audioIdle),
            ratedBooks: ratedList,
            averageRating: avgRating,
            monthlyFinished: monthlyFinished,
            yearlyAdded: yearly,
            monthlyAdded: monthlyAddedArr,
            topTags: topTagsList,
            bookshelfStats: bookshelfStatsList,
            manualCount: manualCount,
            scannedCount: scannedCount,
            importedCount: importedCount
        )
    }
}

// MARK: - 子组件

struct TypeBar: View {
    let color: Color
    let ratio: CGFloat

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: nil, height: nil)
            .layoutPriority(Double(ratio))
    }
}

struct TypePill: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label) \(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct StatusRow: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text("\(count) 本")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.4))
                    .frame(width: total > 0 ? geo.size.width * CGFloat(count) / CGFloat(total) : 0)
            }
            .frame(width: 80, height: 8)
        }
    }
}

#Preview {
    StatisticsView()
        .modelContainer(for: [Book.self, ReadingRecord.self, Tag.self], inMemory: true)
}
