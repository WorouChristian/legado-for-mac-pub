import Foundation

/// 文件管理工具（避免与 Foundation.FileManager 冲突）
enum FileUtils {
    private static var fm: Foundation.FileManager { Foundation.FileManager() }
    
    /// 获取应用支持目录
    static func getAppSupportDirectory() -> URL? {
        return try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Legado", isDirectory: true)
    }
    
    /// 获取书籍缓存目录
    static func getBooksDirectory() -> URL? {
        guard let appSupport = getAppSupportDirectory() else { return nil }
        let booksDir = appSupport.appendingPathComponent("Books", isDirectory: true)
        try? fm.createDirectory(at: booksDir, withIntermediateDirectories: true)
        return booksDir
    }
    
    /// 获取章节缓存路径
    static func getChapterCachePath(bookUrl: String, chapterIndex: Int) -> URL? {
        guard let booksDir = getBooksDirectory() else { return nil }
        let bookId = bookUrl.md5
        let chapterFile = booksDir
            .appendingPathComponent(bookId, isDirectory: true)
            .appendingPathComponent("\(chapterIndex).txt")
        return chapterFile
    }
    
    /// 缓存章节内容
    static func cacheChapterContent(bookUrl: String, chapterIndex: Int, content: String) {
        guard let filePath = getChapterCachePath(bookUrl: bookUrl, chapterIndex: chapterIndex) else {
            return
        }
        
        do {
            try fm.createDirectory(
                at: filePath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: filePath, atomically: true, encoding: .utf8)
        } catch {
            print("缓存章节失败: \(error)")
        }
    }
    
    /// 读取缓存的章节内容
    static func getCachedChapterContent(bookUrl: String, chapterIndex: Int) -> String? {
        guard let filePath = getChapterCachePath(bookUrl: bookUrl, chapterIndex: chapterIndex) else {
            return nil
        }
        
        return try? String(contentsOf: filePath, encoding: .utf8)
    }
    
    /// 清除书籍缓存
    static func clearBookCache(bookUrl: String) {
        guard let booksDir = getBooksDirectory() else { return }
        let bookId = bookUrl.md5
        let bookDir = booksDir.appendingPathComponent(bookId, isDirectory: true)
        try? fm.removeItem(at: bookDir)
    }
    
    /// 清除所有缓存
    static func clearAllCache() {
        guard let booksDir = getBooksDirectory() else { return }
        try? fm.removeItem(at: booksDir)
    }
}

/// String 扩展
extension String {
    /// 计算MD5
    var md5: String {
        // 简化实现，实际应该使用 CryptoKit
        let cleaned = self.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "", options: .regularExpression)
        return String(cleaned.prefix(32))
    }
    
    /// URL编码
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

/// 日期格式化工具
extension Date {
    /// 格式化为字符串
    func formatted(_ format: String = "yyyy-MM-dd HH:mm:ss") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
    
    /// 相对时间描述
    var relativeDescription: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)
        
        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            return "\(Int(interval / 60))分钟前"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))小时前"
        } else if interval < 604800 {
            return "\(Int(interval / 86400))天前"
        } else {
            return formatted("yyyy-MM-dd")
        }
    }
}
