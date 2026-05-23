import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @Query private var records: [ReadingRecord]
    @Query(sort: \Bookshelf.sortOrder) private var bookshelves: [Bookshelf]

    @State private var cachedStats: CachedStatistics?
    @State private var selectedTab: StatsTab = .overview
    @State private var trendFilter: BookType? = nil  // nil = 全部
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

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
        let wereadImportedCount: Int

        // 藏书分析
        let topAuthors: [(name: String, count: Int)]
        let topPublishers: [(name: String, count: Int)]
        let topCategories: [(name: String, count: Int)]

        // 趋势（按类型细分）
        let allYears: [Int]  // 有数据的年份列表
        // 全量月度数据：[year-month: (total, paper, ebook, audiobook)]
        let monthlyAddedByType: [String: (total: Int, paper: Int, ebook: Int, audiobook: Int)]
        let monthlyFinishedByType: [String: (total: Int, paper: Int, ebook: Int, audiobook: Int)]
        let yearlyAddedByType: [(year: Int, total: Int, paper: Int, ebook: Int, audiobook: Int)]
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
            .task { cachedStats = computeStats() }
            .onChange(of: books.count) { _, _ in cachedStats = computeStats() }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        HStack(spacing: 0) {
            heroItem(value: "\(totalBooks)", label: "总藏书", color: .blue)
            heroDivider
            heroItem(value: "\(paperCount)", label: "纸质书", color: .brown)
            heroDivider
            heroItem(value: "\(ebookCount)", label: "电子书", color: .teal)
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
            // 类型筛选器
            trendFilterPicker

            // 年度入库
            if !stats.yearlyAddedByType.isEmpty {
                chartCard(title: "年度入库", icon: "calendar") {
                    Chart {
                        ForEach(stats.yearlyAddedByType, id: \.year) { item in
                            BarMark(
                                x: .value("年份", "\(item.year)"),
                                y: .value("数量", filteredYearlyCount(item))
                            )
                            .foregroundStyle(.purple.gradient)
                            .cornerRadius(4)
                        }
                    }
                    .frame(height: 180)
                }
            }

            // 月度入库（可选年份）
            chartCard(title: "月度入库", icon: "arrow.down.to.line") {
                VStack(spacing: 12) {
                    // 年份选择器
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(stats.allYears, id: \.self) { year in
                                Button {
                                    selectedYear = year
                                } label: {
                                    Text("\(String(year))")
                                        .font(.caption)
                                        .fontWeight(selectedYear == year ? .bold : .regular)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedYear == year ? Color.blue : Color(.systemGray5))
                                        .foregroundStyle(selectedYear == year ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Chart {
                        ForEach(1...12, id: \.self) { month in
                            let key = "\(selectedYear)-\(month)"
                            let count = filteredMonthlyAdded(key: key)
                            BarMark(
                                x: .value("月份", "\(month)月"),
                                y: .value("数量", count)
                            )
                            .foregroundStyle(.blue.gradient)
                            .cornerRadius(4)
                        }
                    }
                    .frame(height: 220)
                }
            }

            // 月度完读（选中年份）
            chartCard(title: "月度完读", icon: "checkmark.circle") {
                Chart {
                    ForEach(1...12, id: \.self) { month in
                        let key = "\(selectedYear)-\(month)"
                        let count = filteredMonthlyFinished(key: key)
                        BarMark(
                            x: .value("月份", "\(month)月"),
                            y: .value("数量", count)
                        )
                        .foregroundStyle(.green.gradient)
                        .cornerRadius(4)
                    }
                }
                .frame(height: 220)
            }
        }
    }

    // MARK: - 趋势筛选器

    private var trendFilterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "全部", isActive: trendFilter == nil) { trendFilter = nil }
                filterChip(label: "纸质书", isActive: trendFilter == .paper) { trendFilter = .paper }
                filterChip(label: "电子书", isActive: trendFilter == .ebook) { trendFilter = .ebook }
                filterChip(label: "有声书", isActive: trendFilter == .audiobook) { trendFilter = .audiobook }
            }
            .padding(.horizontal)
        }
    }

    private func filterChip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isActive ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isActive ? .white : .primary)
                .clipShape(Capsule())
        }
    }

    private func filteredYearlyCount(_ item: (year: Int, total: Int, paper: Int, ebook: Int, audiobook: Int)) -> Int {
        switch trendFilter {
        case nil: return item.total
        case .paper: return item.paper
        case .ebook: return item.ebook
        case .audiobook: return item.audiobook
        }
    }

    private func filteredMonthlyAdded(key: String) -> Int {
        guard let entry = stats.monthlyAddedByType[key] else { return 0 }
        switch trendFilter {
        case nil: return entry.total
        case .paper: return entry.paper
        case .ebook: return entry.ebook
        case .audiobook: return entry.audiobook
        }
    }

    private func filteredMonthlyFinished(key: String) -> Int {
        guard let entry = stats.monthlyFinishedByType[key] else { return 0 }
        switch trendFilter {
        case nil: return entry.total
        case .paper: return entry.paper
        case .ebook: return entry.ebook
        case .audiobook: return entry.audiobook
        }
    }

    // MARK: - 分布 Tab

    private var distributionTab: some View {
        VStack(spacing: 20) {
            collectionAnalysisSection
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

    // MARK: - 藏书分析

    private var collectionAnalysisSection: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 16) {
                cardHeader(title: "藏书分析", icon: "chart.bar.doc.horizontal")

                if !stats.topAuthors.isEmpty {
                    rankingBlock(title: "最爱作者", icon: "person.fill", items: stats.topAuthors, color: .orange)
                }

                if !stats.topPublishers.isEmpty {
                    rankingBlock(title: "最爱出版社", icon: "building.2.fill", items: stats.topPublishers, color: .blue)
                }

                if !stats.topCategories.isEmpty {
                    rankingBlock(title: "最爱题材", icon: "text.book.closed.fill", items: stats.topCategories, color: .purple)
                }
            }
        }
    }

    private func rankingBlock(title: String, icon: String, items: [(name: String, count: Int)], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(index == 0 ? color : .secondary)
                        .frame(width: 16)

                    Text(item.name)
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer()

                    Text("\(item.count) 本")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.3))
                            .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(max(items.first?.count ?? 1, 1)))
                    }
                    .frame(width: 50, height: 8)
                }
            }
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
                    if stats.wereadImportedCount > 0 {
                        TypeBar(color: .teal, ratio: CGFloat(stats.wereadImportedCount) / CGFloat(max(totalBooks, 1)))
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    TypePill(label: "手动", count: stats.manualCount, color: .green)
                    TypePill(label: "扫码", count: stats.scannedCount, color: .orange)
                    TypePill(label: "文件导入", count: stats.importedCount, color: .blue)
                    TypePill(label: "微信读书", count: stats.wereadImportedCount, color: .teal)
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
        var manualCount = 0, scannedCount = 0, importedCount = 0, wereadImportedCount = 0
        var ratingCounts = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        var ratingSum = 0, ratingTotal = 0
        var tagCounts: [String: Int] = [:]
        var authorCounts: [String: Int] = [:]
        var publisherCounts: [String: Int] = [:]
        var categoryCounts: [String: Int] = [:]

        var paperReading = 0, paperFinished = 0, paperWishlist = 0, paperDropped = 0, paperIdle = 0
        var ebookReading = 0, ebookFinished = 0, ebookWishlist = 0, ebookDropped = 0, ebookIdle = 0
        var audioReading = 0, audioFinished = 0, audioWishlist = 0, audioDropped = 0, audioIdle = 0

        var shelfMap: [String: (total: Int, finished: Int, reading: Int, paper: Int, ebook: Int, audio: Int)] = [:]

        // 月度数据：key = "year-month", value = (total, paper, ebook, audiobook)
        var monthlyAddedByType: [String: (total: Int, paper: Int, ebook: Int, audiobook: Int)] = [:]
        var monthlyFinishedByType: [String: (total: Int, paper: Int, ebook: Int, audiobook: Int)] = [:]
        // 年度数据：key = year
        var yearlyAddedByType: [Int: (total: Int, paper: Int, ebook: Int, audiobook: Int)] = [:]
        var allYearsSet: Set<Int> = []

        // 兼容旧的12月视图
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
            case .wereadImported: wereadImportedCount += 1
            }

            // 作者统计
            let author = book.author.trimmingCharacters(in: .whitespaces)
            if !author.isEmpty && author != "未知作者" {
                authorCounts[author, default: 0] += 1
            }

            // 出版社统计
            if let publisher = book.publisher, !publisher.isEmpty {
                publisherCounts[publisher, default: 0] += 1
            }

            // 年月入库统计（带类型）
            let addedYear = calendar.component(.year, from: book.addedDate)
            let addedMonth = calendar.component(.month, from: book.addedDate)
            let addedKey = "\(addedYear)-\(addedMonth)"
            allYearsSet.insert(addedYear)

            var monthEntry = monthlyAddedByType[addedKey] ?? (0, 0, 0, 0)
            monthEntry.total += 1
            switch book.bookType {
            case .paper: monthEntry.paper += 1
            case .ebook: monthEntry.ebook += 1
            case .audiobook: monthEntry.audiobook += 1
            }
            monthlyAddedByType[addedKey] = monthEntry

            var yearEntry = yearlyAddedByType[addedYear] ?? (0, 0, 0, 0)
            yearEntry.total += 1
            switch book.bookType {
            case .paper: yearEntry.paper += 1
            case .ebook: yearEntry.ebook += 1
            case .audiobook: yearEntry.audiobook += 1
            }
            yearlyAddedByType[addedYear] = yearEntry

            if monthlyAddedMap[addedKey] != nil {
                monthlyAddedMap[addedKey]! += 1
            }

            // 标签统计（含题材分类）
            for tag in book.tags ?? [] {
                tagCounts[tag.name, default: 0] += 1
                // 排除"微信读书"标签作为题材
                if tag.name != "微信读书" {
                    categoryCounts[tag.name, default: 0] += 1
                }
            }

            // 月度完读统计（带类型）
            if book.status == .finished, let finished = book.finishedDate {
                let fYear = calendar.component(.year, from: finished)
                let fMonth = calendar.component(.month, from: finished)
                let fKey = "\(fYear)-\(fMonth)"
                allYearsSet.insert(fYear)

                var fEntry = monthlyFinishedByType[fKey] ?? (0, 0, 0, 0)
                fEntry.total += 1
                switch book.bookType {
                case .paper: fEntry.paper += 1
                case .ebook: fEntry.ebook += 1
                case .audiobook: fEntry.audiobook += 1
                }
                monthlyFinishedByType[fKey] = fEntry

                let key = "\(fYear)-\(fMonth)"
                if monthlyMap[key] != nil {
                    monthlyMap[key]! += 1
                }
            }
        }

        // 兼容旧的12月视图数据
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

        let yearly = yearlyAddedByType.sorted { $0.key < $1.key }
            .suffix(10)
            .map { ("\($0.key)", $0.value.total) }

        let topTagsList = tagCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { ($0.key, $0.value) }

        let topAuthorsList = authorCounts.sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }

        let topPublishersList = publisherCounts.sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }

        let topCategoriesList = categoryCounts.sorted { $0.value > $1.value }
            .prefix(5)
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

        let yearlyAddedByTypeArr = yearlyAddedByType.sorted { $0.key < $1.key }
            .map { (year: $0.key, total: $0.value.total, paper: $0.value.paper, ebook: $0.value.ebook, audiobook: $0.value.audiobook) }

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
            importedCount: importedCount,
            wereadImportedCount: wereadImportedCount,
            topAuthors: topAuthorsList,
            topPublishers: topPublishersList,
            topCategories: topCategoriesList,
            allYears: allYearsSet.sorted(),
            monthlyAddedByType: monthlyAddedByType,
            monthlyFinishedByType: monthlyFinishedByType,
            yearlyAddedByType: yearlyAddedByTypeArr
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
