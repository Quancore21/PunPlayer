//
// PunPlayer — Core/Localization.swift
// Lightweight runtime localization for plain strings produced outside SwiftUI.
// SwiftUI Text literals additionally use the environment's Locale.
// Licensed under GPLv3.
//

import Foundation

enum AppLocalization {
    static let preferenceKey = "punplayer.language"

    static var preferredCode: String? {
        switch UserDefaults.standard.string(forKey: preferenceKey) ?? "system" {
        case "ru": return "ru"
        case "en": return "en"
        default: return nil
        }
    }

    static var locale: Locale {
        if let code = preferredCode { return Locale(identifier: code) }
        return .current
    }

    static var isRussian: Bool {
        if let code = preferredCode { return code == "ru" }
        return Locale.current.languageCode == "ru"
    }

    private static var selectedBundle: Bundle {
        guard let code = preferredCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    static func string(_ key: String, defaultValue: String? = nil) -> String {
        let localized = selectedBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        if localized != key { return localized }

        // Keep core-generated summaries localized even in the SwiftPM test target, where the
        // app's .lproj resource bundles are intentionally not loaded.
        if isRussian {
            switch key {
            case "import.summary.imported": return "Импортировано"
            case "import.summary.and": return "и"
            case "import.summary.nothing": return "Нечего импортировать."
            default: break
            }
        }
        return defaultValue ?? key
    }

    static func format(_ key: String, defaultFormat: String, _ arguments: CVarArg...) -> String {
        String(format: string(key, defaultValue: defaultFormat), locale: locale, arguments: arguments)
    }

    /// Language-aware short counts, including the three common Russian plural forms.
    static func count(_ count: Int, noun: String) -> String {
        guard isRussian else {
            let english: (String, String)
            switch noun {
            case "song": english = ("song", "songs")
            case "lyrics file": english = ("lyrics file", "lyrics files")
            case "file": english = ("file", "files")
            case "minute": english = ("min", "min")
            default: english = (noun, noun + "s")
            }
            return "\(count) \(count == 1 ? english.0 : english.1)"
        }

        let value = abs(count)
        let lastTwo = value % 100
        let form: Int
        if (11...14).contains(lastTwo) {
            form = 2
        } else {
            switch value % 10 {
            case 1: form = 0
            case 2...4: form = 1
            default: form = 2
            }
        }
        let word: String
        switch noun {
        case "song": word = ["трек", "трека", "треков"][form]
        case "lyrics file": word = ["файл с текстом", "файла с текстом", "файлов с текстом"][form]
        case "file": word = ["файл", "файла", "файлов"][form]
        case "minute": word = "мин"
        default: word = noun
        }
        return "\(count) \(word)"
    }
}
