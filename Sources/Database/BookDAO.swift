import Foundation
import GRDB

/// 书籍数据访问对象
class BookDAO {
    private let db = DatabaseManager.shared.getDatabase()
    
    // 插入或更新书籍
    func save(_ book: Book) throws {
        try db?.write { db in
            // 先检查是否已存在
            let exists = try Book.fetchOne(db, sql: "SELECT * FROM books WHERE bookUrl = ?", arguments: [book.bookUrl])
            
            if exists != nil {
                print("⚠️ 书籍已存在于书架，更新: \(book.name)")
                // 更新已存在的书籍（包括阅读进度）
                try db.execute(sql: """
                    UPDATE books SET
                        name = ?, author = ?, kind = ?, coverUrl = ?, localCoverPath = ?, intro = ?,
                        origin = ?, originName = ?, latestChapterTitle = ?, tocUrl = ?,
                        durChapterTitle = ?, durChapterIndex = ?, durChapterPos = ?, durChapterTime = ?,
                        lastCheckTime = ?, skipDetailPage = ?
                    WHERE bookUrl = ?
                """, arguments: [
                    book.name, book.author, book.kind, book.coverUrl, book.localCoverPath, book.intro,
                    book.origin, book.originName, book.latestChapterTitle, book.tocUrl,
                    book.durChapterTitle, book.durChapterIndex, book.durChapterPos, book.durChapterTime,
                    book.lastCheckTime, book.skipDetailPage,
                    book.bookUrl
                ])
            } else {
                print("✅ 新增书籍到书架: \(book.name)")
                // 插入新书籍
                try db.execute(sql: """
                    INSERT INTO books (
                        bookUrl, tocUrl, origin, originName, name, author,
                        kind, customTag, coverUrl, customCoverUrl, localCoverPath, intro, customIntro,
                        type, "group", latestChapterTitle, latestChapterTime,
                        lastCheckTime, lastCheckCount, totalChapterNum,
                        durChapterTitle, durChapterIndex, durChapterPos, durChapterTime,
                        wordCount, canUpdate, "order", originOrder, variable, skipDetailPage
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    book.bookUrl, book.tocUrl, book.origin, book.originName,
                    book.name, book.author, book.kind, book.customTag,
                    book.coverUrl, book.customCoverUrl, book.localCoverPath, book.intro, book.customIntro,
                    book.type.rawValue, book.group, book.latestChapterTitle, book.latestChapterTime,
                    book.lastCheckTime, book.lastCheckCount, book.totalChapterNum,
                    book.durChapterTitle, book.durChapterIndex, book.durChapterPos, book.durChapterTime,
                    book.wordCount, book.canUpdate, book.order, book.originOrder, book.variable, book.skipDetailPage
                ])
            }
        }
    }
    
    // 获取所有书籍
    func getAll() throws -> [Book] {
        guard let db = db else { return [] }
        return try db.read { db in
            try Book.fetchAll(db, sql: "SELECT * FROM books ORDER BY lastCheckTime DESC")
        }
    }
    
    // 根据URL获取书籍
    func get(bookUrl: String) throws -> Book? {
        guard let db = db else { return nil }
        return try db.read { db in
            try Book.fetchOne(db, sql: "SELECT * FROM books WHERE bookUrl = ?", arguments: [bookUrl])
        }
    }
    
    // 删除书籍
    func delete(bookUrl: String) throws {
        try db?.write { db in
            try db.execute(sql: "DELETE FROM books WHERE bookUrl = ?", arguments: [bookUrl])
        }
    }
    
    // 获取最近阅读的书籍
    func getLastRead() throws -> Book? {
        guard let db = db else { return nil }
        return try db.read { db in
            try Book.fetchOne(db, sql: "SELECT * FROM books ORDER BY durChapterTime DESC LIMIT 1")
        }
    }
}

// MARK: - Book GRDB 扩展
extension Book: FetchableRecord, PersistableRecord {
    enum Columns {
        static let bookUrl = Column("bookUrl")
        static let name = Column("name")
        static let author = Column("author")
    }
    
    init(row: Row) {
        self.bookUrl = row["bookUrl"]
        self.tocUrl = row["tocUrl"]
        self.origin = row["origin"]
        self.originName = row["originName"]
        self.name = row["name"]
        self.author = row["author"]
        self.kind = row["kind"]
        self.customTag = row["customTag"]
        self.coverUrl = row["coverUrl"]
        self.customCoverUrl = row["customCoverUrl"]
        self.localCoverPath = row["localCoverPath"]
        self.intro = row["intro"]
        self.customIntro = row["customIntro"]
        self.type = BookType(rawValue: row["type"]) ?? .text
        self.group = row["group"]
        self.latestChapterTitle = row["latestChapterTitle"]
        self.latestChapterTime = row["latestChapterTime"]
        self.lastCheckTime = row["lastCheckTime"]
        self.lastCheckCount = row["lastCheckCount"]
        self.totalChapterNum = row["totalChapterNum"]
        self.durChapterTitle = row["durChapterTitle"]
        self.durChapterIndex = row["durChapterIndex"]
        self.durChapterPos = row["durChapterPos"]
        self.durChapterTime = row["durChapterTime"]
        self.wordCount = row["wordCount"]
        self.canUpdate = row["canUpdate"]
        self.order = row["order"]
        self.originOrder = row["originOrder"]
        self.variable = row["variable"]
        self.skipDetailPage = row["skipDetailPage"]
    }
    
    func encode(to container: inout PersistenceContainer) {
        container["bookUrl"] = bookUrl
        container["tocUrl"] = tocUrl
        container["origin"] = origin
        container["originName"] = originName
        container["name"] = name
        container["author"] = author
        container["kind"] = kind
        container["customTag"] = customTag
        container["coverUrl"] = coverUrl
        container["customCoverUrl"] = customCoverUrl
        container["localCoverPath"] = localCoverPath
        container["intro"] = intro
        container["customIntro"] = customIntro
        container["type"] = type.rawValue
        container["group"] = group
        container["latestChapterTitle"] = latestChapterTitle
        container["latestChapterTime"] = latestChapterTime
        container["lastCheckTime"] = lastCheckTime
        container["lastCheckCount"] = lastCheckCount
        container["totalChapterNum"] = totalChapterNum
        container["durChapterTitle"] = durChapterTitle
        container["durChapterIndex"] = durChapterIndex
        container["durChapterPos"] = durChapterPos
        container["durChapterTime"] = durChapterTime
        container["wordCount"] = wordCount
        container["canUpdate"] = canUpdate
        container["order"] = order
        container["originOrder"] = originOrder
        container["variable"] = variable
        container["skipDetailPage"] = skipDetailPage
    }
}
