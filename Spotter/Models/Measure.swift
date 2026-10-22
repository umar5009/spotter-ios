import Foundation

/// Display units for body weight, lift load, and height.
/// Stored values stay in kilograms and centimetres.
enum Measure {
    static func format(_ value: Double, places: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...places)))
    }

    static func number(_ raw: String) -> Double? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, let value = Double(normalized) else { return nil }
        return value
    }

    enum Weight: String, CaseIterable, Identifiable {
        case kilograms
        case pounds

        var id: String { rawValue }
        var symbol: String { self == .kilograms ? "kg" : "lb" }
        var title: String { self == .kilograms ? String(localized: "Kilograms") : String(localized: "Pounds") }
        var placeholder: String { self == .kilograms ? "72.0" : "160" }
        var step: Double { self == .kilograms ? 2.5 : 5 }

        private static let poundsPerKilogram = 2.2046226218

        func fromKilograms(_ kg: Double) -> Double {
            self == .kilograms ? kg : kg * Self.poundsPerKilogram
        }

        func toKilograms(_ value: Double) -> Double {
            self == .kilograms ? value : value / Self.poundsPerKilogram
        }

        func accepts(_ displayValue: Double) -> Bool {
            (20...400).contains(toKilograms(displayValue))
        }

        var rangeDescription: String {
            self == .kilograms ? String(localized: "20 and 400 kg") : String(localized: "44 and 880 lb")
        }
    }

    enum Height: String, CaseIterable, Identifiable {
        case centimeters
        case feet

        var id: String { rawValue }
        var symbol: String { self == .centimeters ? "cm" : "ft" }
        var title: String { self == .centimeters ? String(localized: "Centimetres") : String(localized: "Feet & inches") }

        func text(cm: Double) -> String {
            switch self {
            case .centimeters:
                return String(localized: "\(Measure.format(cm, places: 1)) cm")
            case .feet:
                let parts = Self.parts(cm: cm)
                return String(localized: "\(parts.feet) ft \(parts.inches) in")
            }
        }

        static func parts(cm: Double) -> (feet: Int, inches: Int) {
            let totalInches = cm / 2.54
            var feet = Int(totalInches / 12)
            var inches = Int((totalInches - Double(feet * 12)).rounded())
            if inches == 12 {
                feet += 1
                inches = 0
            }
            return (max(0, feet), max(0, inches))
        }

        static func centimeters(feet: Double, inches: Double) -> Double {
            feet * 30.48 + inches * 2.54
        }

        static func accepts(cm: Double) -> Bool { (90...250).contains(cm) }
    }
}
