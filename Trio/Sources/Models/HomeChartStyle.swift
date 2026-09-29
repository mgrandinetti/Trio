import Foundation

/// Presentation style of the Home screen. `.trio` is the stock layout; `.detailed` swaps in
/// the alternative header and chart stack. Display only: nothing therapeutic reads it.
enum HomeChartStyle: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case trio
    case detailed

    var displayName: String {
        switch self {
        case .trio:
            return String(localized: "Trio", comment: "Home chart style option")
        case .detailed:
            return String(localized: "Detailed", comment: "Home chart style option")
        }
    }
}
