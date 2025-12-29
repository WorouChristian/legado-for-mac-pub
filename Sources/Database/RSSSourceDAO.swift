import Foundation
import GRDB

/// RSS订阅源数据库操作
class RSSSourceDAO {
    private let dbManager = DatabaseManager.shared

    // MARK: - 订阅源操作

    /// 保存订阅源
    func save(_ source: RSSSource) throws {
        print("💾 [DAO] 保存订阅源: \(source.sourceName), URL: \(source.sourceUrl)")
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO rss_sources (
                    sourceUrl, sourceName, sourceIcon, sourceGroup,
                    enabled, enableJs, enabledCookieJar, customOrder, lastUpdateTime,
                    ruleArticles, ruleNextUrl, ruleTitle, ruleLink,
                    ruleDescription, ruleContent, ruleImage, rulePubDate,
                    header, articleStyle, singleUrl, sortUrl, loadWithBaseUrl
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    source.sourceUrl,
                    source.sourceName,
                    source.sourceIcon,
                    source.sourceGroup,
                    source.enabled ? 1 : 0,
                    source.enableJs ? 1 : 0,
                    source.enabledCookieJar ? 1 : 0,
                    source.customOrder,
                    source.lastUpdateTime,
                    source.ruleArticles,
                    source.ruleNextUrl,
                    source.ruleTitle,
                    source.ruleLink,
                    source.ruleDescription,
                    source.ruleContent,
                    source.ruleImage,
                    source.rulePubDate,
                    source.header,
                    source.articleStyle,
                    source.singleUrl ? 1 : 0,
                    source.sortUrl,
                    source.loadWithBaseUrl ? 1 : 0
                ]
            )
            print("✅ [DAO] SQL执行成功")
        }
    }

    /// 批量保存订阅源
    func saveAll(_ sources: [RSSSource]) throws {
        for source in sources {
            try save(source)
        }
    }

    /// 删除订阅源
    func delete(sourceUrl: String) throws {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            try db.execute(sql: "DELETE FROM rss_sources WHERE sourceUrl = ?", arguments: [sourceUrl])
        }
    }

    /// 获取所有订阅源
    func getAllSources() throws -> [RSSSource] {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM rss_sources ORDER BY customOrder, sourceName")
            print("📊 [DAO] 查询到 \(rows.count) 行数据")

            let sources = rows.compactMap { row -> RSSSource? in
                let source = RSSSource(from: row)
                if source == nil {
                    print("❌ [DAO] RSSSource初始化失败")
                }
                return source
            }

            print("✅ [DAO] 成功转换 \(sources.count) 个订阅源")
            return sources
        }
    }

    /// 获取启用的订阅源
    func getEnabledSources() throws -> [RSSSource] {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM rss_sources WHERE enabled = 1 ORDER BY customOrder, sourceName")
            return rows.compactMap { RSSSource(from: $0) }
        }
    }

    /// 根据URL获取订阅源
    func getSource(by url: String) throws -> RSSSource? {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        return try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM rss_sources WHERE sourceUrl = ?", arguments: [url]) else {
                return nil
            }
            return RSSSource(from: row)
        }
    }

    /// 根据分组获取订阅源
    func getSources(by group: String) throws -> [RSSSource] {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM rss_sources WHERE sourceGroup = ? ORDER BY customOrder, sourceName", arguments: [group])
            return rows.compactMap { RSSSource(from: $0) }
        }
    }

    /// 更新订阅源启用状态
    func updateEnabled(sourceUrl: String, enabled: Bool) throws {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            try db.execute(sql: "UPDATE rss_sources SET enabled = ? WHERE sourceUrl = ?", arguments: [enabled, sourceUrl])
        }
    }

    /// 更新最后更新时间
    func updateLastUpdateTime(sourceUrl: String, time: Int64) throws {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            try db.execute(sql: "UPDATE rss_sources SET lastUpdateTime = ? WHERE sourceUrl = ?", arguments: [time, sourceUrl])
        }
    }

    // MARK: - 文章操作

    /// 保存文章
    func save(_ article: Article) throws {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO articles (
                    link, title, sourceUrl, description, content,
                    imageUrl, pubDate, isRead, isFavorite, readTime
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    article.link,
                    article.title,
                    article.sourceUrl,
                    article.description,
                    article.content,
                    article.imageUrl,
                    article.pubDate.map { Int64($0.timeIntervalSince1970) },
                    article.isRead ? 1 : 0,
                    article.isFavorite ? 1 : 0,
                    article.readTime.map { Int64($0.timeIntervalSince1970) }
                ]
            )
        }
    }

    /// 批量保存文章
    func saveAll(_ articles: [Article]) throws {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            for article in articles {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO articles (
                        link, title, sourceUrl, description, content,
                        imageUrl, pubDate, isRead, isFavorite, readTime
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        article.link,
                        article.title,
                        article.sourceUrl,
                        article.description,
                        article.content,
                        article.imageUrl,
                        article.pubDate.map { Int64($0.timeIntervalSince1970) },
                        article.isRead ? 1 : 0,
                        article.isFavorite ? 1 : 0,
                        article.readTime.map { Int64($0.timeIntervalSince1970) }
                    ]
                )
            }
        }
    }

    /// 删除文章
    func deleteArticle(link: String) throws {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            try db.execute(sql: "DELETE FROM articles WHERE link = ?", arguments: [link])
        }
    }

    /// 删除订阅源的所有文章
    func deleteArticles(sourceUrl: String) throws {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            try db.execute(sql: "DELETE FROM articles WHERE sourceUrl = ?", arguments: [sourceUrl])
        }
    }

    /// 获取订阅源的文章列表
    func getArticles(sourceUrl: String, limit: Int = 100, offset: Int = 0) throws -> [Article] {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM articles
                WHERE sourceUrl = ?
                ORDER BY pubDate DESC, link DESC
                LIMIT ? OFFSET ?
                """,
                arguments: [sourceUrl, limit, offset]
            )
            return rows.compactMap { Article(from: $0) }
        }
    }

    /// 获取所有文章（按时间倒序）
    func getAllArticles(limit: Int = 100, offset: Int = 0) throws -> [Article] {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM articles
                ORDER BY pubDate DESC, link DESC
                LIMIT ? OFFSET ?
                """,
                arguments: [limit, offset]
            )
            return rows.compactMap { Article(from: $0) }
        }
    }

    /// 获取未读文章
    func getUnreadArticles(limit: Int = 100) throws -> [Article] {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM articles
                WHERE isRead = 0
                ORDER BY pubDate DESC, link DESC
                LIMIT ?
                """,
                arguments: [limit]
            )
            return rows.compactMap { Article(from: $0) }
        }
    }

    /// 获取收藏的文章
    func getFavoriteArticles() throws -> [Article] {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM articles
                WHERE isFavorite = 1
                ORDER BY pubDate DESC, link DESC
                """)
            return rows.compactMap { Article(from: $0) }
        }
    }

    /// 根据链接获取文章
    func getArticle(by link: String) throws -> Article? {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        return try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM articles WHERE link = ?", arguments: [link]) else {
                return nil
            }
            return Article(from: row)
        }
    }

    /// 标记文章为已读
    func markAsRead(link: String) throws {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        let now = Int64(Date().timeIntervalSince1970)
        try db.write { db in
            try db.execute(sql: "UPDATE articles SET isRead = 1, readTime = ? WHERE link = ?", arguments: [now, link])
        }
    }

    /// 标记文章为未读
    func markAsUnread(link: String) throws {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            try db.execute(sql: "UPDATE articles SET isRead = 0, readTime = NULL WHERE link = ?", arguments: [link])
        }
    }

    /// 切换收藏状态
    func toggleFavorite(link: String) throws {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            try db.execute(sql: "UPDATE articles SET isFavorite = NOT isFavorite WHERE link = ?", arguments: [link])
        }
    }

    /// 更新文章内容
    func updateContent(link: String, content: String) throws {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            try db.execute(sql: "UPDATE articles SET content = ? WHERE link = ?", arguments: [content, link])
        }
    }

    /// 获取文章数量统计
    func getArticleCount(sourceUrl: String? = nil) throws -> Int {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        return try db.read { db in
            if let sourceUrl = sourceUrl {
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles WHERE sourceUrl = ?", arguments: [sourceUrl]) ?? 0
            } else {
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles") ?? 0
            }
        }
    }

    /// 获取未读文章数量
    func getUnreadCount(sourceUrl: String? = nil) throws -> Int {
        guard let db = dbManager.getDatabase() else {
            throw DatabaseError.notInitialized
        }

        return try db.read { db in
            if let sourceUrl = sourceUrl {
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles WHERE sourceUrl = ? AND isRead = 0", arguments: [sourceUrl]) ?? 0
            } else {
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles WHERE isRead = 0") ?? 0
            }
        }
    }
}

/// 数据库错误
enum DatabaseError: Error, LocalizedError {
    case notInitialized
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "数据库未初始化"
        case .invalidData:
            return "无效的数据"
        }
    }
}
