import Foundation

/// Text in the user's language. The English text is the key; Dutch is in nl.lproj/Localizable.strings.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}

enum Build {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    static var number: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    static var versionString: String { "\(version) (\(number))" }
    static let copyright = "© 2026 Filip Haegdorens"
}

/// Screenshots made on the build server cannot show the blurred background; they use a plain one.
enum Look {
    static var solidBackground = false
}
