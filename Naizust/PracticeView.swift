import SwiftUI
import Translation

@main struct NaizustApp: App {
    var body: some Scene { WindowGroup { PracticeView() } }
}

struct PracticeView: View {
    enum Page { case library, edit, read, speak, review }
    @State private var page = Page.library
    @State private var shelf: [Piece] = []
    @State private var piece = Piece()
    @State private var attempt = Attempt(mode: .exact, source: "")
    @StateObject private var voice = Voice()
    @Environment(\.scenePhase) private var phase
    @State private var reading = ""
    @State private var hint = ""
    @State private var position = 0
    @State private var anchor = 0
    @State private var shift = ""
    @State private var sourceWords: [String] = []
    @State private var chunks: [String] = []
    @State private var offsets: [Int] = []
    @State private var history = false
    @State private var busy = false
    @State private var translate: TranslationSession.Configuration?
    @State private var problem = ""
    @State private var editingTranscript = false
    @State private var correction = ""
    @State private var loaded = false
    let green = Color(red: 0.10, green: 0.31, blue: 0.24)
    let paper = Color(red: 0.97, green: 0.96, blue: 0.92)
    private var storage: URL { URL.documentsDirectory.appending(path: "Library.json") }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case .library: library
                    case .edit: editor
                    case .read: reader
                    case .speak: stage
                    case .review: review
                    }
                    if !problem.isEmpty { Text(problem).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            }.scrollDismissesKeyboard(.interactively)
            .background(paper).navigationTitle(title)
            .toolbar {
                if page != .library && page != .speak && !busy {
                    ToolbarItem(placement: .topBarLeading) { Button("Библиотека") { voice.silence(); problem = ""; page = .library } }
                }
            }
        }.tint(green).preferredColorScheme(.light)
        .onAppear { load() }
        .onChange(of: phase) { _, value in
            if value == .background && page == .speak { voice.stop() }
        }
        .translationTask(translate) { session in
            guard busy, page == .review else { return }
            await analyze(session)
        }
    }
    var title: String {
        switch page {
        case .library: return "Мои тексты"
        case .edit: return "Текст и цель"
        case .read: return piece.title
        case .speak: return "Твоя репетиция"
        case .review: return "Разбор рассказа"
        }
    }
    func load() {
        guard !loaded else { return }; loaded = true
        do {
            if FileManager.default.fileExists(atPath: storage.path) {
                shelf = try JSONDecoder().decode([Piece].self, from: Data(contentsOf: storage))
            } else if let old = UserDefaults.standard.string(forKey: "practice.text"), !old.isEmpty {
                shelf = [Piece(title: String(old.prefix(45)), body: old)]
            }
        } catch { problem = "Не удалось открыть библиотеку."; loaded = false }
    }
    @discardableResult func save() -> Bool {
        guard loaded else { problem = "Библиотека недоступна."; return false }
        var all = shelf
        if let i = all.firstIndex(where: { $0.id == piece.id }) { all[i] = piece } else { all.insert(piece, at: 0) }
        do { try JSONEncoder().encode(all).write(to: storage, options: .atomic); shelf = all; return true }
        catch { problem = "Не удалось сохранить текст."; return false }
    }
    func button(_ label: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).padding(8)
        }.buttonStyle(.borderedProminent)
    }
    var library: some View {
        Group {
            button("Добавить текст", "plus") { piece = Piece(); problem = ""; page = .edit }
            if shelf.isEmpty { ContentUnavailableView("Первый рассказ", systemImage: "text.book.closed", description: Text("Добавь стихотворение, доклад или отрывок для репетиции.")) }
            ForEach(shelf) { item in
                Button {
                    piece = item; reading = item.body; history = false; problem = ""; page = .read
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.mode.rawValue).font(.caption.weight(.semibold)).foregroundStyle(green)
                        Text(item.title).font(.system(.title2, design: .serif)).foregroundStyle(.primary)
                        Text(item.body).lineLimit(2).foregroundStyle(.secondary)
                        Text("Попыток: \(item.attempts.count)").font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.white, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
            }
        }
    }
    var editor: some View {
        Group {
            TextField("Название", text: $piece.title).textFieldStyle(.roundedBorder)
            TextEditor(text: $piece.body).frame(minHeight: 200).padding(8).background(.white).accessibilityLabel("Текст для рассказа")
            modePicker
            if piece.mode == .meaning {
                Text("Ключевые мысли").font(.headline)
                Text("По одной на строку. Если оставить пустым, приложение возьмёт предложения оригинала.").font(.footnote)
                TextEditor(text: $piece.ideas).frame(minHeight: 90)
            }
            button("Сохранить и читать", "book") {
                if piece.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { piece.title = String(piece.body.prefix(48)) }
                if save() { reading = piece.body; history = false; page = .read }
            }.disabled(words(piece.body).isEmpty)
        }
    }
    var modePicker: some View {
        Picker("Режим", selection: $piece.mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
    }
    var reader: some View {
        Group {
            modePicker
            button("Готов рассказать", "mic.fill") { launch() }
            Text(reading).font(.system(.title3, design: .serif)).lineSpacing(6)
            Button("Редактировать текст и ключевые мысли") { page = .edit }
            if !piece.attempts.isEmpty {
                DisclosureGroup("История репетиций", isExpanded: $history) {
                    ForEach(piece.attempts.reversed()) { item in
                        Button {
                            voice.reset(); attempt = item; editingTranscript = false; page = .review
                        } label: { VStack(alignment: .leading) {
                            Text(item.date.formatted())
                            Text(item.mode.rawValue + " · подсказок: \(item.hints.count)").font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4) }
                    }
                }
            }
        }
    }
    func launch() {
        guard save() else { return }
        voice.reset(); position = 0; hint = ""; problem = ""; editingTranscript = false
        sourceWords = words(reading)
        chunks = piece.mode == .meaning && reading == piece.body && !fragments(piece.ideas).isEmpty ? fragments(piece.ideas) : fragments(reading)
        if chunks.isEmpty { chunks = [reading] }
        var n = 0
        offsets = chunks.map { line in defer { n += words(line).count }; return n }
        if piece.mode == .meaning { sourceWords = chunks.flatMap(words) }
        attempt = Attempt(mode: piece.mode, source: reading)
        attempt.points = chunks
        page = .speak
        Task { await voice.start() }
    }
    var sectionIndex: Int { offsets.lastIndex(where: { $0 <= position }) ?? 0 }
    func showHint() {
        let i = min(sectionIndex,chunks.count-1)
        if piece.mode == .exact && position >= sourceWords.count {
            hint = "Конец текста"; return
        }
        if hint.isEmpty {
            anchor = position
            hint = piece.mode == .exact ? sourceWords[position] : "Вспомни мысль: " + words(chunks[i]).prefix(4).joined(separator: " ") + "…"
        } else { hint = chunks[i] }
        shift = voice.transcript
        attempt.hints.append(hint)
    }
    var stage: some View {
        Group {
            Label(voice.active ? "Идёт запись" : (voice.pending ? "Подготовка микрофона" : "Пауза"), systemImage: voice.active ? "record.circle.fill" : "pause.circle")
                .font(.headline).foregroundStyle(green)
            Text(piece.title).font(.system(.largeTitle, design: .serif))
            if !voice.issue.isEmpty { Text(voice.issue).font(.callout) }
            if !hint.isEmpty { Text(hint).font(.title2).padding().frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
            button("Что дальше?", "eye") { showHint() }
            Menu("Выбрать фрагмент · \(sectionIndex+1) из \(chunks.count)") {
                ForEach(chunks.indices, id: \.self) { i in Button("Фрагмент \(i+1)") { position = offsets[i]; hint = ""; showHint() } }
            }
            HStack {
                Button(voice.active ? "Пауза" : "Продолжить") { if voice.active { voice.stop() } else { Task { await voice.start() } } }.disabled(voice.pending)
                Spacer()
                Button("Закончить рассказ") { finish() }
            }.buttonStyle(.bordered)
        }.onChange(of: voice.transcript) { _, text in
            position = nextPosition(source: sourceWords, speech: text, near: position)
            if !hint.isEmpty && text != shift { hint = "" }
        }
    }
    func finish() {
        voice.finish()
        attempt.transcript = voice.transcript; attempt.audio = voice.file?.lastPathComponent
        if !voice.issue.isEmpty { attempt.note = voice.issue }
        page = .review
        calculate()
    }
    func persistAttempt() {
        if let i = piece.attempts.firstIndex(where: { $0.id == attempt.id }) { piece.attempts[i] = attempt }
        else { piece.attempts.append(attempt) }
        _ = save()
    }
    func calculate() {
        attempt.findings = []; attempt.note = ""
        if words(attempt.transcript).isEmpty {
            attempt.note = "Не удалось разобрать речь. Прослушай запись или введи расшифровку."; persistAttempt(); return
        }
        if attempt.mode == .exact {
            attempt.findings = exactFindings(source: attempt.source, transcript: attempt.transcript, timing: voice.timing)
            if attempt.findings.isEmpty { attempt.note = "Слова совпадают с оригиналом." }
            persistAttempt()
        } else {
            attempt.note = "Смысловой разбор ожидает проверки."; persistAttempt()
            guard MeaningReview.available else {
                attempt.note = "Для смыслового разбора нужна доступная локальная модель Apple Intelligence. Можно вернуться к этой записи позже."; persistAttempt(); return
            }
            busy = true
            if MeaningReview.needsTranslation {
                if translate == nil { translate = .init(source: .init(identifier: "ru"), target: .init(identifier: "en")) }
                else { translate?.invalidate() }
            } else { Task { await analyze(nil) } }
        }
    }
    func analyze(_ session: TranslationSession?) async {
        do {
            attempt.findings = try await MeaningReview.run(ideas: attempt.points ?? fragments(attempt.source), transcript: attempt.transcript, translator: session)
            attempt.note = session == nil ? "Проверено моделью на iPhone." : "Проверено на iPhone через локальный перевод на английский. Сверь спорные места с цитатами."
        } catch { attempt.note = "Смысловой разбор недоступен. Проверь доступность модели и языковых пакетов. " + error.localizedDescription }
        busy = false; persistAttempt()
    }
    var review: some View {
        Group {
            Text(attempt.mode.rawValue).font(.headline).foregroundStyle(green)
            if busy { ProgressView("Проверяем смысл на iPhone…") }
            if !attempt.note.isEmpty { Text(attempt.note) }
            if let audio = attempt.audio {
                HStack { Button("Слушать запись") { voice.listen(audio) }; Button("Остановить") { voice.silence() } }
            }
            if !voice.issue.isEmpty { Text(voice.issue).font(.footnote) }
            DisclosureGroup("Подсказки · \(attempt.hints.count)") {
                ForEach(attempt.hints.indices, id: \.self) { i in Text(attempt.hints[i]) }
            }
            DisclosureGroup("Расшифровка", isExpanded: $editingTranscript) {
                TextEditor(text: $correction).frame(minHeight: 130)
                Button("Пересчитать разбор") { attempt.transcript = correction; editingTranscript = false; calculate() }.disabled(busy)
            }.onChange(of: editingTranscript) { _, open in if open { correction = attempt.transcript } }
            ForEach(attempt.findings) { f in
                VStack(alignment: .leading, spacing: 8) {
                    Text(f.label).font(.headline)
                    if !f.original.isEmpty { Text("В тексте · " + f.original) }
                    if !f.spoken.isEmpty { Text("В рассказе · " + f.spoken).foregroundStyle(.secondary) }
                    if let s = f.second, let audio = attempt.audio { Button("Послушать это место") { voice.listen(audio, at: s) } }
                    if f.label != "Мысль передана" {
                        Button("Повторить фрагмент") { voice.silence(); piece.mode = attempt.mode; reading = f.repeatText; page = .read }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
            if !busy { button("Рассказать целиком", "arrow.counterclockwise") { voice.silence(); reading = piece.body; page = .read } }
        }
    }
}
