import Foundation

/// Deler tekst fra en CSV-fil i rader og felt.
///
/// Forstår anførselstegn (`"a;b"`, `""` for et anførselstegn i feltet), felt over flere linjer og
/// avsluttende skilletegn, og hopper over tomme rader. Feltene trimmes for mellomrom.
/// `nonisolated` fordi den er ren beregning uten tilknytning til brukergrensesnittet.
nonisolated enum CSVTokenizer {
    /// Skilletegnene som prøves, i den rekkefølgen de foretrekkes ved likt antall.
    static let candidateDelimiters: [Character] = [";", "\t", ","]

    /// Hvor mange linjer i starten som brukes til å finne skilletegnet.
    private static let sampleLineCount = 30

    /// Skilletegnet som forekommer oftest utenfor anførselstegn i de første linjene, der
    /// overskriftsraden står. Semikolon foretrekkes foran tab, og tab foran komma, siden norske
    /// banker bruker komma som desimaltegn i beløp.
    static func detectDelimiter(in text: String) -> Character {
        var counts: [Character: Int] = [:]
        var inQuotes = false
        var lines = 0
        for character in text {
            if character == "\"" {
                inQuotes.toggle()
            } else if !inQuotes {
                if character == "\n" {
                    lines += 1
                    if lines >= sampleLineCount { break }
                } else if candidateDelimiters.contains(character) {
                    counts[character, default: 0] += 1
                }
            }
        }
        var best: Character = ";"
        var bestCount = 0
        for delimiter in candidateDelimiters {
            let count = counts[delimiter] ?? 0
            if count > bestCount {
                best = delimiter
                bestCount = count
            }
        }
        return best
    }

    /// Radene i teksten. Uten `delimiter` finnes skilletegnet med `detectDelimiter`.
    static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        let delimiter = delimiter ?? detectDelimiter(in: text)
        let characters = Array(text)

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        func finishField() {
            row.append(field.trimmingCharacters(in: .whitespaces))
            field = ""
        }

        func finishRow() {
            finishField()
            // Avsluttende skilletegn gir tomme felt til slutt.
            while let last = row.last, last.isEmpty {
                row.removeLast()
            }
            if !row.isEmpty {
                rows.append(row)
            }
            row = []
        }

        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"", field.allSatisfy({ $0 == " " }) {
                // Et anførselstegn først i feltet åpner et felt med anførselstegn.
                field = ""
                inQuotes = true
            } else if character == delimiter {
                finishField()
            } else if character == "\n" {
                finishRow()
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            finishRow()
        }
        return rows
    }
}
