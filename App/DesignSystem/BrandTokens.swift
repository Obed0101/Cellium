import SwiftUI

extension Color {
    init(hex: String) {
        let normalized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: normalized).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

enum CelliumBrand {
    static let background = Color(hex: "0A1013")
    static let surface = Color(hex: "111A1E")
    static let elevated = Color(hex: "182428")
    static let border = Color(hex: "2A383D")
    static let foreground = Color(hex: "E8ECEA")
    static let muted = Color(hex: "95A4A8")
    static let accent = Color(hex: "B5CBCB")
    static let accentStrong = Color(hex: "D6E7E4")
    static let signal = Color(hex: "9ECBC3")
    static let warning = Color(hex: "E2B66D")
    static let critical = Color(hex: "E28D91")
    static let info = Color(hex: "9EBFD4")
}

enum CelliumAppResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }
}
