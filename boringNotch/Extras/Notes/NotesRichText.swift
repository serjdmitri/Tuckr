//
//  NotesRichText.swift
//  boringNotch
//
//  Rich text for the notes editor, in the small HTML dialect Apple Notes speaks through
//  AppleScript: titles and headings, bold, italic, underline, strikethrough, monospace,
//  bulleted lists and links. Checklists and numbered lists cannot be written to Notes that
//  way (it turns them into bullets), so here they are lines that start with a box or a
//  number and stay plain text in Notes.
//

import AppKit

enum NotesStyle {
    static let bodySize: CGFloat = 13
    static let titleSize: CGFloat = 24
    static let headingSize: CGFloat = 18
    static let monoSize: CGFloat = 12
    static let text = NSColor.white
    static let checkedText = NSColor(white: 1, alpha: 0.45)
    static let bullet = "• "
    static let unchecked = "☐ "
    static let checked = "☑ "

    static func font(size: CGFloat = bodySize, bold: Bool = false, italic: Bool = false, mono: Bool = false) -> NSFont {
        var font: NSFont = mono
            ? NSFont.monospacedSystemFont(ofSize: monoSize, weight: bold ? .bold : .regular)
            : NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: font(), .foregroundColor: text]
    }
}

enum NotesHTML {
    // MARK: - From Notes' HTML

    /// A tolerant reader for the tags Notes uses: div, br, h1, h2, b, i, u, strike, tt, font,
    /// span (for its font size), ul, ol, li and a.
    static func attributed(from html: String) -> NSAttributedString {
        var parser = Parser()
        return parser.parse(html)
    }

    private struct Style {
        var bold = false, italic = false, underline = false, strike = false, mono = false
        var size: CGFloat = NotesStyle.bodySize
        var link: String?
    }

    private struct Parser {
        var output = NSMutableAttributedString()
        var paragraph = NSMutableAttributedString()
        var hadBreak = false
        var styles: [Style] = [Style()]
        /// What each open tag pushed, so a closing tag pops the right thing.
        var open: [(tag: String, pushed: Bool)] = []
        var lists: [(ordered: Bool, count: Int)] = []
        var pendingPrefix: String?
        var current: Style { styles[styles.count - 1] }

        mutating func parse(_ html: String) -> NSAttributedString {
            var index = html.startIndex
            var text = ""
            while index < html.endIndex {
                let ch = html[index]
                if ch == "<", let close = html[index...].firstIndex(of: ">") {
                    if !text.isEmpty { append(decode(text)); text = "" }
                    handle(tag: String(html[html.index(after: index)..<close]))
                    index = html.index(after: close)
                } else {
                    text.append(ch)
                    index = html.index(after: index)
                }
            }
            if !text.isEmpty { append(decode(text)) }
            endParagraph()
            // A note's text ends with its last line, not with an empty one.
            if output.string.hasSuffix("\n") { output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1)) }
            return output
        }

        // MARK: Tags

        mutating func handle(tag raw: String) {
            let isClosing = raw.hasPrefix("/")
            let body = isClosing ? String(raw.dropFirst()) : raw
            let name = body.split(whereSeparator: { $0 == " " || $0 == "/" }).first.map { $0.lowercased() } ?? ""
            if isClosing { close(name) } else { openTag(name, attributes: body) }
        }

        mutating func openTag(_ name: String, attributes: String) {
            var pushed = false
            switch name {
            case "div", "p":
                startBlock()
            case "h1":
                startBlock()
                push { $0.bold = true; $0.size = NotesStyle.titleSize }; pushed = true
            case "h2":
                startBlock()
                push { $0.bold = true; $0.size = NotesStyle.headingSize }; pushed = true
            case "ul", "ol":
                startBlock()
                lists.append((name == "ol", 0))
            case "li":
                startBlock()
                if lists.isEmpty { pendingPrefix = NotesStyle.bullet } else {
                    lists[lists.count - 1].count += 1
                    let l = lists[lists.count - 1]
                    pendingPrefix = l.ordered ? "\(l.count). " : NotesStyle.bullet
                }
            case "br":
                if paragraph.length > 0 {
                    endParagraph()
                } else {
                    hadBreak = true
                }
            case "b", "strong": push { $0.bold = true }; pushed = true
            case "i", "em": push { $0.italic = true }; pushed = true
            case "u": push { $0.underline = true }; pushed = true
            case "strike", "s", "del": push { $0.strike = true }; pushed = true
            case "tt", "code": push { $0.mono = true }; pushed = true
            case "font":
                let face = attribute("face", in: attributes)?.lowercased() ?? ""
                push {
                    if face.contains("courier") || face.contains("menlo") || face.contains("monaco") || face.contains("mono") { $0.mono = true }
                    if face.contains("bold") { $0.bold = true }
                }
                pushed = true
            case "span":
                let size = attribute("style", in: attributes).flatMap(fontSize)
                push { if let size { $0.size = size } }
                pushed = true
            case "a":
                let href = attribute("href", in: attributes)
                push { $0.link = href }
                pushed = true
            default: break
            }
            open.append((name, pushed))
        }

        mutating func close(_ name: String) {
            // Pop back to the matching open tag.
            guard let at = open.lastIndex(where: { $0.tag == name }) else { return }
            while open.count > at {
                let tag = open.removeLast()
                if tag.pushed, styles.count > 1 { styles.removeLast() }
                if tag.tag == name { break }
            }
            switch name {
            case "div", "p", "h1", "h2", "li": endParagraph()
            case "ul", "ol": if !lists.isEmpty { lists.removeLast() }; endParagraph()
            default: break
            }
        }

        mutating func push(_ change: (inout Style) -> Void) {
            var next = current
            change(&next)
            styles.append(next)
        }

        // MARK: Paragraphs

        mutating func startBlock() {
            if paragraph.length > 0 { endParagraph() }
        }

        mutating func endParagraph() {
            if paragraph.length > 0 || hadBreak {
                output.append(paragraph)
                output.append(NSAttributedString(string: "\n", attributes: NotesStyle.bodyAttributes))
            }
            paragraph = NSMutableAttributedString()
            hadBreak = false
            pendingPrefix = nil
        }

        mutating func append(_ text: String) {
            guard !text.isEmpty else { return }
            // Whitespace between tags is not content.
            if text.allSatisfy({ $0 == "\n" || $0 == " " }) && paragraph.length == 0 && pendingPrefix == nil { return }
            let cleaned = text.replacingOccurrences(of: "\n", with: " ")
            if hadBreak && paragraph.length == 0 {
                output.append(NSAttributedString(string: "\n", attributes: NotesStyle.bodyAttributes))
                hadBreak = false
            }
            if let prefix = pendingPrefix {
                paragraph.append(NSAttributedString(string: prefix, attributes: NotesStyle.bodyAttributes))
                pendingPrefix = nil
            }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: NotesStyle.font(size: current.size, bold: current.bold, italic: current.italic, mono: current.mono),
                .foregroundColor: NotesStyle.text,
            ]
            if current.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if current.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = current.link, let url = URL(string: link) { attrs[.link] = url }
            paragraph.append(NSAttributedString(string: cleaned, attributes: attrs))
        }

        // MARK: Helpers

        func attribute(_ name: String, in tag: String) -> String? {
            guard let range = tag.range(of: "\(name)=", options: .caseInsensitive) else { return nil }
            let rest = tag[range.upperBound...]
            if let quote = rest.first, quote == "\"" || quote == "'" {
                let inner = rest.dropFirst()
                return inner.firstIndex(of: quote).map { String(inner[..<$0]) }
            }
            return String(rest.prefix { $0 != " " && $0 != ">" })
        }

        func fontSize(from style: String) -> CGFloat? {
            guard let range = style.range(of: "font-size:") else { return nil }
            let digits = style[range.upperBound...].drop { $0 == " " }.prefix { $0.isNumber || $0 == "." }
            return Double(digits).map { CGFloat($0) }
        }

        func decode(_ s: String) -> String {
            guard s.contains("&") else { return s }
            var out = s
            for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
                out = out.replacingOccurrences(of: entity, with: char)
            }
            return out.replacingOccurrences(of: "&amp;", with: "&")
        }
    }

    // MARK: - To Notes' HTML

    /// The editor's text as Notes' HTML: one block per line, bullet lines grouped into a list.
    static func html(from attributed: NSAttributedString) -> String {
        let whole = attributed.string as NSString
        var out = ""
        var inList = false
        var location = 0
        while location < whole.length || (location == 0 && whole.length == 0) {
            let paragraph = whole.length == 0 ? NSRange(location: 0, length: 0) : whole.paragraphRange(for: NSRange(location: location, length: 0))
            var content = NSRange(location: paragraph.location, length: paragraph.length)
            if content.length > 0, whole.character(at: content.location + content.length - 1) == 10 { content.length -= 1 }
            var isBullet = false
            if content.length >= 2, whole.substring(with: NSRange(location: content.location, length: 2)) == NotesStyle.bullet {
                isBullet = true
                content = NSRange(location: content.location + 2, length: content.length - 2)
            }
            if isBullet && !inList { out += "<ul>"; inList = true }
            if !isBullet && inList { out += "</ul>"; inList = false }
            let inner = inline(attributed, content)
            if isBullet {
                out += "<li>\(inner.isEmpty ? "<br>" : inner)</li>"
            } else {
                let size = content.length > 0 ? ((attributed.attribute(.font, at: content.location, effectiveRange: nil) as? NSFont)?.pointSize ?? NotesStyle.bodySize) : NotesStyle.bodySize
                if size >= 22 {
                    out += "<h1>\(inner)</h1>"
                } else if size >= 16 {
                    out += "<h2>\(inner)</h2>"
                } else {
                    out += "<div>\(inner.isEmpty ? "<br>" : inner)</div>"
                }
            }
            if paragraph.length == 0 { break }
            location = paragraph.location + paragraph.length
        }
        if inList { out += "</ul>" }
        return out
    }

    private static func inline(_ attributed: NSAttributedString, _ range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        var out = ""
        attributed.enumerateAttributes(in: range) { attrs, run, _ in
            let text = (attributed.string as NSString).substring(with: run)
            var s = text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isHeading = (font?.pointSize ?? 0) >= 16 && (font?.pointSize ?? 0) != NotesStyle.monoSize
            if traits.contains(.monoSpace) { s = "<tt>\(s)</tt>" }
            if traits.contains(.bold) && !isHeading { s = "<b>\(s)</b>" }
            if traits.contains(.italic) { s = "<i>\(s)</i>" }
            if (attrs[.underlineStyle] as? Int ?? 0) != 0 { s = "<u>\(s)</u>" }
            if (attrs[.strikethroughStyle] as? Int ?? 0) != 0 { s = "<strike>\(s)</strike>" }
            if let link = attrs[.link] as? URL { s = "<a href=\"\(link.absoluteString)\">\(s)</a>" }
            out += s
        }
        return out
    }
}

// MARK: - The text view

/// The editor's commands, for the formatting bar: it holds the text view that has the cursor.
@MainActor
final class NotesEditorController: ObservableObject {
    static let shared = NotesEditorController()
    weak var textView: NotesNSTextView?
    /// Bumped on every selection or typing change so the bar can show what is on.
    @Published private(set) var revision = 0

    func touch() { revision += 1 }

    var state: NotesNSTextView.Formatting { textView?.formatting ?? .init() }

    func toggle(_ trait: NotesNSTextView.Trait) { textView?.toggle(trait); touch() }
    func setBlock(_ block: NotesNSTextView.Block) { textView?.setBlock(block); touch() }
    func toggleList(_ marker: NotesNSTextView.ListMarker) { textView?.toggleList(marker); touch() }
}

/// A text view for Notes' dialect: formatting commands, lists continued on Return, checkbox
/// lines that tick when clicked, and plain-text pasting. It takes ⌘B, ⌘I, ⌘U and the clipboard
/// keys itself, since the notch has no menu bar to carry them.
final class NotesNSTextView: NSTextView {
    enum Trait { case bold, italic, underline, strike, mono }
    enum Block { case title, heading, body }
    enum ListMarker { case bullet, checklist, numbered }

    struct Formatting {
        var bold = false, italic = false, underline = false, strike = false, mono = false
        var block = Block.body
        var list: ListMarker?
    }

    var onFormattingChange: (() -> Void)?

    // MARK: State at the cursor

    var formatting: Formatting {
        var f = Formatting()
        let attrs = currentAttributes
        let font = attrs[.font] as? NSFont
        let traits = font?.fontDescriptor.symbolicTraits ?? []
        f.mono = traits.contains(.monoSpace)
        f.italic = traits.contains(.italic)
        let size = font?.pointSize ?? NotesStyle.bodySize
        f.block = size >= 22 ? .title : (size >= 16 ? .heading : .body)
        f.bold = traits.contains(.bold) && f.block == .body
        f.underline = (attrs[.underlineStyle] as? Int ?? 0) != 0
        f.strike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
        let line = currentParagraphText
        if line.hasPrefix(NotesStyle.bullet) { f.list = .bullet }
        else if line.hasPrefix(NotesStyle.unchecked) || line.hasPrefix(NotesStyle.checked) { f.list = .checklist }
        else if numberedPrefix(in: line) != nil { f.list = .numbered }
        return f
    }

    private var currentAttributes: [NSAttributedString.Key: Any] {
        let range = selectedRange()
        if range.length > 0, range.location < textStorage?.length ?? 0 {
            return textStorage?.attributes(at: range.location, effectiveRange: nil) ?? typingAttributes
        }
        return typingAttributes
    }

    private var currentParagraphText: String {
        let whole = string as NSString
        guard whole.length > 0 else { return "" }
        let range = whole.paragraphRange(for: NSRange(location: min(selectedRange().location, whole.length - 1 + (selectedRange().location >= whole.length ? 1 : 0)), length: 0))
        return whole.substring(with: range)
    }

    private func numberedPrefix(in line: String) -> Int? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return Int(digits)
    }

    // MARK: Inline formatting

    func toggle(_ trait: Trait) {
        let f = formatting
        let range = selectedRange()
        func apply(_ change: (inout [NSAttributedString.Key: Any]) -> Void) {
            if range.length == 0 {
                var attrs = typingAttributes
                change(&attrs)
                typingAttributes = attrs
            } else if let storage = textStorage {
                storage.beginEditing()
                storage.enumerateAttributes(in: range) { attrs, run, _ in
                    var next = attrs
                    change(&next)
                    storage.setAttributes(next, range: run)
                }
                storage.endEditing()
                didChangeText()
            }
        }
        switch trait {
        case .bold:
            apply { attrs in
                let font = attrs[.font] as? NSFont ?? NotesStyle.font()
                attrs[.font] = f.bold
                    ? NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                    : NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
        case .italic:
            apply { attrs in
                let font = attrs[.font] as? NSFont ?? NotesStyle.font()
                attrs[.font] = f.italic
                    ? NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                    : NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
        case .underline:
            apply { $0[.underlineStyle] = f.underline ? 0 : NSUnderlineStyle.single.rawValue }
        case .strike:
            apply { $0[.strikethroughStyle] = f.strike ? 0 : NSUnderlineStyle.single.rawValue }
        case .mono:
            apply { attrs in
                let font = attrs[.font] as? NSFont ?? NotesStyle.font()
                let bold = font.fontDescriptor.symbolicTraits.contains(.bold)
                let italic = font.fontDescriptor.symbolicTraits.contains(.italic)
                attrs[.font] = f.mono
                    ? NotesStyle.font(bold: bold, italic: italic)
                    : NotesStyle.font(bold: bold, italic: italic, mono: true)
            }
        }
        onFormattingChange?()
    }

    // MARK: Blocks (title, heading, body)

    func setBlock(_ block: Block) {
        let size: CGFloat = block == .title ? NotesStyle.titleSize : (block == .heading ? NotesStyle.headingSize : NotesStyle.bodySize)
        let whole = string as NSString
        let range = whole.length == 0 ? NSRange(location: 0, length: 0) : whole.paragraphRange(for: selectedRange())
        let font = NotesStyle.font(size: size, bold: block != .body)
        if let storage = textStorage, range.length > 0 {
            storage.beginEditing()
            storage.addAttribute(.font, value: font, range: range)
            storage.endEditing()
            didChangeText()
        }
        var attrs = typingAttributes
        attrs[.font] = font
        typingAttributes = attrs
        onFormattingChange?()
    }

    // MARK: Lists

    func toggleList(_ marker: ListMarker) {
        guard let storage = textStorage else { return }
        let whole = string as NSString
        let range = whole.length == 0 ? NSRange(location: 0, length: 0) : whole.paragraphRange(for: selectedRange())
        if range.length == 0 {
            insertText(prefix(for: marker, number: 1), replacementRange: selectedRange())
            onFormattingChange?()
            return
        }
        let current = formatting.list
        var paragraphs: [NSRange] = []
        var location = range.location
        while location < range.location + range.length {
            let p = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            paragraphs.append(p)
            location = p.location + p.length
        }
        storage.beginEditing()
        // Back to front, so the ranges before stay valid as markers come and go.
        for (index, p) in paragraphs.enumerated().reversed() {
            let line = (storage.string as NSString).substring(with: p)
            let existing = [NotesStyle.bullet, NotesStyle.unchecked, NotesStyle.checked].first { line.hasPrefix($0) }
                ?? numberedPrefix(in: line).map { "\($0). " }
            if let existing { storage.deleteCharacters(in: NSRange(location: p.location, length: existing.count)) }
            if current != marker {
                storage.insert(
                    NSAttributedString(string: prefix(for: marker, number: index + 1), attributes: NotesStyle.bodyAttributes),
                    at: p.location)
            }
        }
        storage.endEditing()
        didChangeText()
        onFormattingChange?()
    }

    private func prefix(for marker: ListMarker, number: Int) -> String {
        switch marker {
        case .bullet: return NotesStyle.bullet
        case .checklist: return NotesStyle.unchecked
        case .numbered: return "\(number). "
        }
    }

    // MARK: Return continues a list; Return on an empty item ends it

    override func insertNewline(_ sender: Any?) {
        let line = currentParagraphText.trimmingCharacters(in: .newlines)
        var marker: String?
        var next: String?
        if line.hasPrefix(NotesStyle.bullet) { marker = NotesStyle.bullet; next = NotesStyle.bullet }
        else if line.hasPrefix(NotesStyle.unchecked) { marker = NotesStyle.unchecked; next = NotesStyle.unchecked }
        else if line.hasPrefix(NotesStyle.checked) { marker = NotesStyle.checked; next = NotesStyle.unchecked }
        else if let n = numberedPrefix(in: line) { marker = "\(n). "; next = "\(n + 1). " }
        guard let marker, let next else {
            super.insertNewline(sender)
            return
        }
        if line == marker.trimmingCharacters(in: .whitespaces) || line == marker {
            // An empty item: take the marker away and stop the list.
            let whole = string as NSString
            let p = whole.paragraphRange(for: selectedRange())
            if shouldChangeText(in: NSRange(location: p.location, length: marker.count), replacementString: "") {
                textStorage?.deleteCharacters(in: NSRange(location: p.location, length: marker.count))
                didChangeText()
            }
            return
        }
        super.insertNewline(sender)
        insertText(NSAttributedString(string: next, attributes: NotesStyle.bodyAttributes), replacementRange: selectedRange())
    }

    // MARK: Ticking a checkbox

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let whole = string as NSString
        if index < whole.length || index == whole.length, whole.length > 0 {
            let start = whole.paragraphRange(for: NSRange(location: min(index, whole.length - 1), length: 0)).location
            // A click on the box itself (the first or second character of the line).
            if start < whole.length, index <= start + 1,
                let first = whole.substring(with: NSRange(location: start, length: 1)) as String?,
                first == "☐" || first == "☑"
            {
                toggleCheckbox(at: start)
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func toggleCheckbox(at start: Int) {
        guard let storage = textStorage else { return }
        let whole = storage.string as NSString
        let isChecked = whole.substring(with: NSRange(location: start, length: 1)) == "☑"
        let paragraph = whole.paragraphRange(for: NSRange(location: start, length: 0))
        let textStart = start + 2
        let textRange = NSRange(location: textStart, length: max(0, paragraph.location + paragraph.length - textStart))
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: start, length: 1), with: isChecked ? "☐" : "☑")
        if textRange.length > 0 {
            storage.addAttribute(.foregroundColor, value: isChecked ? NotesStyle.text : NotesStyle.checkedText, range: textRange)
            if isChecked { storage.removeAttribute(.strikethroughStyle, range: textRange) }
            else { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange) }
        }
        storage.endEditing()
        didChangeText()
    }

    // MARK: Having the cursor keeps the notch open

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { MainActor.assumeIsolated { NotchKeyboard.setTyping("editor", true) } }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { MainActor.assumeIsolated { NotchKeyboard.setTyping("editor", false) } }
        return resigned
    }

    // MARK: Keys and pasting

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = event.modifierFlags.contains(.shift)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": toggle(.bold); return true
        case "i": toggle(.italic); return true
        case "u": toggle(.underline); return true
        case "x" where shift: toggle(.strike); return true
        case "c": copy(nil); return true
        case "x": cut(nil); return true
        case "v": pasteAsPlainText(nil); return true
        case "a": selectAll(nil); return true
        case "z": if shift { undoManager?.redo() } else { undoManager?.undo() }; return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        onFormattingChange?()
    }
}
