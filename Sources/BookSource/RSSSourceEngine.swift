import Foundation

/// 订阅源解析引擎
class RSSSourceEngine {
    private let jsEngine: JavaScriptEngine
    private let bookSourceEngine: BookSourceEngine

    init() {
        self.jsEngine = JavaScriptEngine.shared
        self.bookSourceEngine = BookSourceEngine.shared
    }

    // MARK: - 主解析方法

    /// 解析订阅源，返回文章列表
    func parse(source: RSSSource) async throws -> [Article] {
        print("📰 开始解析订阅源: \(source.sourceName)")

        // 1. 检查是否是标准RSS
        if source.isStandardRSS {
            print("📰 使用标准RSS解析")
            return try await parseStandardRSS(source: source)
        }

        // 2. 使用自定义规则解析
        print("📰 使用自定义规则解析")
        return try await parseCustomRules(source: source)
    }

    // MARK: - 标准RSS解析

    /// 解析标准RSS源（RSS 2.0, Atom）
    private func parseStandardRSS(source: RSSSource) async throws -> [Article] {
        // 获取RSS内容
        let content = try await fetchContent(url: source.sourceUrl, headers: source.headerMap)

        // 尝试解析RSS 2.0
        if let articles = try? parseRSS20(content: content, sourceUrl: source.sourceUrl) {
            print("✅ RSS 2.0解析成功，找到 \(articles.count) 篇文章")
            return articles
        }

        // 尝试解析Atom
        if let articles = try? parseAtom(content: content, sourceUrl: source.sourceUrl) {
            print("✅ Atom解析成功，找到 \(articles.count) 篇文章")
            return articles
        }

        throw RSSError.unsupportedFormat
    }

    /// 解析RSS 2.0格式
    private func parseRSS20(content: String, sourceUrl: String) throws -> [Article] {
        var articles: [Article] = []

        // 使用正则表达式提取item
        let itemPattern = "<item[^>]*>(.*?)</item>"
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators]) else {
            throw RSSError.parseError("无法创建正则表达式")
        }

        let nsContent = content as NSString
        let matches = itemRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            let itemContent = nsContent.substring(with: match.range(at: 1))

            // 提取标题
            guard let title = extractTag(from: itemContent, tag: "title") else { continue }

            // 提取链接
            guard let link = extractTag(from: itemContent, tag: "link") else { continue }

            // 提取描述
            let description = extractTag(from: itemContent, tag: "description")

            // 提取发布时间
            let pubDateStr = extractTag(from: itemContent, tag: "pubDate")
            let pubDate = pubDateStr.flatMap { parseRFC822Date($0) }

            // 提取图片（可能在enclosure或description中）
            var imageUrl: String?
            if let enclosureUrl = extractAttribute(from: itemContent, tag: "enclosure", attribute: "url") {
                imageUrl = enclosureUrl
            } else if let desc = description {
                imageUrl = extractImageFromHTML(desc)
            }

            let article = Article(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
                imageUrl: imageUrl,
                pubDate: pubDate,
                sourceUrl: sourceUrl
            )

            articles.append(article)
        }

        return articles
    }

    /// 解析Atom格式
    private func parseAtom(content: String, sourceUrl: String) throws -> [Article] {
        var articles: [Article] = []

        // 使用正则表达式提取entry
        let entryPattern = "<entry[^>]*>(.*?)</entry>"
        guard let entryRegex = try? NSRegularExpression(pattern: entryPattern, options: [.dotMatchesLineSeparators]) else {
            throw RSSError.parseError("无法创建正则表达式")
        }

        let nsContent = content as NSString
        let matches = entryRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            let entryContent = nsContent.substring(with: match.range(at: 1))

            // 提取标题
            guard let title = extractTag(from: entryContent, tag: "title") else { continue }

            // 提取链接（Atom的link是属性）
            guard let link = extractAttribute(from: entryContent, tag: "link", attribute: "href") else { continue }

            // 提取摘要或内容
            let summary = extractTag(from: entryContent, tag: "summary")
            let content = extractTag(from: entryContent, tag: "content")
            let description = content ?? summary

            // 提取发布时间
            let publishedStr = extractTag(from: entryContent, tag: "published") ?? extractTag(from: entryContent, tag: "updated")
            let pubDate = publishedStr.flatMap { parseISO8601Date($0) }

            let article = Article(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: pubDate,
                sourceUrl: sourceUrl
            )

            articles.append(article)
        }

        return articles
    }

    // MARK: - 自定义规则解析

    /// 使用自定义规则解析
    private func parseCustomRules(source: RSSSource) async throws -> [Article] {
        var allArticles: [Article] = []
        var currentUrl: String? = source.sourceUrl

        // 循环处理分页
        while let url = currentUrl {
            print("📰 解析页面: \(url)")

            // 获取页面内容
            let content = try await fetchContent(url: url, headers: source.headerMap)

            // 解析文章列表
            guard let ruleArticles = source.ruleArticles, !ruleArticles.isEmpty else {
                throw RSSError.missingRule("ruleArticles")
            }

            // 简化实现：暂时只支持CSS选择器
            // TODO: 完整实现需要集成BookSourceEngine的parseRule方法
            print("⚠️ 自定义规则解析功能需要集成BookSourceEngine")
            print("⚠️ 当前仅支持标准RSS源")
            break
        }

        print("✅ 订阅源解析完成，共找到 \(allArticles.count) 篇文章")
        return allArticles
    }

    /// 解析单篇文章（暂不实现，需要集成BookSourceEngine）
    private func parseArticle(element: [String: Any], source: RSSSource, baseUrl: String) throws -> Article {
        // TODO: 完整实现需要集成BookSourceEngine的parseRule方法
        throw RSSError.parseError("自定义规则解析功能待实现")
    }

    /// 解析下一页URL
    private func parseNextUrl(rule: String, content: String, baseUrl: String, source: RSSSource) async throws -> String? {
        // 如果规则包含JavaScript
        if rule.contains("<js>") || rule.hasPrefix("@js:") {
            let result = try jsEngine.evaluate(
                rule,
                variables: ["baseUrl": baseUrl, "result": content]
            )

            if result.isNull || result.isUndefined {
                return nil
            }

            let nextUrl = result.toString()
            return nextUrl?.isEmpty == false ? nextUrl : nil
        }

        // 暂不支持其他规则
        return nil
    }

    // MARK: - 内容获取

    /// 获取文章内容（用于无描述规则的源）
    func fetchArticleContent(article: Article, source: RSSSource) async throws -> String {
        guard let ruleContent = source.ruleContent, !ruleContent.isEmpty else {
            // 没有内容规则，返回空字符串（将打开网页）
            return ""
        }

        // 获取文章页面内容
        let content = try await fetchContent(url: article.link, headers: source.headerMap)

        // TODO: 完整实现需要集成BookSourceEngine的parseRule方法
        print("⚠️ 内容规则解析功能待实现")
        return content
    }

    // MARK: - 辅助方法

    /// 获取网页内容
    private func fetchContent(url: String, headers: [String: String]?) async throws -> String {
        return try await NetworkManager.shared.get(url: url, headers: headers)
    }

    /// 从XML中提取标签内容
    private func extractTag(from content: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let nsContent = content as NSString
        guard let match = regex.firstMatch(in: content, range: NSRange(location: 0, length: nsContent.length)) else {
            return nil
        }

        let value = nsContent.substring(with: match.range(at: 1))
        return decodeHTMLEntities(value)
    }

    /// 从XML中提取属性值
    private func extractAttribute(from content: String, tag: String, attribute: String) -> String? {
        let pattern = "<\(tag)[^>]*\(attribute)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsContent = content as NSString
        guard let match = regex.firstMatch(in: content, range: NSRange(location: 0, length: nsContent.length)) else {
            return nil
        }

        return nsContent.substring(with: match.range(at: 1))
    }

    /// 从HTML中提取图片URL
    private func extractImageFromHTML(_ html: String) -> String? {
        let pattern = "<img[^>]*src=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsHtml = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHtml.length)) else {
            return nil
        }

        return nsHtml.substring(with: match.range(at: 1))
    }

    /// 解析RFC822日期格式（RSS 2.0）
    private func parseRFC822Date(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: dateString)
    }

    /// 解析ISO8601日期格式（Atom）
    private func parseISO8601Date(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }

    /// 解析通用日期格式
    private func parseDate(_ dateString: String) -> Date? {
        // 尝试多种日期格式
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy/MM/dd HH:mm:ss"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy/MM/dd"
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        // 尝试RFC822和ISO8601
        if let date = parseRFC822Date(dateString) {
            return date
        }

        if let date = parseISO8601Date(dateString) {
            return date
        }

        return nil
    }

    /// 解析HTML实体
    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        return result
    }

    /// 解析相对URL
    private func resolveUrl(_ urlString: String, baseUrl: String) -> String {
        // 如果已经是完整URL，直接返回
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return urlString
        }

        // 解析baseUrl
        guard let base = URL(string: baseUrl) else {
            return urlString
        }

        // 处理相对URL
        if urlString.hasPrefix("/") {
            // 绝对路径
            let scheme = base.scheme ?? "https"
            let host = base.host ?? ""
            return "\(scheme)://\(host)\(urlString)"
        } else {
            // 相对路径
            let basePath = base.deletingLastPathComponent().absoluteString
            return basePath + "/" + urlString
        }
    }
}

// MARK: - 错误类型

enum RSSError: Error, LocalizedError {
    case unsupportedFormat
    case parseError(String)
    case missingRule(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "不支持的RSS格式"
        case .parseError(let message):
            return "解析错误: \(message)"
        case .missingRule(let rule):
            return "缺少必填规则: \(rule)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}
