import SwiftUI
import WebKit

// MARK: - ReaderView (WKWebView-based)

struct ReaderView: View {
    let chapter: EPUBBook.Chapter
    @ObservedObject var speech: SpeechService
    @EnvironmentObject var settings: ReadingSettings
    var onTap: (() -> Void)?
    var onWordClick: ((Int) -> Void)?

    var body: some View {
        WebReaderView(chapter: chapter, speech: speech, settings: settings, onTap: onTap, onWordClick: onWordClick)
            .background(settings.theme.background)
            .ignoresSafeArea(edges: .horizontal)
    }
}

// MARK: - WKWebView wrapper

struct WebReaderView: UIViewRepresentable {
    let chapter: EPUBBook.Chapter
    @ObservedObject var speech: SpeechService
    @ObservedObject var settings: ReadingSettings
    var onTap: (() -> Void)?
    var onWordClick: ((Int) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "tapHandler")
        contentController.add(context.coordinator, name: "wordClick")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        loadContent(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload when chapter or layout mode changes
        let twoPageChanged = context.coordinator.loadedTwoPageMode != settings.twoPageMode
        if context.coordinator.loadedChapterID != chapter.id || twoPageChanged {
            context.coordinator.loadedChapterID = chapter.id
            context.coordinator.loadedTwoPageMode = settings.twoPageMode
            context.coordinator.lastHighlightStart = -1
            context.coordinator.lastSettingsKey = ""
            loadContent(in: webView, coordinator: context.coordinator)
            return
        }
        // Update highlight when word range changes
        highlightWord(in: webView, coordinator: context.coordinator)
        // Update CSS vars only when settings actually changed
        let settingsKey = "\(settings.theme.rawValue)-\(Int(settings.fontSize))-\(settings.fontFamily)-\(settings.lineHeight)-\(Int(settings.marginSize))"
        if settingsKey != context.coordinator.lastSettingsKey {
            context.coordinator.lastSettingsKey = settingsKey
            applySettings(in: webView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap, onWordClick: onWordClick) }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var loadedChapterID: UUID?
        var lastHighlightStart: Int = -1
        var loadedTwoPageMode: Bool = false
        var onTap: (() -> Void)?
        var onWordClick: ((Int) -> Void)?
        // Pending initial highlight to apply after page load
        var pendingInitialWord: String?
        var pendingInitialHint: Int = 0
        // Track last applied settings to avoid redundant JS calls
        var lastSettingsKey: String = ""

        init(onTap: (() -> Void)? = nil, onWordClick: ((Int) -> Void)? = nil) {
            self.onTap = onTap
            self.onWordClick = onWordClick
            super.init()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "tapHandler" {
                DispatchQueue.main.async { [weak self] in self?.onTap?() }
            } else if message.name == "wordClick", let wordIndex = message.body as? Int {
                DispatchQueue.main.async { [weak self] in self?.onWordClick?(wordIndex) }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let word = pendingInitialWord else { return }
            let escaped = word
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let hint = pendingInitialHint
            // Small delay to let JS finish setting up click handlers
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                webView.evaluateJavaScript("highlightWordNear('\(escaped)', \(hint))") { _, _ in }
            }
            pendingInitialWord = nil
        }
    }

    // MARK: - Load

    private func loadContent(in webView: WKWebView, coordinator: Coordinator) {
        // If there's a saved position, set up an initial highlight to fire after load
        if let range = speech.currentWordRange, !speech.isPlaying {
            let word = String(chapter.text[range])
            let charOffset = chapter.text.distance(from: chapter.text.startIndex, to: range.lowerBound)
            coordinator.pendingInitialWord = word
            coordinator.pendingInitialHint = chapter.wordCount(upToCharOffset: charOffset)
        } else {
            coordinator.pendingInitialWord = nil
        }
        let html = buildHTML()
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func buildHTML() -> String {
        let body = chapter.html.isEmpty ? "<p>\(chapter.text)</p>" : extractBody(chapter.html)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
        <style>
        \(css())
        </style>
        </head>
        <body>
        \(body)
        <script>
        \(highlightJS())
        \(tapHandlerJS())
        </script>
        </body>
        </html>
        """
    }

    private func extractBody(_ html: String) -> String {
        let lower = html.lowercased()
        if let bodyStart = lower.range(of: "<body"),
           let bodyOpen = lower.range(of: ">", range: bodyStart.upperBound..<lower.endIndex),
           let bodyEnd = lower.range(of: "</body>") {
            return String(html[bodyOpen.upperBound..<bodyEnd.lowerBound])
        }
        return html
            .replacingOccurrences(of: "<head[^>]*>[\\s\\S]*?</head>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<html[^>]*>|</html>|<!DOCTYPE[^>]*>", with: "", options: .regularExpression)
    }

    // MARK: - CSS

    private func css() -> String {
        let margin = settings.marginSize
        let columnCSS = settings.twoPageMode ? """
        body {
            columns: 2;
            column-gap: 48px;
            column-rule: 1px solid rgba(128,128,128,0.2);
            height: calc(100vh - 140px);
            overflow: hidden;
            padding: 24px \(Int(margin))px 0;
        }
        """ : ""
        return """
        :root {
            --bg: \(settings.theme.backgroundHex);
            --fg: \(settings.theme.foregroundHex);
            --font-size: \(Int(settings.fontSize))px;
            --font-family: \(settings.font.cssFamily);
            --line-height: \(settings.lineHeight);
            --margin: \(Int(margin))px;
            --highlight: #1E73FF;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        html {
            background: var(--bg);
        }
        body {
            background: var(--bg);
            color: var(--fg);
            font-family: var(--font-family);
            font-size: var(--font-size);
            line-height: var(--line-height);
            padding: 24px var(--margin) 120px;
            -webkit-text-size-adjust: none;
            text-rendering: optimizeLegibility;
        }
        \(columnCSS)
        /* Force all text elements to inherit theme color */
        p, div, span, li, td, th, blockquote, pre, article, section {
            color: inherit;
        }
        /* Typography */
        p {
            margin-bottom: 0.85em;
            text-align: justify;
            hyphens: auto;
        }
        h1, h2, h3, h4 {
            color: var(--fg);
            margin: 1.4em 0 0.6em;
            text-align: center;
            line-height: 1.25;
        }
        h1 { font-size: 2em; font-weight: 900; }
        h2 { font-size: 1.5em; font-weight: 700; }
        h3 { font-size: 1.2em; font-style: italic; font-weight: 600; }
        /* Drop cap on first paragraph after h1/h2 */
        h1 + p::first-letter, h2 + p::first-letter {
            font-size: 3.6em;
            font-weight: 900;
            float: left;
            line-height: 0.8;
            margin: 0.08em 0.08em 0 0;
        }
        em, i { font-style: italic; }
        strong, b { font-weight: 700; }
        /* Images */
        img { max-width: 100%; height: auto; display: block; margin: 1em auto; }
        /* Strip EPUB inline color/background only — keep font-family overrides away */
        [style*="color"] { color: var(--fg) !important; }
        [style*="background"] { background: var(--bg) !important; }
        /* Highlight */
        .hw {
            color: var(--highlight) !important;
            font-weight: 700;
        }
        \(settings.theme == .dark ? "a { color: #6EA8FE; }" : "")
        """
    }

    // MARK: - Highlight JS

    private func highlightJS() -> String {
        """
        var _spans = null;
        var _lastSpan = null;
        var _currentIdx = 0;

        function buildSpans() {
            var walker = document.createTreeWalker(
                document.body,
                NodeFilter.SHOW_TEXT,
                { acceptNode: function(n) {
                    var p = n.parentNode;
                    if (!p) return NodeFilter.FILTER_REJECT;
                    var tag = p.nodeName;
                    if (tag === 'SCRIPT' || tag === 'STYLE') return NodeFilter.FILTER_REJECT;
                    return NodeFilter.FILTER_ACCEPT;
                }}
            );
            var nodes = [];
            while (walker.nextNode()) nodes.push(walker.currentNode);
            
            var allSpans = [];
            
            nodes.forEach(function(node) {
                var frag = document.createDocumentFragment();
                var text = node.textContent;
                var i = 0;
                
                while (i < text.length) {
                    var wsStart = i;
                    while (i < text.length && /\\s/.test(text[i])) i++;
                    if (i > wsStart) {
                        frag.appendChild(document.createTextNode(text.substring(wsStart, i)));
                    }
                    
                    var wordStart = i;
                    while (i < text.length && !/\\s/.test(text[i])) i++;
                    if (i > wordStart) {
                        var word = text.substring(wordStart, i);
                        var s = document.createElement('span');
                        s.className = 'w';
                        s.textContent = word;
                        frag.appendChild(s);
                        allSpans.push(s);
                    }
                }
                
                if (node.parentNode) node.parentNode.replaceChild(frag, node);
            });
            
            _spans = allSpans;
        }

        function norm(s) {
            return s.toLowerCase().replace(/[^a-z0-9']/g, '');
        }

        function highlightWordNear(word, hint) {
            if (_spans === null) buildSpans();
            if (_spans.length === 0) return;
            
            var target = norm(word);
            if (target.length === 0) return;
            
            // Determine search start: use hint if it's ahead of current, else current+1
            // This ensures we always progress forward through the text
            var searchStart = (hint > _currentIdx) ? hint : _currentIdx;
            
            // First, try to find exact match searching forward from searchStart
            var found = -1;
            for (var i = searchStart; i < _spans.length; i++) {
                if (norm(_spans[i].textContent) === target) {
                    found = i;
                    break;
                }
            }
            
            // If not found forward, search backward from searchStart (for rewind/replay)
            if (found < 0) {
                for (var i = Math.min(searchStart, _spans.length - 1); i >= 0; i--) {
                    if (norm(_spans[i].textContent) === target) {
                        found = i;
                        break;
                    }
                }
            }
            
            if (found >= 0) {
                if (_lastSpan !== null) {
                    _lastSpan.classList.remove('hw');
                }
                _currentIdx = found;
                _lastSpan = _spans[found];
                _lastSpan.classList.add('hw');
                _lastSpan.scrollIntoView({ block: 'center', behavior: 'smooth' });
            }
        }

        function clearHighlight() {
            if (_lastSpan !== null) {
                _lastSpan.classList.remove('hw');
                _lastSpan = null;
            }
            _currentIdx = 0;
        }

        function setupWordClickHandlers() {
            if (_spans === null) buildSpans();
            _spans.forEach(function(span, idx) {
                span.style.cursor = 'pointer';
                span.addEventListener('click', function(e) {
                    e.stopPropagation();
                    if (window._suppressNextTap) window._suppressNextTap();
                    // Immediate visual feedback
                    if (_lastSpan !== null) {
                        _lastSpan.classList.remove('hw');
                    }
                    _lastSpan = span;
                    _currentIdx = idx;
                    span.classList.add('hw');

                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wordClick) {
                        window.webkit.messageHandlers.wordClick.postMessage(idx);
                    }
                });
            });
        }

        // Initialize click handlers after DOM is ready
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', setupWordClickHandlers);
        } else {
            setTimeout(setupWordClickHandlers, 0);
        }

        function updateCSS(bg, fg, fontSize, fontFamily, lineHeight, margin) {
            var r = document.documentElement.style;
            r.setProperty('--bg', bg);
            r.setProperty('--fg', fg);
            r.setProperty('--font-size', fontSize + 'px');
            r.setProperty('--font-family', fontFamily);
            r.setProperty('--line-height', lineHeight);
            r.setProperty('--margin', margin + 'px');
            document.documentElement.style.background = bg;
            document.body.style.background = bg;
            document.body.style.color = fg;
        }
        """
    }

    private func tapHandlerJS() -> String {
        """
        (function() {
            var touchStartY = 0;
            var touchStartX = 0;
            var touchStartTime = 0;
            var _wordWasTapped = false;  // set by word click handler to suppress chrome toggle

            // Called by word click handlers to suppress the outer tap
            window._suppressNextTap = function() { _wordWasTapped = true; };

            document.addEventListener('touchstart', function(e) {
                touchStartY = e.touches[0].clientY;
                touchStartX = e.touches[0].clientX;
                touchStartTime = Date.now();
                _wordWasTapped = false;
            }, { passive: true });

            document.addEventListener('touchend', function(e) {
                var touchEndY = e.changedTouches[0].clientY;
                var touchEndX = e.changedTouches[0].clientX;
                var touchDuration = Date.now() - touchStartTime;
                var deltaY = Math.abs(touchEndY - touchStartY);
                var deltaX = Math.abs(touchEndX - touchStartX);
                
                // Only trigger tap if it was a quick tap without much movement (not a scroll)
                // and not on a word span (word click suppresses chrome toggle)
                if (touchDuration < 300 && deltaY < 10 && deltaX < 10 && !_wordWasTapped) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tapHandler) {
                        window.webkit.messageHandlers.tapHandler.postMessage('tap');
                    }
                }
                _wordWasTapped = false;
            }, { passive: true });
        })();
        """
    }

    // MARK: - Update highlight

    private func highlightWord(in webView: WKWebView, coordinator: Coordinator) {
        guard let range = speech.currentWordRange else {
            coordinator.lastHighlightStart = -1
            webView.evaluateJavaScript("clearHighlight()") { _, _ in }
            return
        }
        
        // Get the actual word being spoken
        let word = String(chapter.text[range])
        let escapedWord = word
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "")
        
        // Compute position hint (approximate word index)
        let charOffset = chapter.text.distance(from: chapter.text.startIndex, to: range.lowerBound)
        guard charOffset != coordinator.lastHighlightStart else { return }
        coordinator.lastHighlightStart = charOffset
        
        let hint = chapter.wordCount(upToCharOffset: charOffset)
        
        // Pass word and hint to JavaScript
        webView.evaluateJavaScript("highlightWordNear('\(escapedWord)', \(hint))") { _, _ in }
    }

    private func applySettings(in webView: WKWebView) {
        let js = """
        updateCSS(
            '\(settings.theme.backgroundHex)',
            '\(settings.theme.foregroundHex)',
            \(Int(settings.fontSize)),
            '\(settings.font.cssFamily)',
            \(settings.lineHeight),
            \(Int(settings.marginSize))
        );
        """
        webView.evaluateJavaScript(js) { _, _ in }
    }
}
