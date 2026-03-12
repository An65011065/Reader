import SwiftUI

class ReadingSettings: ObservableObject {
    @AppStorage("fontSize")    var fontSize: Double  = 18
    @AppStorage("fontFamily")  var fontFamily: String = FontFamily.georgia.rawValue
    @AppStorage("theme")       var themeRaw: String  = Theme.sepia.rawValue
    @AppStorage("lineHeight")  var lineHeight: Double = 1.6
    @AppStorage("marginSize")  var marginSize: Double = 48   // horizontal pt
    @AppStorage("twoPageMode") var twoPageMode: Bool  = false

    var theme: Theme {
        get { Theme(rawValue: themeRaw) ?? .sepia }
        set { themeRaw = newValue.rawValue }
    }

    var font: FontFamily {
        get { FontFamily(rawValue: fontFamily) ?? .georgia }
        set { fontFamily = newValue.rawValue }
    }

    enum Theme: String, CaseIterable {
        case white, sepia, dark

        var background: Color {
            switch self {
            case .white: return Color(red: 1, green: 1, blue: 1)
            case .sepia: return Color(red: 0.98, green: 0.97, blue: 0.93)
            case .dark:  return Color(red: 0.11, green: 0.11, blue: 0.12)
            }
        }
        var foreground: Color {
            switch self {
            case .white, .sepia: return Color(red: 0.13, green: 0.13, blue: 0.13)
            case .dark:          return Color(red: 0.88, green: 0.88, blue: 0.88)
            }
        }
        var backgroundHex: String {
            switch self {
            case .white: return "#FFFFFF"
            case .sepia: return "#F9F6ED"
            case .dark:  return "#1C1C1E"
            }
        }
        var foregroundHex: String {
            switch self {
            case .white, .sepia: return "#212121"
            case .dark:          return "#E0E0E0"
            }
        }
        var label: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .white: return "sun.max"
            case .sepia: return "book.closed"
            case .dark:  return "moon"
            }
        }
    }

    enum FontFamily: String, CaseIterable {
        case georgia      = "Georgia"
        case palatino     = "Palatino"
        case timesNewRoman = "TimesNewRomanPSMT"
        case helvetica    = "Helvetica Neue"
        case charter      = "Charter"

        var displayName: String {
            switch self {
            case .georgia:      return "Georgia"
            case .palatino:     return "Palatino"
            case .timesNewRoman: return "Times New Roman"
            case .helvetica:    return "Helvetica"
            case .charter:      return "Charter"
            }
        }
        var cssFamily: String {
            switch self {
            case .georgia:      return "Georgia, serif"
            case .palatino:     return "'Palatino Linotype', Palatino, serif"
            case .timesNewRoman: return "'Times New Roman', Times, serif"
            case .helvetica:    return "'Helvetica Neue', Helvetica, sans-serif"
            case .charter:      return "Charter, 'Bitstream Charter', serif"
            }
        }
    }
}
