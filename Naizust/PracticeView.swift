import SwiftUI
import AVFoundation

@main
struct NaizustApp: App {
    var body: some Scene { WindowGroup { PracticeView() } }
}

struct PracticeView: View {
    enum Stage { case write, read, tell, check, done }
    @AppStorage("practice.text") private var draft = ""
    @AppStorage("practice.lastText") private var lastText = ""
    @AppStorage("practice.lastDate") private var lastDate = 0.0
    @State private var stage: Stage = .write
    @State private var passages: [String] = []
    @State private var difficult: Set<Int> = []
    @State private var hintCount = 0
    @State private var hintIndex = 0
    @State private var hint = ""
    @State private var fullRound = true
    @State private var started = Date()
    @State private var voice = AVSpeechSynthesizer()
    @FocusState private var editing: Bool
    private let ink = Color(red: 0.13, green: 0.27, blue: 0.22)
    private var clean: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canRecall: Bool { !clean.isEmpty && clean == lastText }
    private var heading: String {
        switch stage {
        case .write: return "Твой текст"
        case .read: return "Прочитай вслух"
        case .tell: return "Рассказывай"
        case .check: return "Сверь с текстом"
        case .done: return "Репетиция завершена"
        }
    }
    private func prepare(skipReading: Bool = false) {
        editing = false
        passages = clean.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        difficult = []
        fullRound = true
        if skipReading { begin() } else { stage = .read }
    }
    private func begin() {
        hintCount = 0
        hintIndex = 0
        hint = ""
        started = Date()
        stage = .tell
    }
    private func showHint() {
        let text = passages[hintIndex]
        hint = text.split(whereSeparator: { $0.isWhitespace }).prefix(3).joined(separator: " ")
        hintCount += 1
        voice.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: hint)
        utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        voice.speak(utterance)
    }
    private func finishReview() {
        if difficult.isEmpty {
            if fullRound {
                lastText = clean
                lastDate = Date().timeIntervalSince1970
            }
            stage = .done
        } else {
            passages = difficult.sorted().map { passages[$0] }
            difficult = []
            fullRound = false
            stage = .read
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Наизусть", systemImage: "book.pages").font(.headline)
                Spacer()
                if stage != .write {
                    Button("К тексту") {
                        voice.stopSpeaking(at: .immediate)
                        stage = .write
                    }
                }
            }
            Text(heading).font(.system(.largeTitle, design: .serif, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            switch stage {
            case .write:
                Text("Напиши или вставь то, что хочешь выучить.")
                TextEditor(text: $draft).focused($editing).scrollContentBackground(.hidden)
                    .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Текст для репетиции")
                if canRecall {
                    Text("Последняя полная репетиция: " + Date(timeIntervalSince1970: lastDate).formatted(date: .abbreviated, time: .omitted)).font(.footnote)
                    Button("Рассказать по памяти") { prepare(skipReading: true) }
                }
                action("Перейти к чтению") { prepare() }.disabled(clean.isEmpty)
            case .read:
                ScrollView { VStack(alignment: .leading, spacing: 14) {
                    ForEach(passages.indices, id: \.self) { i in Text(passages[i]) }
                }.frame(maxWidth: .infinity, alignment: .leading) }
                .font(.system(.title3, design: .serif)).lineSpacing(5)
                action("Готов рассказать") { begin() }
            case .tell:
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "waveform").font(.largeTitle)
                    Text(started, style: .timer).font(.title.monospacedDigit())
                    Text(hint.isEmpty ? "Начинай, когда удобно." : hint).font(.title3)
                    if passages.count > 1 {
                        Picker("Подсказка для фрагмента", selection: $hintIndex) {
                            ForEach(passages.indices, id: \.self) { i in Text("Фрагмент \(i + 1)").tag(i) }
                        }.onChange(of: hintIndex) { _, _ in hint = "" }
                    }
                    Button("Подсказать начало") { showHint() }
                }.frame(maxWidth: .infinity)
                Spacer()
                action("Закончил рассказ") {
                    voice.stopSpeaking(at: .immediate)
                    stage = .check
                }
            case .check:
                Text("Отметь фрагменты, которые хочется повторить.").font(.subheadline)
                ScrollView { VStack(spacing: 10) {
                    ForEach(passages.indices, id: \.self) { i in
                        Button {
                            if difficult.contains(i) { difficult.remove(i) } else { difficult.insert(i) }
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: difficult.contains(i) ? "checkmark.circle.fill" : "circle")
                                Text(passages[i]).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding().background(.white, in: RoundedRectangle(cornerRadius: 14))
                        }.accessibilityValue(difficult.contains(i) ? "Выбрано" : "Не выбрано")
                    }
                } }
                Text("Подсказок за этот рассказ: \(hintCount)").font(.footnote)
                action(difficult.isEmpty ? "Завершить" : "Повторить выбранное") { finishReview() }
            case .done:
                Spacer()
                Text(fullRound ? "В следующий раз начни с кнопки «Рассказать по памяти»." : "Теперь попробуй связать отработанные фрагменты в целый рассказ.").font(.title3)
                Spacer()
                action("Рассказать целиком") { prepare(skipReading: true) }
            }
        }.padding(22).foregroundStyle(ink).tint(ink)
        .background(Color(red: 0.97, green: 0.96, blue: 0.92))
        .preferredColorScheme(.light)
    }
    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
        }.buttonStyle(.borderedProminent).foregroundStyle(.white)
    }
}
