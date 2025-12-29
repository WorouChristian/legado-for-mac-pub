import SwiftUI

/// 订阅源管理视图
struct RSSSourceManagementView: View {
    @StateObject private var viewModel = RSSSourceViewModel()
    @State private var showingImportPicker = false
    @State private var showingAddSheet = false
    @State private var showingUrlImport = false
    @State private var importUrl = ""

    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading {
                    ProgressView("加载中...")
                } else if viewModel.sources.isEmpty {
                    emptyView
                } else {
                    sourceList
                }
            }
            .navigationTitle("订阅源管理")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button("刷新全部") {
                        Task {
                            await viewModel.refreshAllSources()
                        }
                    }

                    Menu("导入") {
                        Button("从文件导入") {
                            showingImportPicker = true
                        }
                        Button("从URL导入") {
                            showingUrlImport = true
                        }
                    }

                    Button("添加") {
                        showingAddSheet = true
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    viewModel.importSources(from: url)
                }
            }
            .sheet(isPresented: $showingUrlImport) {
                ImportFromUrlView { url in
                    Task {
                        await viewModel.importFromUrl(url)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddRSSSourceView { source in
                    viewModel.addSource(source)
                }
            }
            .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "newspaper")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("还没有订阅源")
                .font(.title2)
                .foregroundColor(.gray)

            Button("添加订阅源") {
                showingAddSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sourceList: some View {
        List {
            ForEach(viewModel.sources) { source in
                NavigationLink(destination: ArticleListView(source: source)) {
                    RSSSourceRow(source: source, viewModel: viewModel)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    viewModel.deleteSource(viewModel.sources[index])
                }
            }
        }
    }
}

/// 订阅源行视图
struct RSSSourceRow: View {
    let source: RSSSource
    let viewModel: RSSSourceViewModel

    var body: some View {
        HStack {
            // 图标
            if let iconUrl = source.sourceIcon, let url = URL(string: iconUrl) {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Image(systemName: "newspaper")
                }
                .frame(width: 40, height: 40)
                .cornerRadius(8)
            } else {
                Image(systemName: "newspaper")
                    .frame(width: 40, height: 40)
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(source.sourceName)
                    .font(.headline)

                if let group = source.sourceGroup {
                    Text(group)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if source.lastUpdateTime > 0 {
                    Text("更新: \(formatDate(source.lastUpdateTime))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 刷新按钮
            Button {
                Task {
                    await viewModel.refreshSource(source)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)

            // 启用开关
            Toggle("", isOn: .constant(source.enabled))
                .labelsHidden()
                .onChange(of: source.enabled) { _ in
                    viewModel.toggleEnabled(source)
                }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// 文章列表视图
struct ArticleListView: View {
    let source: RSSSource
    @StateObject private var viewModel: ArticleListViewModel
    @Environment(\.dismiss) private var dismiss

    init(source: RSSSource) {
        self.source = source
        _viewModel = StateObject(wrappedValue: ArticleListViewModel(source: source))
    }

    var body: some View {
        VStack {
            // 如果是singleUrl，直接显示网页
            if source.singleUrl {
                WebContentView(url: source.sourceUrl)
            }
            // 如果有sortUrl，显示分类列表
            else if let sortUrl = source.sortUrl, !sortUrl.isEmpty {
                SortUrlListView(source: source, sortUrl: sortUrl)
            }
            // 否则显示文章列表
            else if viewModel.isLoading {
                ProgressView("加载中...")
            } else if viewModel.articles.isEmpty {
                emptyView
            } else {
                articleList
            }
        }
        .navigationTitle(source.sourceName)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack {
                    if !source.singleUrl && (source.sortUrl == nil || source.sortUrl?.isEmpty == true) {
                        Text("未读: \(viewModel.unreadCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("刷新") {
                            Task {
                                await refreshSource()
                            }
                        }
                    }

                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("还没有内容")
                .font(.title2)
                .foregroundColor(.gray)

            Text("点击下方按钮刷新订阅源")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("刷新订阅源") {
                Task {
                    await refreshSource()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func refreshSource() async {
        let rssViewModel = RSSSourceViewModel()
        await rssViewModel.refreshSource(source)
        viewModel.loadArticles()
    }

    private var articleList: some View {
        List(viewModel.articles) { article in
            NavigationLink(destination: ArticleDetailView(article: article, viewModel: viewModel)) {
                ArticleRow(article: article)
            }
        }
    }
}

/// 文章行视图
struct ArticleRow: View {
    let article: Article

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 图片
            if let imageUrl = article.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 80, height: 80)
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                // 标题
                Text(article.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(article.isRead ? .secondary : .primary)

                // 描述
                if let description = article.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // 时间
                if let pubDate = article.pubDate {
                    Text(formatDate(pubDate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 未读标记
            if !article.isRead {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// 文章详情视图
struct ArticleDetailView: View {
    let article: Article
    let viewModel: ArticleListViewModel

    @State private var content: String?
    @State private var isLoadingContent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 标题
                Text(article.title)
                    .font(.title)
                    .fontWeight(.bold)

                // 元信息
                HStack {
                    if let pubDate = article.pubDate {
                        Text(formatDate(pubDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        viewModel.toggleFavorite(article)
                    } label: {
                        Image(systemName: article.isFavorite ? "star.fill" : "star")
                    }
                }

                Divider()

                // 内容
                if let content = content {
                    Text(content)
                        .font(.body)
                } else if let description = article.description {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.secondary)
                } else if isLoadingContent {
                    ProgressView("加载内容中...")
                } else {
                    Text("点击下方按钮查看完整内容")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // 查看原文按钮
                if content == nil {
                    Button("查看完整内容") {
                        loadContent()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Link("在浏览器中打开", destination: URL(string: article.link)!)
                    .font(.caption)
            }
            .padding()
        }
        .navigationTitle("文章详情")
        .onAppear {
            viewModel.markAsRead(article)
        }
    }

    private func loadContent() {
        isLoadingContent = true
        Task {
            content = await viewModel.fetchContent(for: article)
            isLoadingContent = false
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// 添加订阅源视图
struct AddRSSSourceView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (RSSSource) -> Void

    @State private var sourceName = ""
    @State private var sourceUrl = ""
    @State private var sourceGroup = ""

    var body: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    TextField("订阅源名称", text: $sourceName)
                    TextField("订阅源URL", text: $sourceUrl)
                    TextField("分组（可选）", text: $sourceGroup)
                }

                Section {
                    Button("添加") {
                        addSource()
                    }
                    .disabled(sourceName.isEmpty || sourceUrl.isEmpty)
                }
            }
            .navigationTitle("添加订阅源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func addSource() {
        let source = RSSSource(
            sourceName: sourceName,
            sourceUrl: sourceUrl,
            sourceGroup: sourceGroup.isEmpty ? nil : sourceGroup
        )
        onAdd(source)
        dismiss()
    }
}

/// 从URL导入视图
struct ImportFromUrlView: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: (String) -> Void

    @State private var urlText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section("订阅源URL") {
                    TextField("https://example.com/sources.json", text: $urlText)
                        .focused($isTextFieldFocused)
                        .onAppear {
                            isTextFieldFocused = true
                        }
                }

                Section {
                    Button("导入") {
                        onImport(urlText)
                        dismiss()
                    }
                    .disabled(urlText.isEmpty)
                }
            }
            .navigationTitle("从URL导入")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 250)
    }
}

// MARK: - 分类列表视图

/// 分类列表视图（解析sortUrl）
struct SortUrlListView: View {
    let source: RSSSource
    let sortUrl: String
    @State private var categories: [(name: String, url: String)] = []

    var body: some View {
        List(categories, id: \.name) { category in
            Button(action: {
                if let url = URL(string: category.url) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack {
                    Image(systemName: "folder")
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name)
                            .font(.headline)

                        Text(category.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            parseSortUrl()
        }
    }

    private func parseSortUrl() {
        // 解析sortUrl格式：📚MD.2::https://wwdn.lanzoue.com/b0d5g0tba##iori
        let lines = sortUrl.components(separatedBy: "\n")
        categories = lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            // 分割名称和URL
            let parts = trimmed.components(separatedBy: "::")
            guard parts.count >= 2 else { return nil }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let urlPart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            // 提取URL（去掉##后面的密码和【】中的图标）
            let url = urlPart.components(separatedBy: "##").first?
                .components(separatedBy: "【").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? urlPart

            return (name: name, url: url)
        }
    }
}

// MARK: - 网页内容视图

/// 网页内容视图
struct WebContentView: View {
    let url: String

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "globe")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("此订阅源需要在浏览器中查看")
                .font(.title2)
                .foregroundColor(.primary)

            Text(url)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("在浏览器中打开") {
                if let url = URL(string: url) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 预览

struct RSSSourceManagementView_Previews: PreviewProvider {
    static var previews: some View {
        RSSSourceManagementView()
    }
}
