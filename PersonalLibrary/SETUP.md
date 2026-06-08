# PersonalLibrary — 项目初始化指引

## 前置条件

1. **安装 Xcode** — 从 App Store 下载 Xcode（免费，约 12GB）
2. 首次打开 Xcode 时同意 License 协议并安装附加组件

## 创建 Xcode 项目

源代码文件已经准备好了。你需要在 Xcode 中创建项目，然后把这些文件加进去：

### 步骤 1: 新建项目
1. 打开 Xcode → File → New → Project
2. 选择 **iOS** → **App** → Next
3. 填写信息：
   - Product Name: `PersonalLibrary`
   - Organization Identifier: `com.example`（改成你自己的）
   - Interface: **SwiftUI**
   - Storage: **SwiftData**
   - Language: **Swift**
4. 选择保存位置为本目录（覆盖 PersonalLibrary.xcodeproj）

### 步骤 2: 替换文件
1. 在 Xcode 左侧 Navigator 中删除自动生成的 `ContentView.swift` 和 `Item.swift`
2. 右键 PersonalLibrary 文件夹 → Add Files to "PersonalLibrary"
3. 选中 `Models/`、`Views/`、`Services/` 文件夹（勾选 "Create groups"）
4. 把现有的 `PersonalLibraryApp.swift` 和 `ContentView.swift` 也替换进去

### 步骤 3: 运行
- 选择 iPhone 模拟器 → ⌘R 运行

## 项目结构

```
PersonalLibrary/
├── PersonalLibraryApp.swift    # App 入口
├── ContentView.swift           # 主界面 (TabView)
├── Models/
│   ├── Book.swift              # 书籍模型 (SwiftData)
│   └── ReadingRecord.swift     # 阅读记录模型
├── Views/
│   ├── Books/
│   │   ├── BookListView.swift  # 书架列表
│   │   ├── BookDetailView.swift # 书籍详情
│   │   └── AddBookView.swift   # 添加新书
│   └── Reading/
│       ├── ReadingProgressView.swift  # 在读书籍
│       ├── AddReadingRecordView.swift # 记录阅读
│       └── StatisticsView.swift       # 阅读统计
├── Services/
│   └── BookService.swift       # 业务逻辑层
└── Assets.xcassets/            # 图标和颜色资源
```

## 技术栈

- **SwiftUI** — 声明式 UI 框架
- **SwiftData** — Apple 原生 ORM（数据自动持久化到本地）
- **iOS 17+** — 最低支持版本
- **Swift Testing** — 单元测试框架
