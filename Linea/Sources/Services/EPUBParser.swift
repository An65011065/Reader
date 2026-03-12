import Foundation
import ZIPFoundation

// MARK: - Parser

class EPUBParser {

    enum ParseError: Error, LocalizedError {
        case invalidEPUB, missingOPF, missingContent
        var errorDescription: String? {
            switch self {
            case .invalidEPUB:  return "Not a valid EPUB file."
            case .missingOPF:   return "Could not locate package document."
            case .missingContent: return "No readable content found."
            }
        }
    }

    func parse(url: URL) throws -> EPUBBook {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Unzip
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { throw ParseError.invalidEPUB }

        for entry in archive where entry.type == .file {
            let dest = tmpDir.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: dest)
        }

        // container.xml → OPF path
        let containerURL = tmpDir.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else { throw ParseError.invalidEPUB }
        let opfRelPath = try parseContainerXML(at: containerURL)
        let opfURL     = tmpDir.appendingPathComponent(opfRelPath)
        let opfBase    = opfURL.deletingLastPathComponent()

        // Parse OPF
        let opfResult = try parseOPF(at: opfURL, baseURL: opfBase)

        // Cover image
        var coverData: Data?
        if let coverHref = opfResult.coverHref {
            coverData = try? Data(contentsOf: opfBase.appendingPathComponent(coverHref))
        }

        // Parse TOC (NCX or nav.xhtml)
        var tocEntries: [TOCEntry] = []
        if let ncxHref = opfResult.ncxHref {
            let ncxURL = opfBase.appendingPathComponent(ncxHref)
            tocEntries = (try? parseNCX(at: ncxURL)) ?? []
        }
        if tocEntries.isEmpty, let navHref = opfResult.navHref {
            let navURL = opfBase.appendingPathComponent(navHref)
            tocEntries = (try? parseNavXHTML(at: navURL)) ?? []
        }

        // Build chapters: match TOC entries to spine items, extract text
        let chapters = buildChapters(
            spineItems: opfResult.spineItems,
            manifest: opfResult.manifest,
            tocEntries: tocEntries,
            baseURL: opfBase
        )

        guard !chapters.isEmpty else { throw ParseError.missingContent }

        return EPUBBook(
            title: opfResult.title,
            author: opfResult.author,
            coverImageData: coverData,
            chapters: chapters
        )
    }

    // MARK: - container.xml

    private func parseContainerXML(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let p = SimpleAttrParser(data: data, targetTag: "rootfile", targetAttr: "full-path")
        p.parse()
        guard let path = p.result else { throw ParseError.missingOPF }
        return path
    }

    // MARK: - OPF

    private struct OPFResult {
        let title: String
        let author: String
        let coverHref: String?
        let ncxHref: String?
        let navHref: String?
        let manifest: [String: ManifestItem]   // id → item
        let spineItems: [String]               // ordered idrefs
    }

    struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
    }

    private func parseOPF(at url: URL, baseURL: URL) throws -> OPFResult {
        let data = try Data(contentsOf: url)
        let p = OPFXMLParser(data: data)
        p.parse()

        // Resolve cover: look for cover item in manifest
        var coverHref: String?
        if let coverId = p.coverId, let item = p.manifest[coverId] {
            coverHref = item.href
        } else {
            // Fallback: find an image item with "cover" in id or href
            coverHref = p.manifest.values.first(where: {
                ($0.mediaType.hasPrefix("image/")) &&
                ($0.id.lowercased().contains("cover") || $0.href.lowercased().contains("cover"))
            })?.href
        }

        // NCX
        var ncxHref: String?
        if let ncxId = p.ncxId, let item = p.manifest[ncxId] {
            ncxHref = item.href
        } else {
            ncxHref = p.manifest.values.first(where: { $0.mediaType.contains("ncx") })?.href
        }

        // nav (EPUB3)
        let navHref = p.manifest.values.first(where: {
            $0.mediaType.contains("xhtml") &&
            ($0.id.lowercased().contains("nav") || $0.href.lowercased().contains("nav"))
        })?.href

        return OPFResult(
            title: p.title ?? "Untitled",
            author: p.author ?? "Unknown Author",
            coverHref: coverHref,
            ncxHref: ncxHref,
            navHref: navHref,
            manifest: p.manifest,
            spineItems: p.spineIdrefs
        )
    }

    // MARK: - NCX (EPUB2 TOC)

    struct TOCEntry {
        let title: String
        let href: String          // path relative to OPF base, may include fragment
        let playOrder: Int
        let nestingLevel: Int
    }

    private func parseNCX(at url: URL) throws -> [TOCEntry] {
        let data = try Data(contentsOf: url)
        let p = NCXParser(data: data)
        p.parse()
        return p.entries
    }

    // MARK: - nav.xhtml (EPUB3 TOC)

    private func parseNavXHTML(at url: URL) throws -> [TOCEntry] {
        let data = try Data(contentsOf: url)
        let p = NavXHTMLParser(data: data)
        p.parse()
        return p.entries
    }

    // MARK: - Build chapters

    private func buildChapters(
        spineItems: [String],
        manifest: [String: ManifestItem],
        tocEntries: [TOCEntry],
        baseURL: URL
    ) -> [EPUBBook.Chapter] {

        // Build a map: normalized file path → TOC entries that point to it
        var tocByFile: [String: [TOCEntry]] = [:]
        for entry in tocEntries {
            let filePath = entry.href.components(separatedBy: "#").first ?? entry.href
            let normalized = filePath.removingPercentEncoding ?? filePath
            tocByFile[normalized, default: []].append(entry)
        }

        var chapters: [EPUBBook.Chapter] = []
        var playOrder = 1

        for idref in spineItems {
            guard let item = manifest[idref],
                  item.mediaType.contains("html") else { continue }

            let itemURL = baseURL.appendingPathComponent(item.href)
            guard let (text, html) = try? extractTextAndHTML(from: itemURL),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let fileKey = item.href.removingPercentEncoding ?? item.href
            let matchedTOC = tocByFile[fileKey] ?? tocByFile[item.href] ?? []

            if matchedTOC.isEmpty {
                // Count words without allocating intermediate arrays
                var wc = 0; var inWord = false
                for ch in text { if ch.isWhitespace { inWord = false } else if !inWord { inWord = true; wc += 1 } }
                if wc > 100 {
                    chapters.append(EPUBBook.Chapter(
                        title: "Chapter \(playOrder)", text: text, html: html,
                        playOrder: playOrder, nestingLevel: 0))
                    playOrder += 1
                }
            } else if matchedTOC.count == 1 {
                let toc = matchedTOC[0]
                chapters.append(EPUBBook.Chapter(
                    title: toc.title, text: text, html: html,
                    playOrder: toc.playOrder, nestingLevel: toc.nestingLevel))
                playOrder = toc.playOrder + 1
            } else {
                let sorted = matchedTOC.sorted { $0.playOrder < $1.playOrder }
                chapters.append(EPUBBook.Chapter(
                    title: sorted[0].title, text: text, html: html,
                    playOrder: sorted[0].playOrder, nestingLevel: sorted[0].nestingLevel))
                playOrder = (sorted.last?.playOrder ?? playOrder) + 1
            }
        }

        // Re-sort by playOrder
        return chapters.sorted { $0.playOrder < $1.playOrder }
    }

    // MARK: - HTML extraction

    private func extractTextAndHTML(from url: URL) throws -> (text: String, html: String) {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return (stripHTML(raw), raw)
    }

    private func stripHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil)
        else {
            return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return attr.string
    }
}

// MARK: - XML Helpers

// Generic single-attribute finder
private class SimpleAttrParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let targetTag: String
    private let targetAttr: String
    var result: String?

    init(data: Data, targetTag: String, targetAttr: String) {
        self.data = data; self.targetTag = targetTag; self.targetAttr = targetAttr
    }
    func parse() { let p = XMLParser(data: data); p.delegate = self; p.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        if elementName.lowercased().hasSuffix(targetTag.lowercased()), result == nil {
            result = attributes[targetAttr]
        }
    }
}

// OPF parser
private class OPFXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    var title: String?
    var author: String?
    var coverId: String?
    var ncxId: String?
    var manifest: [String: EPUBParser.ManifestItem] = [:]
    var spineIdrefs: [String] = []

    private var currentElement = ""
    private var inMetadata = false

    init(data: Data) { self.data = data }
    func parse() { let p = XMLParser(data: data); p.delegate = self; p.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        let name = localName(elementName)
        currentElement = name
        switch name {
        case "metadata": inMetadata = true
        case "meta":
            if attributes["name"] == "cover", let content = attributes["content"] {
                coverId = content
            }
        case "item":
            if let id = attributes["id"], let href = attributes["href"],
               let mt = attributes["media-type"] {
                manifest[id] = EPUBParser.ManifestItem(id: id, href: href, mediaType: mt)
                if mt.contains("ncx") { ncxId = id }
            }
        case "itemref":
            if let idref = attributes["idref"] { spineIdrefs.append(idref) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if localName(elementName) == "metadata" { inMetadata = false }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inMetadata else { return }
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        let el = localName(currentElement)
        if el == "title" && title == nil { title = s }
        if el == "creator" && author == nil { author = s }
    }

    private func localName(_ name: String) -> String {
        name.components(separatedBy: ":").last?.lowercased() ?? name.lowercased()
    }
}

// NCX parser
private class NCXParser: NSObject, XMLParserDelegate {
    private let data: Data
    var entries: [EPUBParser.TOCEntry] = []

    private var currentTitle = ""
    private var currentSrc = ""
    private var currentPlayOrder = 0
    private var nestingStack: [Int] = []   // tracks depth
    private var inNavLabel = false
    private var inText = false

    init(data: Data) { self.data = data }
    func parse() { let p = XMLParser(data: data); p.delegate = self; p.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        let name = elementName.lowercased().components(separatedBy: ":").last ?? elementName.lowercased()
        switch name {
        case "navpoint":
            nestingStack.append(0)
            currentPlayOrder = Int(attributes["playorder"] ?? "") ?? (entries.count + 1)
            currentTitle = ""
            currentSrc = ""
        case "navlabel": inNavLabel = true
        case "text" where inNavLabel: inText = true
        case "content":
            currentSrc = attributes["src"] ?? ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { currentTitle += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let name = elementName.lowercased().components(separatedBy: ":").last ?? elementName.lowercased()
        switch name {
        case "text" where inText:
            inText = false
        case "navlabel":
            inNavLabel = false
        case "navpoint":
            let level = max(0, nestingStack.count - 1)
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && !currentSrc.isEmpty {
                // Strip fragment for file matching; keep full href
                entries.append(EPUBParser.TOCEntry(
                    title: title,
                    href: currentSrc,
                    playOrder: currentPlayOrder,
                    nestingLevel: level
                ))
            }
            if !nestingStack.isEmpty { nestingStack.removeLast() }
            currentTitle = ""
            currentSrc = ""
        default: break
        }
    }
}

// EPUB3 nav.xhtml parser (reads <nav epub:type="toc"> <ol><li><a href>...)
private class NavXHTMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    var entries: [EPUBParser.TOCEntry] = []

    private var inTocNav = false
    private var listDepth = 0
    private var currentHref = ""
    private var currentTitle = ""
    private var inAnchor = false
    private var playOrder = 1

    init(data: Data) { self.data = data }
    func parse() { let p = XMLParser(data: data); p.delegate = self; p.parse() }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        let name = elementName.lowercased()
        if name == "nav" {
            let epubType = attributes["epub:type"] ?? attributes["type"] ?? ""
            if epubType.contains("toc") { inTocNav = true }
        }
        guard inTocNav else { return }
        if name == "ol" || name == "ul" { listDepth += 1 }
        if name == "a" {
            currentHref = attributes["href"] ?? ""
            currentTitle = ""
            inAnchor = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inAnchor else { return }
        currentTitle += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let name = elementName.lowercased()
        if name == "nav" && inTocNav { inTocNav = false }
        guard inTocNav else { return }
        if name == "ol" || name == "ul" { listDepth = max(0, listDepth - 1) }
        if name == "a" {
            inAnchor = false
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && !currentHref.isEmpty {
                entries.append(EPUBParser.TOCEntry(
                    title: title,
                    href: currentHref,
                    playOrder: playOrder,
                    nestingLevel: max(0, listDepth - 1)
                ))
                playOrder += 1
            }
        }
    }
}
