import Foundation

enum ManagementLocalizationError: Error {
    case missingLocalization(String)
    case missingKey(String, localization: String)
}

enum ManagementLocalization {
    static func strings(locale: String) throws -> [String: String] {
        let bundle = packagedResourceBundle ?? Bundle.module
        guard let path = bundle.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: locale
        ), let strings = NSDictionary(contentsOfFile: path) as? [String: String] else {
            throw ManagementLocalizationError.missingLocalization(locale)
        }
        return strings
    }

    static func string(_ key: String) -> String {
        let bundle = packagedResourceBundle ?? Bundle.module
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func text(_ key: String, locale: String) throws -> String {
        let strings = try strings(locale: locale)
        guard let value = strings[key] else {
            throw ManagementLocalizationError.missingKey(key, localization: locale)
        }
        return value
    }

    private static var packagedResourceBundle: Bundle? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        return Bundle(url: resources.appendingPathComponent(
            "MyOmarchy_MyOmarchy.bundle",
            isDirectory: true
        ))
    }
}
