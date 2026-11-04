//
// PunPlayer -- Core/Localization.swift
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
        if #available(iOS 16, macOS 13, *) {
            return Locale.current.language.languageCode?.identifier == "ru"
        } else {
            return Locale.current.languageCode == "ru"
        }
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
        if let number = arguments.first as? Int, arguments.count == 1 {
            switch key {
            case "home.library.count":
                return isRussian ? "\(count(number, noun: "track")) в медиатеке" : "\(count(number, noun: "track")) in your library"
            case "home.playlists.count":
                return count(number, noun: "personal playlist")
            case "album.count":
                return count(number, noun: "album")
            case "playlist.count", "album.trackCount":
                return count(number, noun: "track")
            case "cleanup.removeEntries":
                return isRussian ? "Удалить \(count(number, noun: "entry"))" : "Remove \(count(number, noun: "entry"))"
            default:
                break
            }
        }
        return String(format: string(key, defaultValue: defaultFormat), locale: locale, arguments: arguments)
    }

    private static func russianForm(for count: Int) -> Int {
        let value = abs(count)
        let lastTwo = value % 100
        if (11...14).contains(lastTwo) { return 2 }
        switch value % 10 {
        case 1: return 0
        case 2...4: return 1
        default: return 2
        }
    }

    /// Language-aware short counts, including the three common Russian plural forms.
    static func count(_ count: Int, noun: String) -> String {
        guard isRussian else {
            let english: (String, String)
            switch noun {
            case "song": english = ("song", "songs")
            case "track": english = ("track", "tracks")
            case "album": english = ("album", "albums")
            case "personal playlist": english = ("personal playlist", "personal playlists")
            case "entry": english = ("entry", "entries")
            case "lyrics file": english = ("lyrics file", "lyrics files")
            case "file": english = ("file", "files")
            case "minute": english = ("min", "min")
            default: english = (noun, noun + "s")
            }
            return "\(count) \(count == 1 ? english.0 : english.1)"
        }

        let form = russianForm(for: count)
        let word: String
        switch noun {
        case "song", "track": word = ["трек", "трека", "треков"][form]
        case "album": word = ["альбом", "альбома", "альбомов"][form]
        case "personal playlist": word = ["личный плейлист", "личных плейлиста", "личных плейлистов"][form]
        case "entry": word = ["запись", "записи", "записей"][form]
        case "lyrics file": word = ["файл с текстом", "файла с текстом", "файлов с текстом"][form]
        case "file": word = ["файл", "файла", "файлов"][form]
        case "minute": word = "мин"
        default: word = noun
        }
        return "\(count) \(word)"
    }
}
