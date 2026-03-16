import Foundation

public enum MassUnit: String, Codable, CaseIterable, Identifiable {
    case kilograms
    case pounds
    case stones

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .kilograms:
            return "Kilograms"
        case .pounds:
            return "Pounds"
        case .stones:
            return "Stones"
        }
    }

    public func toKilograms(_ value: Double) -> Double {
        switch self {
        case .kilograms:
            return value
        case .pounds:
            return value * 0.453_592_37
        case .stones:
            return value * 6.350_293_18
        }
    }
}
