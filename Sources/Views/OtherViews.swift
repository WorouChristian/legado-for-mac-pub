import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Logo和标题
                VStack(spacing: 16) {
                    Image(systemName: "book.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.accentColor)

                    Text("Legado for macOS")
                        .font(.title)
                        .bold()

                    Text("版本 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                Divider()
                    .padding(.horizontal, 40)

                // 作者信息
                VStack(alignment: .leading, spacing: 16) {
                    Text("作者")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Kequan@linux.do")
                            .font(.body)
                    }

                    Text("觉得这个工作不错的话，可以用 LDC 赞助一下我哦！")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Link(destination: URL(string: "https://credit.kequan.me/")!) {
                        HStack {
                            Image(systemName: "heart.fill")
                            Text("赞助支持")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 500, alignment: .leading)
                .padding(.horizontal, 40)

                Divider()
                    .padding(.horizontal, 40)

                // 项目信息
                VStack(alignment: .leading, spacing: 16) {
                    Text("项目信息")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "link.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("基于 Legado 开源阅读")
                                .font(.body)
                        }

                        Link(destination: URL(string: "https://github.com/gedoor/legado")!) {
                            HStack {
                                Image(systemName: "arrow.up.forward.circle")
                                Text("https://github.com/gedoor/legado")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundColor(.accentColor)
                            Text("本项目即将开源")
                                .font(.body)
                        }

                        Link(destination: URL(string: "https://github.com/Kequans/legado-for-mac")!) {
                            HStack {
                                Image(systemName: "arrow.up.forward.circle")
                                Text("https://github.com/Kequans/legado-for-mac")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 500, alignment: .leading)
                .padding(.horizontal, 40)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DiscoverView: View {
    var body: some View {
        VStack {
            Text("发现")
                .font(.title)
            Text("功能开发中...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RSSView: View {
    var body: some View {
        RSSSourceManagementView()
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HStack {
                Text("设置")
                    .font(.title2)
                    .bold()

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // 标签页选择器
            HStack(spacing: 0) {
                Button(action: { selectedTab = 0 }) {
                    Text("通用")
                        .font(.system(size: 14))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(selectedTab == 0 ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: { selectedTab = 1 }) {
                    Text("网络")
                        .font(.system(size: 14))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(selectedTab == 1 ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // 内容区域
            Group {
                if selectedTab == 0 {
                    GeneralSettingsView()
                } else {
                    NetworkSettingsView()
                }
            }
        }
        .frame(width: 550, height: 450)
    }
}

struct GeneralSettingsView: View {
    @State private var preloadCountText: String
    @State private var showError = false
    @State private var errorMessage = ""

    init() {
        let loadedConfig = MainAppConfig.load()
        _preloadCountText = State(initialValue: String(loadedConfig.preloadChapterCount))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 阅读缓存
                VStack(alignment: .leading, spacing: 12) {
                    Text("阅读缓存")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Text("预加载章节数:")
                            .frame(width: 110, alignment: .leading)

                        TextField("", text: $preloadCountText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onSubmit {
                                savePreloadCount()
                            }

                        Text("章")
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    Text("范围: 10-50章，预加载后续章节以加快阅读速度")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if showError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button("清理过期缓存") {
                        Task {
                            do {
                                try ChapterContentDAO().cleanExpiredCache()
                                print("✅ 缓存清理完成")
                            } catch {
                                print("❌ 缓存清理失败: \(error)")
                            }
                        }
                    }
                }

                Divider()

                // 数据管理
                VStack(alignment: .leading, spacing: 12) {
                    Text("数据")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Button("备份数据") {
                            // TODO: 实现备份功能
                        }

                        Button("恢复数据") {
                            // TODO: 实现恢复功能
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .onDisappear {
            savePreloadCount()
        }
    }

    private func savePreloadCount() {
        guard let count = Int(preloadCountText) else {
            showError = true
            errorMessage = "请输入有效的数字"
            // 恢复为当前配置值
            preloadCountText = String(MainAppConfig.load().preloadChapterCount)
            return
        }

        if count < 10 || count > 50 {
            showError = true
            errorMessage = "数值必须在 10-50 之间"
            preloadCountText = String(MainAppConfig.load().preloadChapterCount)
            return
        }

        showError = false
        var newConfig = MainAppConfig.load()
        newConfig.preloadChapterCount = count
        newConfig.save()
        print("✅ 预加载章节数已设置为: \(count)")
    }
}

struct NetworkSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 网络请求
                VStack(alignment: .leading, spacing: 12) {
                    Text("网络请求")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("User-Agent")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("", text: .constant(""))
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("超时时间(秒)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("", value: .constant(30), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }

                Divider()

                // 代理设置
                VStack(alignment: .leading, spacing: 12) {
                    Text("代理设置")
                        .font(.headline)

                    Toggle("启用代理", isOn: .constant(false))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("代理地址")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("", text: .constant(""))
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("代理端口")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("", text: .constant(""))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
    }
}

struct BookSourceEditView: View {
    let bookSource: BookSource?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text(bookSource == nil ? "添加书源" : "编辑书源")
                .font(.title2)
                .bold()
            
            Text("书源编辑功能待实现")
                .foregroundColor(.secondary)
                .padding()
            
            Spacer()
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                
                Spacer()
                
                Button("保存") {
                    // TODO: 保存逻辑
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 700, height: 600)
    }
}

// 预览仅在 Xcode 中使用，CLI 构建移除
