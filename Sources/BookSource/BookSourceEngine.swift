import Foundation
import SwiftSoup
import JavaScriptCore

/// 书源解析引擎
class BookSourceEngine {
    static let shared = BookSourceEngine()
    
    private init() {}
    
    // 搜索书籍
    func search(keyword: String, bookSource: BookSource) async throws -> [SearchBook] {
        guard let searchUrl = bookSource.searchUrl else {
            throw BookSourceError.noSearchUrl
        }
        
        // 已移除详细调试打印，避免运行时输出过多信息
        
        // 解析URL和请求配置（支持逗号分隔的格式）
        // 查找 ",{" 或 ",[" 的组合位置（URL和配置的分隔符）
        var urlPart = searchUrl
        var requestConfig: [String: Any]?
        
        // 从后往前找 ",{" 或 ",["
        if let range = searchUrl.range(of: ",\\s*[\\{\\[]", options: [.regularExpression, .backwards]) {
            let commaIndex = range.lowerBound
            let jsonStartIndex = searchUrl.index(after: commaIndex)
            let potentialJsonPart = String(searchUrl[jsonStartIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            urlPart = String(searchUrl[..<commaIndex])
            // URL 部分与潜在 JSON 配置已解析
            
            // 尝试解析JSON配置
            if let configData = potentialJsonPart.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
                requestConfig = json
                // requestConfig 已解析
            }
        }
        
        // 先处理页码表达式
        var url = evaluateSimpleExpressions(in: urlPart, page: 1)
        // 页码表达式已处理
        
        // 替换body中的关键词（如果有配置）
        if var config = requestConfig {
            if let body = config["body"] as? String {
                let replacedBody = body
                    .replacingOccurrences(of: "{{key}}", with: keyword)
                    .replacingOccurrences(of: "{key}", with: keyword)
                config["body"] = replacedBody
                requestConfig = config
            }
        }
        
        // 替换URL中的关键词
        url = url
            .replacingOccurrences(of: "{{key}}", with: keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)
            .replacingOccurrences(of: "{key}", with: keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)
        
        // 关键词替换完毕
        
        // 处理相对URL（补全协议和域名）
        url = resolveUrl(url, baseUrl: bookSource.bookSourceUrl)
        // 最终 URL 已生成
        
        // 发起网络请求
        let html: String
        
        // 合并headers：优先使用searchUrl中的headers配置
        var finalHeaders = parseHeaders(bookSource.header) ?? [:]
            if let config = requestConfig, let searchHeaders = config["headers"] as? [String: String] {
            for (key, value) in searchHeaders {
                finalHeaders[key] = value
            }
            // 合并 searchUrl 中的 headers
        }
        
        if let config = requestConfig, let method = config["method"] as? String, method.uppercased() == "POST" {
            // 检查是否需要webView
            // webView 需求已检测（如需可在此处处理）
            
            // POST请求
            let body = config["body"] as? String ?? ""
            let bodyData = body.data(using: .utf8)
            html = try await NetworkManager.shared.post(url: url, body: bodyData, headers: finalHeaders)
        } else {
            // GET请求
            // 发起 GET 请求（headers 已合并）
            do {
                html = try await NetworkManager.shared.get(url: url, headers: finalHeaders)
                // 成功接收响应
            } catch {
                // 请求失败，向上抛出错误以便上层处理
                throw error
            }
        }
        
        // 解析搜索结果
        do {
            return try parseSearchResult(html: html, rule: bookSource.ruleSearch, baseUrl: bookSource.bookSourceUrl, bookSource: bookSource, keyword: keyword)
        } catch {
            // 解析搜索结果失败，错误上抛，已移除调试输出
            throw error
        }
    }
    
    // 获取书籍信息
    func getBookInfo(bookUrl: String, bookSource: BookSource) async throws -> Book {
        let html = try await NetworkManager.shared.get(url: bookUrl, headers: parseHeaders(bookSource.header))
        
        return try parseBookInfo(html: html, bookUrl: bookUrl, rule: bookSource.ruleBookInfo, bookSource: bookSource)
    }
    
    // 获取章节列表
    func getChapterList(book: Book, bookSource: BookSource) async throws -> [BookChapter] {
        let tocUrl = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl
        let html = try await NetworkManager.shared.get(url: tocUrl, headers: parseHeaders(bookSource.header))
        
        return try parseChapterList(html: html, bookUrl: book.bookUrl, rule: bookSource.ruleToc)
    }
    
    // 获取章节内容
    func getChapterContent(chapter: BookChapter, bookSource: BookSource) async throws -> String {
        // 章节内容获取入口（调试打印已移除）

        // 从bookUrl中提取bookid（bookUrl是正确的）
        var actualBookid: String?
        if let urlComponents = URLComponents(string: chapter.bookUrl),
           let queryItems = urlComponents.queryItems,
           let bookidItem = queryItems.first(where: { $0.name == "bookid" }),
           let bookid = bookidItem.value, bookid != "undefined" {
            actualBookid = bookid
            // 保存到 JS 缓存（静默执行）
            _ = try? JavaScriptEngine.shared.evaluate("java.put('bookid', '\(bookid)');", variables: [:])
        }

        // 检查chapter.url是否包含undefined，如果是则重新构建URL
        var finalUrl = chapter.url
        if finalUrl.contains("bookid=undefined"), let bookid = actualBookid {
            // 从chapter.url提取itemid
            if let urlComponents = URLComponents(string: chapter.url),
               let queryItems = urlComponents.queryItems,
               let itemidItem = queryItems.first(where: { $0.name == "itemid" }),
               let itemid = itemidItem.value {
                // 重新构建正确的URL
                var components = urlComponents
                components.queryItems = [
                    URLQueryItem(name: "bookid", value: bookid),
                    URLQueryItem(name: "itemid", value: itemid)
                ]
                if let newUrl = components.url?.absoluteString {
                    finalUrl = newUrl
                }
            }
        }

        // 修正章节URL，处理重复路径问题（如 /bqg/1099590//bqg/1099590/xxx.html）
        if finalUrl.hasPrefix("http") {
            // 检测并修复重复路径：提取协议后的部分，查找双斜杠后的重复路径
            if let range = finalUrl.range(of: "://") {
                let afterProtocol = String(finalUrl[range.upperBound...])
                // 如果存在双斜杠（非协议部分）
                if let doubleSlashIndex = afterProtocol.firstIndex(of: "/"),
                   afterProtocol[doubleSlashIndex...].contains("//") {
                    // 分割成域名和路径
                    let components = afterProtocol.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                    if components.count == 2 {
                        let domain = components[0]
                        var path = String(components[1])
                        
                        // 清理路径中的连续双斜杠，并检测重复路径段
                        // 例如 /bqg/1099590//bqg/1099590/xxx.html -> /bqg/1099590/xxx.html
                        if path.contains("//") {
                            let pathSegments = path.split(separator: "/", omittingEmptySubsequences: true)
                            var cleanedSegments: [String] = []
                            var i = 0
                            while i < pathSegments.count {
                                let segment = String(pathSegments[i])
                                cleanedSegments.append(segment)
                                
                                // 检查是否有连续重复的路径段
                                if i + 1 < pathSegments.count && 
                                   cleanedSegments.count >= 2 &&
                                   pathSegments[i + 1] == pathSegments[i - cleanedSegments.count + 1] {
                                    // 发现重复模式，跳过后续的重复段
                                    let repeatCount = cleanedSegments.count - 1
                                    var skip = 0
                                    for j in 0..<repeatCount {
                                        if i + 1 + j < pathSegments.count && 
                                           pathSegments[i + 1 + j] == pathSegments[i - repeatCount + 1 + j] {
                                            skip += 1
                                        } else {
                                            break
                                        }
                                    }
                                    if skip > 0 {
                                        i += skip
                                    }
                                }
                                i += 1
                            }
                            path = cleanedSegments.joined(separator: "/")
                            let urlProtocol = String(finalUrl[..<range.upperBound])
                            finalUrl = "\(urlProtocol)\(domain)/\(path)"
                        }
                    }
                }
            }
        } else {
            // 相对路径，使用resolveUrl拼接
            if let base = URL(string: chapter.bookUrl), let url = URL(string: finalUrl, relativeTo: base) {
                finalUrl = url.absoluteURL.absoluteString
            } else {
                finalUrl = chapter.bookUrl + finalUrl
            }
        }

        let html = try await NetworkManager.shared.get(url: finalUrl, headers: parseHeaders(bookSource.header))

        return try parseContent(html: html, rule: bookSource.ruleContent)
    }
    
    // MARK: - 解析方法
    
    // 解析搜索结果
    private func parseSearchResult(html: String, rule: SearchRule?, baseUrl: String, bookSource: BookSource, keyword: String) throws -> [SearchBook] {
        guard let rule = rule else {
            throw BookSourceError.noRule
        }
        
        var books: [SearchBook] = []
        
        // 获取书籍列表 - 支持JS规则
        guard let bookListRule = rule.bookList else {
            throw BookSourceError.noRule
        }
        
        // 检查是否是JS规则
        if containsJavaScript(bookListRule) {
            // 使用JavaScript解析
            return try parseSearchResultWithJS(html: html, rule: rule, baseUrl: baseUrl, bookSource: bookSource, keyword: keyword)
        }
        
        // 检查是否是JSON响应
        if html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            // 使用JSON解析
            return try parseSearchResultWithJSON(json: html, rule: rule, baseUrl: baseUrl, bookSource: bookSource)
        }
        
        // 使用CSS选择器解析（已移除详细调试输出）
        let doc = try SwiftSoup.parse(html)

        // 处理bookList规则中的@符号语法
        var elements: Elements
        if bookListRule.contains("@") {
            // 分离选择器和子选择器
            let parts = bookListRule.split(separator: "@", maxSplits: 1)
            if parts.count == 2 {
                var parentSelector = String(parts[0]).trimmingCharacters(in: .whitespaces)
                var childSelector = String(parts[1]).trimmingCharacters(in: .whitespaces)

                // 转换Android阅读选择器语法
                parentSelector = convertToStandardCSSSelector(parentSelector)
                childSelector = convertToStandardCSSSelector(childSelector)

                // 先选择父元素
                let parentElements = try doc.select(parentSelector)
                // 找到父元素

                // 从每个父元素中选择子元素
                elements = Elements()
                for parent in parentElements {
                    let children = try parent.select(childSelector)
                    for child in children {
                        try elements.add(child)
                    }
                }
                // 从父元素中找到子元素
            } else {
                // 转换选择器语法后直接选择
                let convertedSelector = convertToStandardCSSSelector(bookListRule)
                elements = try doc.select(convertedSelector)
                // 找到书籍元素
            }
            } else {
                // 转换选择器语法后直接选择
                let convertedSelector = convertToStandardCSSSelector(bookListRule)
                elements = try doc.select(convertedSelector)
                // 找到书籍元素
            }
        
        for element in elements {
            var book = SearchBook()
            
            do {
                // 解析书名
                if let nameRule = rule.name {
                    book.name = try parseRuleValue(element: element, rule: nameRule, html: html, baseUrl: baseUrl)
                }
                
                // 解析作者
                if let authorRule = rule.author {
                    book.author = try parseRuleValue(element: element, rule: authorRule, html: html, baseUrl: baseUrl)
                }
                
                // 解析书籍URL
                if let bookUrlRule = rule.bookUrl {
                    var bookUrl = try parseRuleValue(element: element, rule: bookUrlRule, html: html, baseUrl: baseUrl)
                    if !bookUrl.starts(with: "http") {
                        bookUrl = URL(string: baseUrl)?.appendingPathComponent(bookUrl).absoluteString ?? bookUrl
                    }
                    book.bookUrl = bookUrl
                }
                
                // 解析封面
                if let coverRule = rule.coverUrl {
                    var coverUrl = try parseRuleValue(element: element, rule: coverRule, html: html, baseUrl: baseUrl)
                    if !coverUrl.starts(with: "http") && !coverUrl.isEmpty {
                        coverUrl = URL(string: baseUrl)?.appendingPathComponent(coverUrl).absoluteString ?? coverUrl
                    }
                    book.coverUrl = coverUrl
                }
                
                // 解析简介
                if let introRule = rule.intro, !introRule.isEmpty {
                    book.intro = try parseRuleValue(element: element, rule: introRule, html: html, baseUrl: baseUrl)
                }
                
                // 解析分类
                if let kindRule = rule.kind {
                    book.kind = try parseRuleValue(element: element, rule: kindRule, html: html, baseUrl: baseUrl)
                }
                
                // 解析最新章节
                if let lastChapterRule = rule.lastChapter {
                    book.latestChapterTitle = try parseRuleValue(element: element, rule: lastChapterRule, html: html, baseUrl: baseUrl)
                }
                
                // 保存书源信息
                book.bookSourceUrl = bookSource.bookSourceUrl
                book.bookSourceName = bookSource.bookSourceName
                
                // 只添加有效的书籍（至少有书名和URL）
                if !book.name.isEmpty && !book.bookUrl.isEmpty {
                    books.append(book)
                }
            } catch {
                // 解析单个书籍元素失败，已移除调试输出，继续解析下一个元素
                continue
            }
        }
        
        return books
    }
    
    // 使用CSS选择器或JS规则解析单个值
    private func parseRuleValue(element: Element, rule: String, html: String, baseUrl: String) throws -> String {
        // 使用RuleAnalyzer拆分规则
        let segments = RuleAnalyzer.splitRule(rule)
        
        var result: String = try element.outerHtml()
        
        // 按顺序执行每个规则片段
        for segment in segments {
            let cleanRule = RuleAnalyzer.cleanRulePrefix(segment.content, mode: segment.mode)
            
            switch segment.mode {
            case .js:
                // JavaScript规则
                result = try JavaScriptEngine.shared.parseJSRule("@js:\(cleanRule)", html: result, baseUrl: baseUrl)
                
            case .json:
                // JSON规则（暂不支持，返回空）
                // JSON规则暂不支持
                return ""
                
            case .xpath:
                // XPath规则（暂不支持，返回空）
                // XPath规则暂不支持
                return ""
                
            case .regex:
                // 正则表达式规则（简化实现）
                if let regex = try? NSRegularExpression(pattern: cleanRule, options: []) {
                    let nsResult = result as NSString
                    let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsResult.length))
                    if let firstMatch = matches.first, firstMatch.numberOfRanges > 1 {
                        result = nsResult.substring(with: firstMatch.range(at: 1))
                    }
                }
                
            case .default:
                // CSS选择器解析
                // 支持属性选择：@attr, @src, @href等
                // 也支持子选择器：@p, @a 等（相当于空格）
                if cleanRule.contains("@") {
                    let parts = cleanRule.split(separator: "@", maxSplits: 1)
                    if parts.count == 2 {
                        var selector = String(parts[0]).trimmingCharacters(in: .whitespaces)
                        let attr = String(parts[1]).trimmingCharacters(in: .whitespaces)

                        // 转换Android阅读的选择器语法为标准CSS选择器
                        selector = convertToStandardCSSSelector(selector)

                        // 处理索引语法：.author.0 -> (.author, 0), a.1 -> (a, 1), a.-1 -> (a, -1)
                        var index: Int? = nil
                        if let lastDotIndex = selector.lastIndex(of: "."),
                           lastDotIndex != selector.startIndex {
                            let afterDot = selector[selector.index(after: lastDotIndex)...]
                            if let idx = Int(afterDot) {
                                index = idx
                                selector = String(selector[..<lastDotIndex])
                            }
                        }
                        
                        let doc = try SwiftSoup.parse(result)
                        
                        // 检查@后面是特殊属性（text/html）、HTML标签（子选择器）还是普通属性
                        let specialAttrs = ["text", "html"]
                        let htmlTags = ["p", "a", "div", "span", "li", "td", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "img", "ul", "ol", "dl", "dt", "dd"]
                        let isSpecialAttr = specialAttrs.contains(attr.lowercased())
                        let isSubSelector = htmlTags.contains(attr.lowercased())
                        
                        if isSpecialAttr {
                            // @text, @html 特殊处理
                            var targetElement: Element? = nil
                            if !selector.isEmpty {
                                let elements = try doc.select(selector)
                                if let idx = index {
                                    if idx >= 0 && idx < elements.count {
                                        targetElement = elements[idx]
                                    } else if idx < 0 && -idx <= elements.count {
                                        targetElement = elements[elements.count + idx]
                                    }
                                } else {
                                    targetElement = elements.first()
                                }
                            } else {
                                targetElement = try? doc.select("body").first()
                            }
                            
                            if let element = targetElement {
                                if attr.lowercased() == "text" {
                                    result = try element.text()
                                } else if attr.lowercased() == "html" {
                                    result = try element.html()
                                }
                            } else {
                                result = ""
                            }
                        } else if isSubSelector {
                            // @p, @a 等作为子选择器
                            var fullSelector = selector.isEmpty ? attr : "\(selector) \(attr)"
                            
                            // 先根据selector+index选择父元素
                            var parentElement: Element? = nil
                            if !selector.isEmpty {
                                let parentElements = try doc.select(selector)
                                if let idx = index {
                                    if idx >= 0 && idx < parentElements.count {
                                        parentElement = parentElements[idx]
                                    } else if idx < 0 && -idx <= parentElements.count {
                                        parentElement = parentElements[parentElements.count + idx]
                                    }
                                } else {
                                    parentElement = parentElements.first()
                                }
                            } else {
                                parentElement = try? doc.select("body").first()
                            }
                            
                            // 从父元素中选择子元素，返回所有匹配的HTML
                            if let parent = parentElement {
                                let childElements = try parent.select(attr)
                                result = try childElements.map { try $0.outerHtml() }.joined()
                            } else {
                                result = ""
                            }
                        } else {
                            // 作为属性选择器
                            if selector.isEmpty {
                                // 直接从当前元素获取属性
                                if let root = try? doc.select("body").first() {
                                    result = try root.attr(attr)
                                }
                            } else {
                                // 从子元素获取属性
                                let elements = try doc.select(selector)
                                var selected: Element? = nil
                                if let idx = index {
                                    if idx >= 0 && idx < elements.count {
                                        selected = elements[idx]
                                    } else if idx < 0 && -idx <= elements.count {
                                        selected = elements[elements.count + idx]
                                    }
                                } else {
                                    selected = elements.first()
                                }
                                
                                if let selected = selected {
                                    if attr == "text" {
                                        result = try selected.text()
                                    } else if attr == "html" {
                                        result = try selected.html()
                                    } else {
                                        // 获取属性值 - 优先使用abs:前缀获取绝对URL
                                            if attr == "href" || attr == "src" {
                                            // 先尝试获取原始属性值（相对路径）
                                            result = try selected.attr(attr)
                                            // 已静默属性调试输出
                                        } else {
                                            result = try selected.attr(attr)
                                        }
                                    }
                                } else {
                                    result = ""
                                }
                            }
                        }
                    }
                } else {
                    // 普通文本选择
                    // 处理索引语法
                    var selector = cleanRule
                    var index: Int? = nil
                    if let lastDotIndex = selector.lastIndex(of: "."),
                       lastDotIndex != selector.startIndex {
                        let afterDot = selector[selector.index(after: lastDotIndex)...]
                        if let idx = Int(afterDot) {
                            index = idx
                            selector = String(selector[..<lastDotIndex])
                        }
                    }
                    
                    let doc = try SwiftSoup.parse(result)
                    let elements = try doc.select(selector)
                    var selected: Element? = nil
                    if let idx = index {
                        if idx >= 0 && idx < elements.count {
                            selected = elements[idx]
                        } else if idx < 0 && -idx <= elements.count {
                            selected = elements[elements.count + idx]
                        }
                    } else {
                        selected = elements.first()
                    }
                    
                    if let selected = selected {
                        result = try selected.text()
                    }
                }
            }
        }
        
        return result
    }
    
    // 使用JSON解析搜索结果
    private func parseSearchResultWithJSON(json: String, rule: SearchRule, baseUrl: String, bookSource: BookSource) throws -> [SearchBook] {
        // 使用JSON解析（静默日志）
        
        guard let data = json.data(using: .utf8) else {
            throw BookSourceError.parseError
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BookSourceError.parseError
        }
        
        var books: [SearchBook] = []
        
        // 获取书籍数组
        guard let bookListRule = rule.bookList else {
            throw BookSourceError.noRule
        }
        
        // bookList 规则可能是 "data" 或 "$.data" 等
        let cleanRule = bookListRule.replacingOccurrences(of: "$.", with: "")
        guard let bookArray = jsonObject[cleanRule] as? [[String: Any]] else {
            // 无法从JSON中获取书籍数组
            return books
        }
        
        // 解析每本书
        for bookData in bookArray {
            var book = SearchBook()
            
            // 解析书名
            if let nameRule = rule.name {
                book.name = extractJSONValue(from: bookData, rule: nameRule)
            }
            
            // 解析作者
            if let authorRule = rule.author {
                book.author = extractJSONValue(from: bookData, rule: authorRule)
            }
            
            // 解析书籍URL
            if let bookUrlRule = rule.bookUrl {
                var bookUrl = bookUrlRule
                // 先处理模板变量 {{$.bookid}}
                bookUrl = replaceTemplates(in: bookUrl, with: bookData)
                // 如果没有模板，尝试作为字段名提取
                if bookUrl == bookUrlRule && !bookUrl.contains("{{") {
                    bookUrl = extractJSONValue(from: bookData, rule: bookUrlRule)
                }
                // 处理相对URL
                bookUrl = resolveUrl(bookUrl, baseUrl: baseUrl)
                book.bookUrl = bookUrl
            }
            
            // 解析封面
            if let coverRule = rule.coverUrl {
                var coverUrl = extractJSONValue(from: bookData, rule: coverRule)
                coverUrl = resolveUrl(coverUrl, baseUrl: baseUrl)
                book.coverUrl = coverUrl
            }
            
            // 解析简介
            if let introRule = rule.intro {
                book.intro = extractJSONValue(from: bookData, rule: introRule)
            }
            
            // 解析分类
            if let kindRule = rule.kind {
                var kind = kindRule
                // 处理模板: {{$.category}},{{$.status}}
                kind = replaceTemplates(in: kind, with: bookData)
                book.kind = kind
            }
            
            // 解析最新章节
            if let lastChapterRule = rule.lastChapter {
                book.latestChapterTitle = extractJSONValue(from: bookData, rule: lastChapterRule)
            }
            
            // 解析字数
            if let wordCountRule = rule.wordCount {
                book.wordCount = extractJSONValue(from: bookData, rule: wordCountRule)
            }
            
            // 保存书源URL
            book.bookSourceUrl = bookSource.bookSourceUrl
            book.bookSourceName = bookSource.bookSourceName
            
            books.append(book)
        }
        
        return books
    }
    
    // 从JSON对象中提取值
    private func extractJSONValue(from jsonObject: [String: Any], rule: String) -> String {
        // 移除 $. 前缀
        let cleanRule = rule.replacingOccurrences(of: "$.", with: "")
        
        if let value = jsonObject[cleanRule] {
            return "\(value)"
        }
        
        return ""
    }
    
    // 替换模板变量 {{$.field}}
    private func replaceTemplates(in text: String, with jsonObject: [String: Any]) -> String {
        var result = text
        
        // 匹配 {{$.xxx}} 或 {{xxx}}
        let pattern = "\\{\\{\\$?\\.?([^}]+)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        // 从后向前替换
        for match in matches.reversed() {
            if match.numberOfRanges >= 2 {
                let fullRange = match.range(at: 0)
                let fieldRange = match.range(at: 1)
                let fieldName = nsString.substring(with: fieldRange)
                
                if let value = jsonObject[fieldName] {
                    result = (result as NSString).replacingCharacters(in: fullRange, with: "\(value)")
                }
            }
        }
        
        return result
    }
    
    // 使用JavaScript解析搜索结果
    private func parseSearchResultWithJS(html: String, rule: SearchRule, baseUrl: String, bookSource: BookSource, keyword: String) throws -> [SearchBook] {
        guard let bookListRule = rule.bookList else {
            throw BookSourceError.noRule
        }
        
        // 使用JS解析bookList规则（静默日志）
        
        var books: [SearchBook] = []
        
        // 执行bookList JS规则获取书籍列表
        let jsEngine = JavaScriptEngine.shared
        
        do {
            // 使用RuleAnalyzer提取所有片段
            let segments = RuleAnalyzer.splitRule(bookListRule)
            
            // 规则分段数量（静默）
            for (index, segment) in segments.enumerated() {
                // 规则片段信息（已静默）
            }
            
            // 先处理非JS片段（如JSONPath）
            var currentResult: Any = html
            
            for segment in segments {
                if segment.mode == .json || segment.mode == .default {
                    // 处理JSONPath规则
                    let jsonPathRule = segment.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !jsonPathRule.isEmpty && jsonPathRule.hasPrefix("$") {
                        // 执行 JSONPath 规则（静默）
                        
                        // 确保输入是JSON字符串
                        if let jsonString = currentResult as? String {
                            // 使用JSONPath提取（简化版：只处理$.items[:10]这种格式）
                            if let jsonData = jsonString.data(using: .utf8),
                               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) {
                                
                                // 解析JSONPath
                                var extracted: Any = jsonObject
                                
                                if jsonPathRule.hasPrefix("$.") {
                                    let path = jsonPathRule.dropFirst(2) // 移除"$."
                                    let components = path.components(separatedBy: ".")
                                    
                                    for component in components {
                                        // 处理数组切片 items[:10]
                                        if component.contains("[") && component.contains("]") {
                                            let parts = component.split(separator: "[")
                                            let key = String(parts[0])
                                            
                                            // 提取数组
                                            if let dict = extracted as? [String: Any],
                                               let array = dict[key] as? [[String: Any]] {
                                                
                                                // 处理切片 [:10]
                                                let slicePart = parts[1].dropLast() // 移除"]"
                                                if slicePart.hasPrefix(":") {
                                                    let countStr = slicePart.dropFirst()
                                                    if let count = Int(countStr) {
                                                        extracted = Array(array.prefix(count))
                                                        // JSONPath切片成功（静默）
                                                    } else {
                                                        extracted = array
                                                    }
                                                } else {
                                                    extracted = array
                                                }
                                            }
                                        } else {
                                            // 普通属性访问
                                            if let dict = extracted as? [String: Any] {
                                                extracted = dict[component] ?? extracted
                                            }
                                        }
                                    }
                                }
                                
                                currentResult = extracted
                                // JSONPath 提取成功（静默）
                            }
                        }
                    }
                }
            }
            
            // 找到第一个JS片段
            guard let jsSegment = segments.first(where: { $0.mode == .js }) else {
                throw BookSourceError.noRule
            }
            
            let cleanRule = jsSegment.content
            // 清理后的规则（静默）
            
            // 将处理后的result传给JS
            let bookListResult = try jsEngine.evaluate(
                cleanRule,
                variables: ["result": currentResult, "baseUrl": baseUrl, "html": html, "page": 1, "key": keyword],
                jsLib: bookSource.jsLib
            )
            
            // JS执行成功（静默）
            
            // 处理返回值
            var actualResult = bookListResult
            
            // 如果返回的是字符串（可能是JSON字符串），尝试解析
            if bookListResult.isString, let jsonString = bookListResult.toString() {
                // 返回的是字符串（静默）
                
                // 尝试解析JSON字符串
                if let jsonData = jsonString.data(using: .utf8),
                   let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) {
                    // 将解析后的对象重新注入JSContext
                    let tempContext = JSContext()!
                    if let jsonArray = jsonObject as? [[String: Any]] {
                        // 成功解析为数组（静默）
                        actualResult = JSValue(object: jsonArray, in: tempContext)
                    } else {
                        // JSON解析结果不是数组（静默）
                    }
                }
            }
            
            // 检查返回类型
            if actualResult.isArray {
                // 如果是数组，遍历每个元素
                let length = actualResult.forProperty("length").toInt32()
                // 找到结果数量（静默）
                
                for i in 0..<length {
                    guard let bookItem = actualResult.atIndex(Int(i)) else { continue }
                    
                    var book = SearchBook()
                    
                    // 解析书名
                    if let nameRule = rule.name {
                        do {
                            book.name = try parseJSField(bookItem, rule: nameRule, baseUrl: baseUrl, bookSource: bookSource)
                            // 解析书名成功（静默）
                        } catch {
                            // 解析书名失败（静默）
                        }
                    }
                    
                    // 解析作者
                    if let authorRule = rule.author {
                        do {
                            book.author = try parseJSField(bookItem, rule: authorRule, baseUrl: baseUrl, bookSource: bookSource)
                            // 解析作者成功（静默）
                        } catch {
                            // 解析作者失败（静默）
                        }
                    }
                    
                    // 解析书籍URL
                    if let bookUrlRule = rule.bookUrl {
                        do {
                            var bookUrl = try parseJSField(bookItem, rule: bookUrlRule, baseUrl: baseUrl, bookSource: bookSource)
                            if !bookUrl.starts(with: "http") && !bookUrl.isEmpty {
                                bookUrl = URL(string: baseUrl)?.appendingPathComponent(bookUrl).absoluteString ?? bookUrl
                            }
                            book.bookUrl = bookUrl
                            // 解析 URL 成功（静默）
                        } catch {
                            // 解析 URL 失败（静默）
                        }
                    }
                    
                    // 解析封面
                    if let coverRule = rule.coverUrl {
                        do {
                            var coverUrl = try parseJSField(bookItem, rule: coverRule, baseUrl: baseUrl, bookSource: bookSource)
                            if !coverUrl.starts(with: "http") && !coverUrl.isEmpty {
                                coverUrl = URL(string: baseUrl)?.appendingPathComponent(coverUrl).absoluteString ?? coverUrl
                            }
                            book.coverUrl = coverUrl
                            // 解析封面成功（静默）
                        } catch {
                            // 解析封面失败（静默）
                        }
                    }
                    
                    // 解析简介
                    if let introRule = rule.intro {
                        do {
                            book.intro = try parseJSField(bookItem, rule: introRule, baseUrl: baseUrl, bookSource: bookSource)
                            // 解析简介成功（静默）
                        } catch {
                            // 解析简介失败（静默）
                        }
                    }
                    
                    // 解析分类
                    if let kindRule = rule.kind {
                        do {
                            book.kind = try parseJSField(bookItem, rule: kindRule, baseUrl: baseUrl, bookSource: bookSource)
                            // 解析分类成功（静默）
                        } catch {
                            // 解析分类失败（静默）
                        }
                    }
                    
                    // 解析最新章节
                    if let lastChapterRule = rule.lastChapter {
                        do {
                            book.latestChapterTitle = try parseJSField(bookItem, rule: lastChapterRule, baseUrl: baseUrl, bookSource: bookSource)
                            // 解析最新章节成功（静默）
                        } catch {
                            // 解析最新章节失败（静默）
                        }
                    }
                    
                    if !book.name.isEmpty && !book.bookUrl.isEmpty {
                        books.append(book)
                    }
                }
            } else {
                // 如果不是数组，可能是CSS选择器结果，尝试用原HTML解析
                // bookList 返回的不是数组，尝试 CSS 解析（静默）
                let doc = try SwiftSoup.parse(html)
                if let elements = try? doc.select(bookListRule) {
                    for element in elements {
                        var book = SearchBook()
                        
                        let elementHtml = try element.outerHtml()
                        
                        // 解析各字段
                        if let nameRule = rule.name {
                            book.name = try parseRuleValue(element: element, rule: nameRule, html: elementHtml, baseUrl: baseUrl)
                        }
                        
                        if let authorRule = rule.author {
                            book.author = try parseRuleValue(element: element, rule: authorRule, html: elementHtml, baseUrl: baseUrl)
                        }
                        
                        if let bookUrlRule = rule.bookUrl {
                            var bookUrl = try parseRuleValue(element: element, rule: bookUrlRule, html: elementHtml, baseUrl: baseUrl)
                            if !bookUrl.starts(with: "http") && !bookUrl.isEmpty {
                                bookUrl = URL(string: baseUrl)?.appendingPathComponent(bookUrl).absoluteString ?? bookUrl
                            }
                            book.bookUrl = bookUrl
                        }
                        
                        if let coverRule = rule.coverUrl {
                            var coverUrl = try parseRuleValue(element: element, rule: coverRule, html: elementHtml, baseUrl: baseUrl)
                            if !coverUrl.starts(with: "http") && !coverUrl.isEmpty {
                                coverUrl = URL(string: baseUrl)?.appendingPathComponent(coverUrl).absoluteString ?? coverUrl
                            }
                            book.coverUrl = coverUrl
                        }
                        
                        if let introRule = rule.intro {
                            book.intro = try parseRuleValue(element: element, rule: introRule, html: elementHtml, baseUrl: baseUrl)
                        }
                        
                        if let kindRule = rule.kind {
                            book.kind = try parseRuleValue(element: element, rule: kindRule, html: elementHtml, baseUrl: baseUrl)
                        }
                        
                        if let lastChapterRule = rule.lastChapter {
                            book.latestChapterTitle = try parseRuleValue(element: element, rule: lastChapterRule, html: elementHtml, baseUrl: baseUrl)
                        }
                        
                        // 保存书源URL
                        book.bookSourceUrl = bookSource.bookSourceUrl
                        book.bookSourceName = bookSource.bookSourceName
                        
                        if !book.name.isEmpty && !book.bookUrl.isEmpty {
                            books.append(book)
                        }
                    }
                }
            }
        } catch {
            // JS 解析失败（静默）
            throw error
        }
        
        return books
    }
    
    // 解析JS字段值
    private func parseJSField(_ jsValue: JSValue, rule: String, baseUrl: String, bookSource: BookSource) throws -> String {
        // 1. 处理 ## 分隔符（三段式：主规则##匹配正则##替换内容）
        let parts = rule.components(separatedBy: "##")
        var currentRule = rule
        var result = ""
        
        if parts.count >= 3 {
            // 第1部分：主规则（提取原始值）
            currentRule = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            // 第2部分：匹配正则（用于过滤）
            let matchPattern = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            // 第3部分：替换内容（JS代码）
            let replacement = parts[2...].joined(separator: "##").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 处理 ## 规则（静默）
            
            // 执行主规则获取原始值
            result = try parseJSFieldSegments(jsValue, rule: currentRule, baseUrl: baseUrl, bookSource: bookSource)
            
            // 应用正则过滤
            if !matchPattern.isEmpty, let regex = try? NSRegularExpression(pattern: matchPattern, options: []) {
                let nsResult = result as NSString
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(location: 0, length: nsResult.length),
                    withTemplate: ""
                )
                // 正则过滤后（静默）
            }
            
            // 执行JS替换
            if !replacement.isEmpty {
                result = try parseJSFieldSegments(result, rule: replacement, baseUrl: baseUrl, bookSource: bookSource)
            }
            
            return result
        }
        
        // 2. 正常规则处理（无##分隔符）
        return try parseJSFieldSegments(jsValue, rule: currentRule, baseUrl: baseUrl, bookSource: bookSource)
    }
    
    // 解析JS字段片段（链式执行）
    private func parseJSFieldSegments(_ element: Any, rule: String, baseUrl: String, bookSource: BookSource) throws -> String {
        // 先处理模板语法 {{$.field}}
        var processedRule = rule
        
        // 提取所有 {{...}} 模板并替换
        let templatePattern = #"\{\{([^}]+)\}\}"#
        if let regex = try? NSRegularExpression(pattern: templatePattern, options: []) {
            var result = processedRule
            var offset = 0
            
            let nsRule = processedRule as NSString
            let matches = regex.matches(in: processedRule, options: [], range: NSRange(location: 0, length: nsRule.length))
            
            for match in matches {
                if match.numberOfRanges >= 2 {
                    let originalRange = match.range(at: 0)
                    let templateContent = nsRule.substring(with: match.range(at: 1))
                    // 处理模板（静默）
                    
                    // 简单实现：$.field → 访问 JSON 字段
                    var fieldValue = ""
                    if templateContent.hasPrefix("$.") {
                        let fieldName = String(templateContent.dropFirst(2))
                        if let jsVal = element as? JSValue, let prop = jsVal.forProperty(fieldName) {
                            fieldValue = prop.toString()
                        }
                    } else if templateContent.hasPrefix("$..") {
                        // $..text 表示递归查找所有 text 字段
                        let fieldName = String(templateContent.dropFirst(3))
                        if let jsVal = element as? JSValue, let prop = jsVal.forProperty(fieldName) {
                            fieldValue = prop.toString()
                        }
                    } else if templateContent == "source.bookSourceUrl" || templateContent.contains("source.") {
                        // 特殊处理 source 变量
                        fieldValue = baseUrl
                    }
                    
                    // 替换模板
                    let adjustedRange = NSRange(location: originalRange.location + offset, length: originalRange.length)
                    let nsResult = result as NSString
                    result = nsResult.replacingCharacters(in: adjustedRange, with: fieldValue)
                    offset += fieldValue.count - originalRange.length
                }
            }
            processedRule = result
        }
        
        // 模板处理后（静默）
        
        // 使用RuleAnalyzer检查是否包含JS
        let segments = RuleAnalyzer.splitRule(processedRule)
        
        // 链式执行所有片段
        var currentResult: Any = element
        
        for (index, segment) in segments.enumerated() {
            // 执行片段（已静默输出）
            
            if segment.mode == .js {
                // 执行JS规则
                var cleanRule = segment.content.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 处理以 . 开头的链式调用（如 .replace()）
                if cleanRule.hasPrefix(".") {
                    // 将链式调用转换为完整表达式
                    cleanRule = "result\(cleanRule)"
                    // 转换链式调用（静默）
                }
                
                // 将当前结果转换为 JSValue
                let jsContext = JSContext()!
                var jsResult: JSValue
                
                if let jsVal = currentResult as? JSValue {
                    jsResult = jsVal
                } else if let str = currentResult as? String {
                    jsResult = JSValue(object: str, in: jsContext)
                } else {
                    jsResult = JSValue(object: currentResult, in: jsContext)
                }
                
                currentResult = try JavaScriptEngine.shared.evaluate(
                    cleanRule,
                    variables: ["result": jsResult, "baseUrl": baseUrl, "java": jsResult],
                    jsLib: bookSource.jsLib
                )
            } else if segment.mode == .default {
                // CSS 选择器或 JSON 字段访问
                let property = segment.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !property.isEmpty {
                    if let jsVal = element as? JSValue, let prop = jsVal.forProperty(property) {
                        currentResult = prop.toString()
                        // 访问字段（静默）
                    }
                }
            }
        }
        
        // 转换为字符串
        if let jsVal = currentResult as? JSValue {
            return jsVal.toString()
        } else {
            return String(describing: currentResult)
        }
    }
    
    // 解析书籍信息
    private func parseBookInfo(html: String, bookUrl: String, rule: BookInfoRule?, bookSource: BookSource) throws -> Book {
        guard let rule = rule else {
            throw BookSourceError.noRule
        }
        
        // 检查是否是JSON响应
        if html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return try parseBookInfoWithJSON(json: html, bookUrl: bookUrl, rule: rule, bookSource: bookSource)
        }
        
        let doc = try SwiftSoup.parse(html)
        
        // 临时存储变量的字典
        var variables: [String: String] = [:]
        
        // 处理init规则（@put保存变量）
        if let initRule = rule.`init` {
            variables = try parseInitRule(doc: doc, rule: initRule, html: html)
        }
        
        var name = ""
        var author = ""
        
        // 解析书名
        if let nameRule = rule.name {
            name = try parseFieldWithVariables(doc: doc, rule: nameRule, variables: variables, html: html)
        }
        
        // 解析作者
        if let authorRule = rule.author {
            author = try parseFieldWithVariables(doc: doc, rule: authorRule, variables: variables, html: html)
        }
        
        var book = Book(bookUrl: bookUrl, name: name, author: author)
        book.origin = bookSource.bookSourceUrl
        book.originName = bookSource.bookSourceName
        
        // 解析简介
        if let introRule = rule.intro {
            book.intro = try parseFieldWithVariables(doc: doc, rule: introRule, variables: variables, html: html)
        }
        
        // 解析封面
        if let coverRule = rule.coverUrl {
            var coverUrl = try parseFieldWithVariables(doc: doc, rule: coverRule, variables: variables, html: html)
            if !coverUrl.starts(with: "http") && !coverUrl.isEmpty {
                coverUrl = URL(string: bookSource.bookSourceUrl)?.appendingPathComponent(coverUrl).absoluteString ?? coverUrl
            }
            book.coverUrl = coverUrl
        }
        
        // 解析分类
        if let kindRule = rule.kind {
            book.kind = try parseFieldWithVariables(doc: doc, rule: kindRule, variables: variables, html: html)
        }
        
        // 解析目录URL
        if let tocRule = rule.tocUrl {
            if let tocElement = try doc.select(tocRule).first() {
                var tocUrl = try tocElement.attr("href")
                if !tocUrl.starts(with: "http") {
                    tocUrl = URL(string: bookUrl)?.appendingPathComponent(tocUrl).absoluteString ?? bookUrl
                }
                book.tocUrl = tocUrl
            }
        } else {
            book.tocUrl = bookUrl
        }
        
        return book
    }
    
    // 使用JSON解析书籍信息
    private func parseBookInfoWithJSON(json: String, bookUrl: String, rule: BookInfoRule, bookSource: BookSource) throws -> Book {
        // 使用JSON解析书籍信息（静默）
        
        guard let data = json.data(using: .utf8) else {
            throw BookSourceError.parseError
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BookSourceError.parseError
        }
        
        // 使用init规则定位数据
        var bookData: [String: Any] = jsonObject
        if let initRule = rule.`init` {
            let cleanRule = initRule.replacingOccurrences(of: "$.", with: "")
            if let dataDict = jsonObject[cleanRule] as? [String: Any] {
                bookData = dataDict
            }
        }
        
        // 解析基本信息
        let name = rule.name.map { extractJSONValue(from: bookData, rule: $0) } ?? ""
        let author = rule.author.map { extractJSONValue(from: bookData, rule: $0) } ?? ""
        
        var book = Book(bookUrl: bookUrl, name: name, author: author)
        book.origin = bookSource.bookSourceUrl
        book.originName = bookSource.bookSourceName
        
        // 解析简介
        if let introRule = rule.intro {
            book.intro = extractJSONValue(from: bookData, rule: introRule)
        }
        
        // 解析封面
        if let coverRule = rule.coverUrl {
            var coverUrl = extractJSONValue(from: bookData, rule: coverRule)
            coverUrl = resolveUrl(coverUrl, baseUrl: bookSource.bookSourceUrl)
            book.coverUrl = coverUrl
        }
        
        // 解析分类 - 支持模板
        if let kindRule = rule.kind {
            var kind = kindRule
            kind = replaceTemplates(in: kind, with: bookData)
            book.kind = kind
        }
        
        // 解析tocUrl - 可能包含JS
        if let tocRule = rule.tocUrl {
            if containsJavaScript(tocRule) {
                // 例如: "$.bookid\n<js>\njava.put('bookid',result);\n\"/catalog?bookid=\"+result;\n</js>"
                let segments = RuleAnalyzer.splitRule(tocRule)
                var fieldValue = ""
                var tocUrl = ""
                
                // 先提取字段值
                for segment in segments {
                    if segment.mode != .js && !segment.content.isEmpty {
                        fieldValue = extractJSONValue(from: bookData, rule: segment.content)
                        break
                    }
                }
                
                // 执行JS - 保存bookid并构造URL
                for segment in segments {
                    if segment.mode == .js {
                        // 将bookid传递给JS环境
                        let variables: [String: Any] = ["result": fieldValue]
                        if let jsResult = try? JavaScriptEngine.shared.evaluate(segment.content, variables: variables) {
                            tocUrl = String(describing: jsResult)
                        }
                        break
                    }
                }
                
                book.tocUrl = resolveUrl(tocUrl, baseUrl: bookSource.bookSourceUrl)
            } else {
                // 检查是否包含模板变量
                if tocRule.contains("{{") {
                    // 使用模板替换
                    var tocUrl = replaceTemplates(in: tocRule, with: bookData)
                    book.tocUrl = resolveUrl(tocUrl, baseUrl: bookSource.bookSourceUrl)
                } else {
                    // 作为字段名提取
                    var tocUrl = extractJSONValue(from: bookData, rule: tocRule)
                    book.tocUrl = resolveUrl(tocUrl, baseUrl: bookSource.bookSourceUrl)
                }
            }
        } else {
            book.tocUrl = bookUrl
        }
        
        // 书籍信息解析完成（静默）
        return book
    }
    
    // 解析章节列表
    private func parseChapterList(html: String, bookUrl: String, rule: TocRule?) throws -> [BookChapter] {
        guard let rule = rule, let chapterListRule = rule.chapterList else {
            throw BookSourceError.noRule
        }
        
        // 检查是否是JSON响应
        if html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            // 使用JSON解析
            return try parseChapterListWithJSON(json: html, bookUrl: bookUrl, rule: rule)
        }
        
        // 检查是否使用JS规则
        if containsJavaScript(chapterListRule) {
            // TODO: 实现完整的JS章节解析
            // 章节列表使用了JS规则，尝试基础解析（静默）
        }
        
        let doc = try SwiftSoup.parse(html)
        
        // 处理特殊的章节列表选择器（支持@子选择器）
        var elements: Elements
        if chapterListRule.contains("@") {
            // 使用parseRuleValue处理复杂选择器，然后重新解析结果
            let chapterHtml = try parseRuleValue(element: doc, rule: chapterListRule, html: html, baseUrl: bookUrl)
            let chapterDoc = try SwiftSoup.parse(chapterHtml)
            // 获取所有顶层元素
            elements = try chapterDoc.select("body > *")
        } else {
            elements = try doc.select(chapterListRule)
        }
        
        var chapters: [BookChapter] = []
        var index = 0
        
        for element in elements {
            var title = ""
            var url = ""
            
            // 解析章节名 - 支持JS规则和@text等特殊属性
            if let nameRule = rule.chapterName {
                if containsJavaScript(nameRule) {
                    let elementHtml = try element.outerHtml()
                    title = try JavaScriptEngine.shared.parseJSRule(nameRule, html: elementHtml, baseUrl: bookUrl)
                } else {
                    // 使用parseRuleValue支持@text等特殊属性
                    title = try parseRuleValue(element: element, rule: nameRule, html: html, baseUrl: bookUrl)
                }
            } else {
                title = try element.text()
            }
            
            // 解析章节URL - 支持JS规则和@href等属性
            if let urlRule = rule.chapterUrl {
                if containsJavaScript(urlRule) {
                    let elementHtml = try element.outerHtml()
                    url = try JavaScriptEngine.shared.parseJSRule(urlRule, html: elementHtml, baseUrl: bookUrl)
                } else {
                    // 使用parseRuleValue支持@href等属性
                    url = try parseRuleValue(element: element, rule: urlRule, html: html, baseUrl: bookUrl)
                    // parseRuleValue 返回的 url（静默）
                }
            } else {
                url = try element.attr("href")
                // 直接获取 href（静默）
            }
            
            // 处理相对URL，使用resolveUrl确保正确拼接
            if !url.isEmpty {
                // 章节 URL 解析（静默）
                url = resolveUrl(url, baseUrl: bookUrl)
            }
            
            if !title.isEmpty && !url.isEmpty {
                let chapter = BookChapter(url: url, title: title, bookUrl: bookUrl, index: index)
                chapters.append(chapter)
                index += 1
            }
        }
        
        return chapters
    }
    
    // 使用JSON解析章节列表
    private func parseChapterListWithJSON(json: String, bookUrl: String, rule: TocRule) throws -> [BookChapter] {
        // 使用JSON解析章节列表（静默）

        // 从bookUrl中提取bookid并保存到JS缓存
        // bookUrl格式可能是: http://69shuba.qingtian618.com/catalog?bookid=89023
        if let urlComponents = URLComponents(string: bookUrl),
           let queryItems = urlComponents.queryItems,
           let bookidItem = queryItems.first(where: { $0.name == "bookid" }),
           let bookid = bookidItem.value {
            // 从 URL 提取 bookid 并保存（静默）
            // 保存到JS环境的缓存中
            _ = try? JavaScriptEngine.shared.evaluate("java.put('bookid', '\(bookid)');", variables: [:])
        }

        guard let data = json.data(using: .utf8) else {
            throw BookSourceError.parseError
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BookSourceError.parseError
        }

        // JSON keys 已解析（静默）

        var chapters: [BookChapter] = []

        // 获取章节数组
        guard let chapterListRule = rule.chapterList else {
            throw BookSourceError.noRule
        }

        // chapterList 规则可能是 "data" 或 "$.data" 等
        let cleanRule = chapterListRule.replacingOccurrences(of: "$.", with: "")
        // 尝试获取章节数组（静默）

        guard let chapterArray = jsonObject[cleanRule] as? [[String: Any]] else {
            // 无法从JSON中获取章节数组（静默）
            if let value = jsonObject[cleanRule] {
                // 如果是字典，打印其所有键
                if let dict = value as? [String: Any] {
                    // data 是字典（静默），尝试在字典中查找数组字段
                    for (key, val) in dict {
                        if let arr = val as? [[String: Any]] {
                            // 找到数组字段（静默）
                        }
                    }
                } else {
                    // 实际的值（静默）
                }
            }
            return chapters
        }
        
        // 找到章节数量（静默）

        // 从 bookUrl 中提取 book_id（如果存在）
        var bookId: String? = nil
        if let urlComponents = URLComponents(string: bookUrl),
           let pathComponents = urlComponents.path.components(separatedBy: "/").last {
            bookId = pathComponents
            // 从 bookUrl 提取 book_id（静默）
        }

        // 解析每个章节
        for (index, chapterData) in chapterArray.enumerated() {
            var title = ""
            var url = ""

            // 解析章节名
            if let nameRule = rule.chapterName {
                // 检查是否包含正则替换规则（##）
                if nameRule.contains("##") {
                    let parts = nameRule.components(separatedBy: "##")
                    if parts.count >= 2 {
                        // 第一部分是字段名，第二部分是正则替换规则
                        let fieldRule = parts[0]
                        let regexRule = parts[1]

                        // 提取字段值
                        var fieldValue = extractJSONValue(from: chapterData, rule: fieldRule)

                        // 应用正则替换（移除匹配的内容）
                        let patterns = regexRule.components(separatedBy: "|")
                        for pattern in patterns {
                            if !pattern.isEmpty {
                                fieldValue = fieldValue.replacingOccurrences(
                                    of: pattern,
                                    with: "",
                                    options: .regularExpression
                                )
                            }
                        }

                        title = fieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        title = extractJSONValue(from: chapterData, rule: nameRule)
                    }
                } else {
                    title = extractJSONValue(from: chapterData, rule: nameRule)
                }

                // 章节信息（静默）
            }

            // 解析章节URL - 可能包含JS或模板变量
            if let urlRule = rule.chapterUrl {
                // 69书吧的chapterUrl规则: "$.itemid\n<js>\nlet bookid = java.get('bookid');\n`/content?bookid=${bookid}&itemid=${result}`;\n</js>"
                if containsJavaScript(urlRule) {
                    let segments = RuleAnalyzer.splitRule(urlRule)
                    var fieldValue = ""

                    // 先提取字段值
                    for segment in segments {
                        if segment.mode != .js && !segment.content.isEmpty {
                            fieldValue = extractJSONValue(from: chapterData, rule: segment.content)
                            break
                        }
                    }

                    // 执行JS构造URL
                    for segment in segments {
                        if segment.mode == .js {
                            let variables: [String: Any] = ["result": fieldValue]
                            if let jsResult = try? JavaScriptEngine.shared.evaluate(segment.content, variables: variables) {
                                url = String(describing: jsResult)
                            }
                            break
                        }
                    }
                } else if urlRule.contains("{{") {
                    // 包含模板变量，需要替换
                    // 创建合并的数据字典（章节数据 + book_id）
                    var mergedData = chapterData
                    if let bookId = bookId {
                        mergedData["book_id"] = bookId
                    }
                    url = replaceTemplates(in: urlRule, with: mergedData)
                } else {
                    url = extractJSONValue(from: chapterData, rule: urlRule)
                }
            }
            
            // 处理相对URL
            if !url.isEmpty {
                url = resolveUrl(url, baseUrl: bookUrl)
                
                let chapter = BookChapter(url: url, title: title, bookUrl: bookUrl, index: index)
                chapters.append(chapter)
            }
        }
        
        // 解析完成（静默）
        return chapters
    }
    
    // 解析正文内容
    private func parseContent(html: String, rule: ContentRule?) throws -> String {
        guard let rule = rule, let contentRule = rule.content else {
            throw BookSourceError.noRule
        }
        
        // 检查是否是JSON响应
        if html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return try parseContentWithJSON(json: html, rule: rule)
        }
        
        // 检查是否使用JS规则
        if containsJavaScript(contentRule) {
            let content = try JavaScriptEngine.shared.parseJSRule(contentRule, html: html, baseUrl: "")
            
            // 应用替换规则
            if let replaceRegex = rule.replaceRegex {
                return applyReplaceRule(content: content, replaceRule: replaceRegex)
            }
            
            return content
        }
        
        // CSS选择器解析
        let doc = try SwiftSoup.parse(html)
        
        // 使用parseRuleValue处理规则，支持@text/@html等特殊语法
        let dummyElement = try doc.select("html").first()!
        var content = try parseRuleValue(element: dummyElement, rule: contentRule, html: html, baseUrl: "")
        
        // 如果内容本身是HTML，需要提取纯文本并保留段落结构
        if !contentRule.contains("@text") {
            // 解析HTML内容
            let contentDoc = try SwiftSoup.parse(content)
            
            // 遍历所有<p>标签，提取文本并添加换行
            var paragraphs: [String] = []
            let pElements = try contentDoc.select("p")
            for p in pElements {
                let text = try p.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    paragraphs.append(text)
                }
            }
            
            // 如果没有<p>标签，尝试其他方式
            if paragraphs.isEmpty {
                // 处理<br>换行
                content = content.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
                content = content.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
                content = content.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
                content = try SwiftSoup.parse(content).text()
            } else {
                // 用双换行连接段落（段落间有空行）
                content = paragraphs.joined(separator: "\n\n")
            }
            
            // 清理首尾空白
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 应用替换规则
        if let replaceRegex = rule.replaceRegex {
            content = applyReplaceRule(content: content, replaceRule: replaceRegex)
        }
        
        return content
    }
    
    // 使用JSON解析章节内容
    private func parseContentWithJSON(json: String, rule: ContentRule) throws -> String {
        // 使用JSON解析章节内容（静默）
        
        guard let contentRule = rule.content else {
            // 没有 content 规则（静默）
            throw BookSourceError.noRule
        }
        
        guard let data = json.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // JSON 解析失败（静默）
            throw BookSourceError.parseError
        }
        
        // JSON 对象 keys（静默）
        
        // 简化逻辑：直接提取第一个非JS规则指定的字段
        let segments = RuleAnalyzer.splitRule(contentRule)
        var content = ""
        
        // 从JSON中提取字段值
        for segment in segments {
            if segment.mode != .js && !segment.content.isEmpty {
                let cleanRule = segment.content.replacingOccurrences(of: "$.", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                // 提取字段（静默）

                // 支持嵌套路径（如 data.content）
                let pathComponents = cleanRule.components(separatedBy: ".")
                var currentValue: Any? = jsonObject

                for component in pathComponents {
                    if let dict = currentValue as? [String: Any] {
                        currentValue = dict[component]
                    } else {
                        currentValue = nil
                        break
                    }
                }

                // 尝试从JSON中获取值
                if let value = currentValue {
                    // 找到值，类型（静默）

                    // 根据值的类型进行处理
                    if let stringValue = value as? String {
                        content = stringValue
                        // 提取到 String 内容（静默）
                    } else if let numberValue = value as? NSNumber {
                        content = numberValue.stringValue
                        // 提取到 Number 内容（静默）
                    } else {
                        // 对于其他类型，尝试转换为字符串
                        content = "\(value)"
                        // 其他类型转字符串（静默）
                    }
                } else {
                    // JSON 中不存在字段（静默）
                }
                break
            }
        }
        
        // 如果没有明确规则，尝试常见字段名
        if content.isEmpty {
            // 尝试默认字段（静默）
            if let dataField = jsonObject["data"] as? String {
                content = dataField
                // 使用默认 data 字段（静默）
            } else if let contentField = jsonObject["content"] as? String {
                content = contentField
                // 使用默认 content 字段（静默）
            } else {
                // data 和 content 字段都不是 String 类型（静默）
                if let anyData = jsonObject["data"] {
                    // data 字段类型已检测（静默）
                }
            }
        }
        
        if content.isEmpty || content == "Optional(<null>)" || content == "<null>" {
            // 未找到有效内容（静默）
            throw BookSourceError.parseError
        }
        
        // TODO: 后续可以添加JS处理功能
        // 现在先返回原始内容
        // 最终返回内容已生成（静默）
        return content
    }
    
    // 应用替换规则
    private func applyReplaceRule(content: String, replaceRule: String) -> String {
        // 简化的替换规则实现
        // 格式: ##正则##替换文本
        var result = content
        let rules = replaceRule.components(separatedBy: "\n")
        
        for rule in rules {
            if rule.hasPrefix("##") {
                let parts = rule.components(separatedBy: "##").filter { !$0.isEmpty }
                if parts.count >= 2 {
                    let pattern = parts[0]
                    let replacement = parts.count > 1 ? parts[1] : ""
                    result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
                }
            }
        }
        
        return result
    }
    
    // 解析请求头
    private func parseHeaders(_ headerStr: String?) -> [String: String]? {
        guard var headerStr = headerStr, !headerStr.isEmpty else {
            return nil
        }
        
        // 处理@js:开头的JavaScript代码
        if headerStr.hasPrefix("@js:") {
            // header 包含 JavaScript 代码（静默）
            // 移除@js:前缀
            headerStr = String(headerStr.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            // 暂时跳过JavaScript执行，直接返回nil
            // TODO: 实现JavaScript执行引擎
            // 跳过 JavaScript header 执行（静默）
            return nil
        }
        
        var headers: [String: String] = [:]
        
        // 尝试解析JSON格式的请求头
        if let data = headerStr.data(using: .utf8),
           let jsonHeaders = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return jsonHeaders
        }
        
        // 解析键值对格式
        let lines = headerStr.components(separatedBy: "\n")
        for line in lines {
            let parts = line.components(separatedBy: ":")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        return headers.isEmpty ? nil : headers
    }
    
    // 解析URL中的简单表达式（如 {{ ( page - 1 ) * 10 }}）
    private func evaluateSimpleExpressions(in url: String, page: Int) -> String {
        var result = url
        
        // 匹配 {{ expression }} 格式
        let pattern = "\\{\\{([^}]+)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }
        
        let nsString = url as NSString
        let matches = regex.matches(in: url, options: [], range: NSRange(location: 0, length: nsString.length))
        
        // 从后向前替换，避免索引问题
        for match in matches.reversed() {
            if match.numberOfRanges >= 2 {
                let fullRange = match.range(at: 0)
                let exprRange = match.range(at: 1)
                var expression = nsString.substring(with: exprRange).trimmingCharacters(in: .whitespaces)
                
                // 处理 Android 阅读特有的格式: key;java.put("key",key)
                // 提取分号前面的变量名
                var needsReplacement = false
                if expression.contains(";") {
                    let parts = expression.components(separatedBy: ";")
                    if let firstPart = parts.first?.trimmingCharacters(in: .whitespaces), !firstPart.isEmpty {
                        expression = firstPart
                        needsReplacement = true
                        // 从复合表达式中提取变量（静默）
                    }
                }
                
                // 检查是否是简单变量名（如 key, page）
                let simpleVarPattern = "^[a-zA-Z_][a-zA-Z0-9_]*$"
                if let varRegex = try? NSRegularExpression(pattern: simpleVarPattern, options: []),
                   varRegex.firstMatch(in: expression, options: [], range: NSRange(location: 0, length: expression.count)) != nil {
                    // 是简单变量名
                    if needsReplacement {
                        // 从复合表达式中提取的变量，需要替换为简单格式 {{variable}}
                        result = (result as NSString).replacingCharacters(in: fullRange, with: "{{\(expression)}}")
                    }
                    // 保留简单变量让后续替换
                    continue
                }
                
                // 计算简单的数学表达式
                if let value = evaluateMathExpression(expression, page: page) {
                    result = (result as NSString).replacingCharacters(in: fullRange, with: "\(value)")
                } else {
                    // 对于无法计算的表达式，尝试提取默认值
                    // 无法计算表达式，尝试使用默认值（静默）
                    
                    // 尝试提取默认值 (pattern: expression || defaultValue)
                    if let orIndex = expression.range(of: "||") {
                        let defaultPart = String(expression[orIndex.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if let defaultValue = Int(defaultPart) {
                            result = (result as NSString).replacingCharacters(in: fullRange, with: "\(defaultValue)")
                        } else {
                            // 默认值不是数字，可能是字符串，保留它
                            result = (result as NSString).replacingCharacters(in: fullRange, with: defaultPart)
                        }
                    } else {
                        // 无法处理，移除整个表达式（保留空字符串）
                        result = (result as NSString).replacingCharacters(in: fullRange, with: "")
                    }
                }
            }
        }
        
        // 处理简单的 {{page}} 和 {page} 变量
        result = result
            .replacingOccurrences(of: "{{page}}", with: "\(page)")
            .replacingOccurrences(of: "{page}", with: "\(page)")
        
        return result
    }
    
    // 计算简单的数学表达式（支持 page 变量）
    private func evaluateMathExpression(_ expr: String, page: Int) -> Int? {
        var expression = expr.trimmingCharacters(in: .whitespaces)

        // 检查是否包含Android阅读特有的语法（这些无法用NSExpression计算）
        let unsupportedPatterns = [
            "Map\\(",           // Map("key")
            "java\\.",          // java.put(), java.get()
            "cookie\\.",        // cookie.removeCookie()
            "source\\.",        // source.getKey(), source.getVariable()
            "getKey\\(",        // getKey()
            "getVariable\\(",   // getVariable()
            "removeCookie\\(",  // removeCookie()
            "encodeURI",        // encodeURI()
            "JSON\\.",          // JSON.stringify()
            "String\\(",        // String()
            "org\\.jsoup",      // org.jsoup.Jsoup
            "\\.split\\(",      // .split(",")
            "\\.match\\(",      // .match()
            "\\.replace\\(",    // .replace()
            "\\|\\|",           // || 默认值运算符
            "\\?",              // 三元运算符
            ":",                // 三元运算符的:
            "let ",             // JavaScript变量声明
            "var ",             // JavaScript变量声明
            "const ",           // JavaScript变量声明
            "=>",               // 箭头函数
            "function",         // 函数声明
            "\\$\\{",           // 模板字符串
        ]

        for pattern in unsupportedPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: expression, options: [], range: NSRange(location: 0, length: expression.count)) != nil {
                // 表达式包含不支持的语法（静默）
                return nil
            }
        }

        // 检查是否只包含安全的字符（数字、运算符、括号、page变量）
        let safePattern = "^[0-9+\\-*/()\\s]*$|^[0-9+\\-*/()\\spage]*$"
        let testExpression = expression.replacingOccurrences(of: "page", with: "")
        if let safeRegex = try? NSRegularExpression(pattern: safePattern, options: []),
           safeRegex.firstMatch(in: testExpression, options: [], range: NSRange(location: 0, length: testExpression.count)) == nil {
            // 表达式包含不安全的字符（静默）
            return nil
        }

        // 替换 page 变量
        expression = expression.replacingOccurrences(of: "page", with: "\(page)")

        // 移除所有空格
        expression = expression.replacingOccurrences(of: " ", with: "")

        // 最后检查：确保只包含数字和运算符
        let finalPattern = "^[0-9+\\-*/()]+$"
        if let finalRegex = try? NSRegularExpression(pattern: finalPattern, options: []),
           finalRegex.firstMatch(in: expression, options: [], range: NSRange(location: 0, length: expression.count)) == nil {
            // 表达式格式不正确（静默）
            return nil
        }

        // 尝试使用 NSExpression 计算
        do {
            let exp = NSExpression(format: expression)
            if let result = exp.expressionValue(with: nil, context: nil) as? NSNumber {
                return result.intValue
            }
        } catch {
            // NSExpression 计算失败（静默）
            return nil
        }

        // 无法计算表达式（静默）
        return nil
    }

    // 转换Android阅读的选择器语法为标准CSS选择器
    private func convertToStandardCSSSelector(_ selector: String) -> String {
        var result = selector

        // 处理 class.xxx -> .xxx
        result = result.replacingOccurrences(of: #"class\.([a-zA-Z0-9_-]+)"#, with: ".$1", options: .regularExpression)

        // 处理 id.xxx -> #xxx
        result = result.replacingOccurrences(of: #"id\.([a-zA-Z0-9_-]+)"#, with: "#$1", options: .regularExpression)

        // 处理 tag.xxx -> xxx
        result = result.replacingOccurrences(of: #"tag\.([a-zA-Z0-9_-]+)"#, with: "$1", options: .regularExpression)

        return result
    }

    // 解析相对URL（补全协议和域名）
    private func resolveUrl(_ urlString: String, baseUrl: String) -> String {
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespaces)
        let trimmedBase = baseUrl.trimmingCharacters(in: .whitespaces)
        
        // resolveUrl 输入参数（静默）
        
        // 如果已经是完整URL，直接返回
        if trimmedUrl.hasPrefix("http://") || trimmedUrl.hasPrefix("https://") {
            return trimmedUrl
        }
        
        // 解析基础URL
        guard let base = URL(string: trimmedBase) else {
            // 无法解析 baseUrl（静默）
            return trimmedUrl
        }
        
        // 如果是相对路径，组合基础URL
        if trimmedUrl.hasPrefix("/") {
            // 绝对路径（相对于域名根目录）
            if let scheme = base.scheme, let host = base.host {
                let port = base.port.map { ":\($0)" } ?? ""
                return "\(scheme)://\(host)\(port)\(trimmedUrl)"
            }
        } else {
            // 相对路径（相对于当前目录）
            if let resolved = URL(string: trimmedUrl, relativeTo: base) {
                return resolved.absoluteString
            }
        }
        
        return trimmedUrl
    }
    
    // 检查规则是否包含JavaScript代码
    private func containsJavaScript(_ rule: String) -> Bool {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("@js:") || 
               trimmed.hasPrefix("<js>") || 
               trimmed.contains("<js>") ||
               trimmed.hasPrefix("{{") && trimmed.contains("@js")
    }
}

// 搜索书籍结果
struct SearchBook: Identifiable {
    let id = UUID()
    var name: String = ""
    var author: String = ""
    var bookUrl: String = ""
    var coverUrl: String?
    var intro: String?
    var kind: String?
    var latestChapterTitle: String?
    var wordCount: String?
    var bookSourceUrl: String = "" // 书源URL，用于后续获取详情
    var bookSourceName: String = "" // 书源名称，用于显示
}

// MARK: - @put/@get 变量支持
extension BookSourceEngine {
    /// 解析init规则，提取并保存变量
    private func parseInitRule(doc: Document, rule: String, html: String) throws -> [String: String] {
        var variables: [String: String] = [:]
        
        // 检查是否是@put规则
        if rule.hasPrefix("@put:") {
            let content = String(rule.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            // 解析 {key1:"selector1", key2:"selector2"} 格式
            if content.hasPrefix("{") && content.hasSuffix("}") {
                let jsonContent = content.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                // 简单解析键值对
                let pairs = jsonContent.components(separatedBy: ",")
                for pair in pairs {
                    let parts = pair.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        var selector = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                        // 移除引号
                        selector = selector.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        
                        // 解析CSS选择器
                        do {
                            let value = try parseRuleValue(element: doc, rule: selector, html: html, baseUrl: "")
                            variables[key] = value
                            // 保存变量（静默）
                        } catch {
                            // 解析变量失败（静默）
                        }
                    }
                }
            }
        }
        
        return variables
    }
    
    /// 解析字段，支持@get从变量获取
    private func parseFieldWithVariables(doc: Document, rule: String, variables: [String: String], html: String) throws -> String {
        // 检查是否是@get规则
        if rule.hasPrefix("@get:") {
            let varName = String(rule.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
            if let value = variables[varName] {
                return value
            }
            // 变量未找到（静默）
            return ""
        }
        
        // 普通CSS选择器
        return try parseRuleValue(element: doc, rule: rule, html: html, baseUrl: "")
    }
}

// 书源错误
enum BookSourceError: Error, LocalizedError {
    case noSearchUrl
    case noRule
    case parseError
    case unsupportedJavaScript(sourceName: String)
    case unsupportedJavaScriptInRule
    
    var errorDescription: String? {
        switch self {
        case .noSearchUrl:
            return "书源未配置搜索地址"
        case .noRule:
            return "书源规则不完整"
        case .parseError:
            return "解析失败"
        case .unsupportedJavaScript(let sourceName):
            return "书源【\(sourceName)】使用了JavaScript规则，当前版本暂不支持。请选择使用纯HTML/CSS选择器的书源。"
        case .unsupportedJavaScriptInRule:
            return "该书源的解析规则使用了JavaScript代码（<js>标签），当前版本暂不支持。请选择使用纯CSS选择器的书源。"
        }
    }
}
