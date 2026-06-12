import Foundation

enum PlateParser {
    static func extractPlate(from textCandidates: [String]) -> String? {
        for candidate in textCandidates {
            if let plate = extractPlate(from: candidate) {
                return plate
            }
        }

        return nil
    }

    private static func extractPlate(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawCharacters = Array(trimmed)

        guard rawCharacters.count == 6 || rawCharacters.count == 7 else {
            return nil
        }

        if rawCharacters.count == 7 {
            guard rawCharacters[3] == " " else {
                return nil
            }
        }

        let scalars = trimmed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        guard scalars.count == 6 else {
            return nil
        }

        let characters = scalars.map { Character(String($0)) }
        guard characters.allSatisfy({ $0.isASCIIUppercaseLetter || $0.isNumber }) else {
            return nil
        }

        return SwedishPlateCandidate(characters: characters)?.formatted
    }
}

private struct SwedishPlateCandidate {
    let formatted: String

    init?(characters: [Character]) {
        guard characters.count == 6 else {
            return nil
        }

        let letters = characters.prefix(3).compactMap(Self.letterValue)
        let digits = characters.dropFirst(3).prefix(2).compactMap(Self.digitValue)
        let final = Self.finalValue(characters[5])

        guard letters.count == 3, digits.count == 2, let final else {
            return nil
        }

        formatted = "\(String(letters)) \(String(digits))\(final)"
    }

    private static func letterValue(_ character: Character) -> Character? {
        character.isASCIIUppercaseLetter ? character : nil
    }

    private static func digitValue(_ character: Character) -> Character? {
        switch character {
        case "0"..."9":
            return character
        default:
            return nil
        }
    }

    private static func finalValue(_ character: Character) -> Character? {
        if character.isASCIIUppercaseLetter || character.isNumber {
            return character
        }

        return nil
    }
}

private extension Character {
    var isASCIIUppercaseLetter: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else {
            return false
        }

        return scalar.value >= 65 && scalar.value <= 90
    }

    var isNumber: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else {
            return false
        }

        return scalar.value >= 48 && scalar.value <= 57
    }
}
