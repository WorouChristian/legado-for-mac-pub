import SwiftUI
import AppKit

/// 支持缓存的封面图片视图
struct CachedCoverImage: View {
    let book: Binding<Book>
    let width: CGFloat
    let height: CGFloat
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.5)
                            } else {
                                Image(systemName: "book")
                                    .font(width > 80 ? .title : .body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            loadCover()
        }
        .onChange(of: book.wrappedValue.displayCover) { _ in
            loadCover()
        }
    }
    
    private func loadCover() {
        let currentBook = book.wrappedValue
        let coverPath = currentBook.displayCover
        
        guard !coverPath.isEmpty else { return }
        
        // 如果已经是本地路径，直接加载
        if coverPath.hasPrefix("/") {
            if let loadedImage = NSImage(contentsOfFile: coverPath) {
                self.image = loadedImage
                CoverCacheManager.shared.cacheImageToMemory(image: loadedImage, for: coverPath)
            }
            return
        }
        
        // 检查内存缓存
        if let cachedImage = CoverCacheManager.shared.getMemoryCachedImage(for: coverPath) {
            self.image = cachedImage
            return
        }
        
        // 异步加载封面
        guard let coverUrl = currentBook.coverUrl, !coverUrl.isEmpty else { return }
        
        isLoading = true
        Task {
            do {
                let localPath = try await CoverCacheManager.shared.getCoverImage(
                    coverUrl: coverUrl,
                    bookUrl: currentBook.bookUrl
                )
                
                // 更新book的localCoverPath
                await MainActor.run {
                    var updatedBook = book.wrappedValue
                    updatedBook.localCoverPath = localPath
                    book.wrappedValue = updatedBook
                    
                    // 保存到数据库
                    try? BookDAO().save(updatedBook)
                    
                    // 加载图片
                    if let loadedImage = NSImage(contentsOfFile: localPath) {
                        self.image = loadedImage
                        CoverCacheManager.shared.cacheImageToMemory(image: loadedImage, for: localPath)
                    }
                    
                    isLoading = false
                }
            } catch {
                print("❌ [CachedCoverImage] 加载封面失败: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}
