import AppKit
import Combine
import UserNotifications

struct Snip: Codable { var n: String; var t: String }
struct Bm: Codable { var n: String; var u: String }
struct Search: Codable { var n: String; var u: String }
struct Saved: Codable {
    var snips: [Snip] = [Snip(n: "ty", t: "Thanks so much, I really appreciate it!"), Snip(n: "today", t: "{date}")]
    var bms: [Bm] = []
    var searches: [String: Search] = [:]
    var clips: [String] = []
}

enum After { case close, stay, set(String) }

struct Item: Identifiable {
    let id = UUID()
    var icon: String
    var title: String
    var sub: String = ""
    var image: NSImage? = nil
    var after: After = .close
    var del: (() -> Void)? = nil
    var run: () -> Void = {}
}

/// Small safe calculator (NSExpression can crash on bad input, so we parse ourselves).
struct Calc {
    var s: [Character]
    var i = 0
    var bad = false
    init(_ t: String) {
        s = Array(t.lowercased().replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace })
    }
    mutating func run() -> Double? {
        let v = expr()
        return (!bad && i == s.count && v.isFinite) ? v : nil
    }
    func peek() -> Character? { i < s.count ? s[i] : nil }
    mutating func expr() -> Double {
        var v = term()
        while let c = peek(), c == "+" || c == "-" {
            i += 1
            let r = term()
            v = c == "+" ? v + r : v - r
        }
        return v
    }
    mutating func term() -> Double {
        var v = unary()
        while let c = peek(), c == "*" || c == "/" || c == "%" {
            i += 1
            let r = unary()
            v = c == "*" ? v * r : (c == "/" ? v / r : fmod(v, r))
        }
        return v
    }
    mutating func unary() -> Double {
        if peek() == "-" { i += 1; return -unary() }
        let b = prim()
        if peek() == "^" { i += 1; return pow(b, unary()) }
        return b
    }
    mutating func prim() -> Double {
        guard let c = peek() else { bad = true; return 0 }
        if c == "(" {
            i += 1
            let v = expr()
            if peek() == ")" { i += 1 } else { bad = true }
            return v
        }
        if c.isNumber || c == "." {
            var t = ""
            while let d = peek(), d.isNumber || d == "." { t.append(d); i += 1 }
            if let v = Double(t) { return v }
            bad = true; return 0
        }
        var name = ""
        while let d = peek(), d.isLetter { name.append(d); i += 1 }
        if name == "pi" { return Double.pi }
        guard peek() == "(" else { bad = true; return 0 }
        i += 1
        let a = expr()
        if peek() == ")" { i += 1 } else { bad = true }
        switch name {
        case "sqrt": return sqrt(a)
        case "sin": return sin(a)
        case "cos": return cos(a)
        case "tan": return tan(a)
        case "log": return log(a)
        case "abs": return abs(a)
        case "round": return a.rounded()
        case "floor": return floor(a)
        case "ceil": return ceil(a)
        default: bad = true; return 0
        }
    }
}

final class Launcher: ObservableObject {
    @Published var query = "" { didSet { sel = 0; refresh() } }
    @Published var items: [Item] = []
    @Published var sel = 0
    @Published var focusTick = 0
    var onClose: () -> Void = {}

    private var saved: Saved
    private var apps: [(name: String, path: String)] = []
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?

    static let defaults: [String: Search] = [
        "g": Search(n: "Google", u: "https://www.google.com/search?q={q}"),
        "ddg": Search(n: "DuckDuckGo", u: "https://duckduckgo.com/?q={q}"),
        "yt": Search(n: "YouTube", u: "https://www.youtube.com/results?search_query={q}"),
        "w": Search(n: "Wikipedia", u: "https://en.wikipedia.org/w/index.php?search={q}"),
        "def": Search(n: "Wiktionary", u: "https://en.wiktionary.org/wiki/{q}"),
        "maps": Search(n: "Google Maps", u: "https://www.google.com/maps/search/{q}"),
        "gh": Search(n: "GitHub", u: "https://github.com/search?q={q}"),
        "a": Search(n: "Amazon", u: "https://www.amazon.com/s?k={q}"),
        "tr": Search(n: "Google Translate", u: "https://translate.google.com/?text={q}"),
        "so": Search(n: "Stack Overflow", u: "https://stackoverflow.com/search?q={q}"),
        "img": Search(n: "Google Images", u: "https://www.google.com/search?tbm=isch&q={q}"),
        "imdb": Search(n: "IMDb", u: "https://www.imdb.com/find/?q={q}"),
        "npm": Search(n: "npm", u: "https://www.npmjs.com/search?q={q}")
    ]

    init() {
        if let d = UserDefaults.standard.data(forKey: "jeeves"), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            saved = s
        } else {
            saved = Saved()
        }
        scanApps()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.pollClip() }
        refresh()
    }

    // MARK: helpers
    func save() {
        if let d = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(d, forKey: "jeeves") }
    }
    func refresh() { items = results(query.trimmingCharacters(in: .whitespaces)) }
    func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        lastChange = pb.changeCount
    }
    func openURL(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }
    func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s
    }
    func fix(_ u: String) -> String { u.lowercased().hasPrefix("http") ? u : "https://" + u }
    func fmt(_ v: Double) -> String {
        (v == v.rounded() && abs(v) < 1e15) ? String(Int(v)) : String(format: "%.10g", v)
    }
    func expand(_ t: String) -> String {
        let d = DateFormatter(); d.dateStyle = .medium; d.timeStyle = .none
        let h = DateFormatter(); h.dateStyle = .none; h.timeStyle = .short
        return t.replacingOccurrences(of: "{date}", with: d.string(from: Date()))
                .replacingOccurrences(of: "{time}", with: h.string(from: Date()))
    }
    var allSearches: [String: Search] {
        var m = Launcher.defaults
        for (k, v) in saved.searches { m[k] = v }
        return m
    }

    // MARK: clipboard history
    func pollClip() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        // Skip things password managers mark as secret.
        if pb.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true { return }
        if let s = pb.string(forType: .string) { addClip(s) }
    }
    func addClip(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count < 5000 else { return }
        saved.clips.removeAll { $0 == t }
        saved.clips.insert(t, at: 0)
        saved.clips = Array(saved.clips.prefix(50))
        save()
    }

    // MARK: apps
    func scanApps() {
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var found: [String: String] = [:]
        for d in dirs {
            for f in (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [] where f.hasSuffix(".app") {
                found[String(f.dropLast(4))] = d + "/" + f
            }
        }
        apps = found.map { (name: $0.key, path: $0.value) }.sorted { $0.name < $1.name }
    }
    func matchApps(_ lq: String) -> [(name: String, path: String)] {
        func rank(_ n: String) -> Int? {
            let l = n.lowercased()
            if l.hasPrefix(lq) { return 0 }
            if l.contains(lq) { return 1 }
            let ini = l.split(separator: " ").compactMap { $0.first }.map { String($0) }.joined()
            if ini.hasPrefix(lq) { return 2 }
            return nil
        }
        var scored: [(app: (name: String, path: String), r: Int)] = []
        for a in apps { if let r = rank(a.name) { scored.append((app: a, r: r)) } }
        scored.sort { ($0.r, $0.app.name.count) < ($1.r, $1.app.name.count) }
        return scored.prefix(6).map { $0.app }
    }

    // MARK: keyboard actions
    func move(_ d: Int) {
        guard !items.isEmpty else { return }
        sel = min(max(sel + d, 0), items.count - 1)
    }
    func tab() {
        if items.indices.contains(sel), case .set(let s) = items[sel].after { query = s }
    }
    func run(_ k: Int) {
        guard items.indices.contains(k) else { return }
        let it = items[k]
        it.run()
        switch it.after {
        case .close: onClose(); query = ""
        case .stay: refresh()
        case .set(let s): query = s
        }
    }

    // MARK: results
    func results(_ q: String) -> [Item] {
        var out: [Item] = []
        if q.isEmpty {
            let tips: [(String, String, String)] = [
                ("🔎", "g best pizza near me", "Web search with a keyword: g, ddg, yt, w, maps, gh, so…"),
                ("🧮", "24 * (7 + 3) / 5", "Calculator with sqrt(), sin(), pi and ^"),
                ("📋", "clip", "Clipboard history, saved automatically"),
                ("✂️", "snip", "Snippets: snip add hello = Hi, it’s {date}"),
                ("🔖", "bm", "Bookmarks: bm add docs = https://docs.claude.com"),
                ("⏰", "timer 10m", "Timers: timer 30s, timer 5, timer 1h"),
                ("🛠️", "uuid", "Tools: uuid, pass, now, b64 text, enc text, upper text, #ff8800"),
                ("🌙", "sleep", "sleep puts the Mac to sleep, lock turns the display off"),
                ("➕", "search add wp = https://example.com/?s={q}", "Make your own search keyword")
            ]
            return tips.map { Item(icon: $0.0, title: $0.1, sub: $0.2, after: .set($0.1)) }
        }
        let parts = q.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map { String($0) }
        let kw = parts[0].lowercased()
        let rest = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        let lq = q.lowercased()

        if q.contains(where: { $0.isNumber }), q.contains(where: { "+-*/%^(".contains($0) }) {
            var c = Calc(q)
            if let v = c.run() {
                let r = fmt(v)
                out.append(Item(icon: "🧮", title: r, sub: q + " · Enter copies the result", run: { self.copy(r) }))
            }
        }

        // add commands: snip add n = text, bm add n = url, search add k = url-with-{q}
        if ["snip", "bm", "search"].contains(kw), rest.lowercased().hasPrefix("add "), let eq = rest.firstIndex(of: "=") {
            let name = rest[rest.index(rest.startIndex, offsetBy: 4)..<eq].trimmingCharacters(in: .whitespaces)
            let val = rest[rest.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !val.isEmpty else { return out }
            switch kw {
            case "snip":
                return [Item(icon: "✂️", title: "Save snippet “\(name)”", sub: val, after: .set("snip"), run: {
                    self.saved.snips.removeAll { $0.n == name }
                    self.saved.snips.append(Snip(n: name, t: val)); self.save()
                })]
            case "bm":
                return [Item(icon: "🔖", title: "Save bookmark “\(name)”", sub: self.fix(val), after: .set("bm"), run: {
                    self.saved.bms.removeAll { $0.n == name }
                    self.saved.bms.append(Bm(n: name, u: self.fix(val))); self.save()
                })]
            default:
                guard val.contains("{q}") else {
                    return [Item(icon: "⚠️", title: "The address needs {q} where the query goes", sub: "Example: search add wp = https://example.com/?s={q}", after: .stay)]
                }
                return [Item(icon: "➕", title: "Save search keyword “\(name)”", sub: val, after: .set(name.lowercased() + " "), run: {
                    self.saved.searches[name.lowercased()] = Search(n: name, u: self.fix(val)); self.save()
                })]
            }
        }

        if kw == "clip" {
            for t in saved.clips where rest.isEmpty || t.localizedCaseInsensitiveContains(rest) {
                let first = t.components(separatedBy: "\n").first ?? t
                out.append(Item(icon: "📋", title: String(first.prefix(90)), sub: t.count > 90 ? "\(t.count) characters" : "Enter copies it again",
                                del: { self.saved.clips.removeAll { $0 == t }; self.save() }, run: { self.copy(t) }))
            }
            if saved.clips.isEmpty { out.append(Item(icon: "💡", title: "Nothing here yet", sub: "Anything you copy shows up here", after: .stay)) }
            return out
        }
        if kw == "snip" {
            for x in saved.snips where rest.isEmpty || x.n.lowercased().contains(rest.lowercased()) {
                out.append(Item(icon: "✂️", title: x.n, sub: String(expand(x.t).prefix(100)),
                                del: { self.saved.snips.removeAll { $0.n == x.n }; self.save() }, run: { self.copy(self.expand(x.t)) }))
            }
            out.append(Item(icon: "💡", title: "Add one: snip add name = text", sub: "Use {date} and {time} for live values", after: .set("snip add ")))
            return out
        }
        if kw == "bm" {
            for x in saved.bms where rest.isEmpty || (x.n + x.u).lowercased().contains(rest.lowercased()) {
                out.append(Item(icon: "🔖", title: x.n, sub: x.u,
                                del: { self.saved.bms.removeAll { $0.n == x.n }; self.save() }, run: { self.openURL(x.u) }))
            }
            out.append(Item(icon: "💡", title: "Add one: bm add name = address", after: .set("bm add ")))
            return out
        }
        if kw == "search" || kw == "keys" {
            for (k, v) in allSearches.sorted(by: { $0.key < $1.key }) {
                let custom = saved.searches[k] != nil
                out.append(Item(icon: "🔎", title: "\(k) · \(v.n)", sub: v.u, after: .set(k + " "),
                                del: custom ? { self.saved.searches[k] = nil; self.save() } : nil))
            }
            return out
        }

        if kw == "timer", !rest.isEmpty {
            let digits = String(rest.prefix { $0.isNumber || $0 == "." })
            if let n = Double(digits) {
                let unit = rest.dropFirst(digits.count).trimmingCharacters(in: .whitespaces).lowercased().first ?? "m"
                let secs = n * (unit == "s" ? 1 : (unit == "h" ? 3600 : 60))
                let label = "\(digits)\(unit)"
                out.append(Item(icon: "⏰", title: "Start a \(label) timer", sub: "You get a notification when it ends", run: {
                    let c = UNUserNotificationCenter.current()
                    c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
                    let content = UNMutableNotificationContent()
                    content.title = "Jeeves"; content.body = "\(label) timer is up"; content.sound = .default
                    let trig = UNTimeIntervalNotificationTrigger(timeInterval: max(1, secs), repeats: false)
                    c.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trig))
                }))
            }
            return out
        }

        // small tools
        func tool(_ icon: String, _ v: String, _ what: String) {
            out.append(Item(icon: icon, title: v, sub: what + " · Enter copies", run: { self.copy(v) }))
        }
        if kw == "uuid" { tool("🆔", UUID().uuidString, "New UUID") }
        if kw == "pass" {
            let chars = Array("abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*?")
            tool("🔑", String((0..<20).map { _ in chars.randomElement()! }), "Random 20-character password")
        }
        if kw == "now" {
            let d = Date()
            tool("🕒", d.formatted(date: .abbreviated, time: .standard), "Local time")
            tool("🕒", ISO8601DateFormatter().string(from: d), "ISO 8601")
            tool("🕒", String(Int(d.timeIntervalSince1970)), "Unix timestamp")
        }
        if !rest.isEmpty {
            switch kw {
            case "b64": tool("🛠️", Data(rest.utf8).base64EncodedString(), "Base64 encode")
            case "unb64": if let d = Data(base64Encoded: rest), let s = String(data: d, encoding: .utf8) { tool("🛠️", s, "Base64 decode") }
            case "enc": tool("🛠️", enc(rest), "URL encode")
            case "upper": tool("🛠️", rest.uppercased(), "Uppercase")
            case "lower": tool("🛠️", rest.lowercased(), "Lowercase")
            default: break
            }
        }
        if q.hasPrefix("#"), q.count == 4 || q.count == 7 {
            var h = String(q.dropFirst())
            if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
            if let n = Int(h, radix: 16) { tool("🎨", "rgb(\(n >> 16), \((n >> 8) & 255), \(n & 255))", "#\(h)") }
        }
        func sys(_ arg: String) { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = [arg]; try? p.run() }
        if kw == "sleep" { out.append(Item(icon: "😴", title: "Put the Mac to sleep", run: { sys("sleepnow") })) }
        if kw == "lock" { out.append(Item(icon: "🔒", title: "Turn off the display", sub: "Locks if a password is required after sleep", run: { sys("displaysleepnow") })) }

        // web search keywords
        let a = allSearches
        let isSearch = a[kw] != nil
        if let s = a[kw] {
            if rest.isEmpty {
                out.append(Item(icon: "🔎", title: s.n + " search", sub: "Keep typing your query", after: .set(kw + " ")))
            } else {
                out.append(Item(icon: "🔎", title: "Search \(s.n) for “\(rest)”", sub: s.u.components(separatedBy: "/").dropFirst(2).first ?? "",
                                run: { self.openURL(s.u.replacingOccurrences(of: "{q}", with: self.enc(rest))) }))
            }
        }

        // apps, bookmarks, snippets
        if !(isSearch && !rest.isEmpty) {
            for app in matchApps(lq) {
                out.append(Item(icon: "", title: app.name, sub: app.path, image: NSWorkspace.shared.icon(forFile: app.path),
                                run: { NSWorkspace.shared.open(URL(fileURLWithPath: app.path)) }))
            }
        }
        for x in saved.bms.filter({ ($0.n + $0.u).lowercased().contains(lq) }).prefix(5) {
            out.append(Item(icon: "🔖", title: x.n, sub: x.u, run: { self.openURL(x.u) }))
        }
        for x in saved.snips.filter({ $0.n.lowercased().contains(lq) }).prefix(4) {
            out.append(Item(icon: "✂️", title: "Snippet: " + x.n, sub: String(expand(x.t).prefix(100)), run: { self.copy(self.expand(x.t)) }))
        }
        if q.range(of: #"^(https?://)?[\w-]+(\.[\w-]+)+(:\d+)?(/\S*)?$"#, options: .regularExpression) != nil {
            out.append(Item(icon: "🌐", title: "Open " + q, sub: fix(q), run: { self.openURL(self.fix(q)) }))
        }
        if !isSearch || rest.isEmpty {
            for k in ["g", "ddg", "yt"] {
                if let s = a[k] {
                    out.append(Item(icon: "🔎", title: "Search \(s.n) for “\(q)”", sub: "Fallback search",
                                    run: { self.openURL(s.u.replacingOccurrences(of: "{q}", with: self.enc(q))) }))
                }
            }
        }
        return out
    }
}
