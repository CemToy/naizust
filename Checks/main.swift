import Foundation

let original = "Вода расширяется при замерзании."
func changes(_ speech: String) -> [Finding] {
    exactFindings(source: original, transcript: speech, timing: [])
}
precondition(changes("ВОДА расширяется при замерзании!").isEmpty)
precondition(changes("Вода при замерзании").first?.original == "расширяется")
precondition(changes("Вода сжимается при замерзании").first?.spoken == "сжимается")
precondition(changes("Вода тоже расширяется при замерзании").first?.label == "Добавлено")
precondition(changes("").first?.original == "Вода расширяется при замерзании")
precondition(nextPosition(source: words(original), speech: "вода расширяется", near: 0) == 2)
precondition(exactFindings(source: "да да", transcript: "да", timing: []).count == 1)
print("Recall checks passed")
