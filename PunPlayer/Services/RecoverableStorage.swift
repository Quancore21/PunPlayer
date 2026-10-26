//
//  PunPlayer — Services/RecoverableStorage.swift
//  A store whose file could not be read keeps its data in memory but cannot save. The app shows a
//  banner for as long as that lasts and offers explicit recovery. PunPlayer is licensed under GPLv3.
//

import Foundation

protocol RecoverableStorage: AnyObject {
    /// Short name for the banner, e.g. "Playlists".
    var storageName: String { get }
    /// True while saving is paused for this store.
    var isReadOnly: Bool { get }
    /// Reads the file again; saving resumes if it is readable now.
    func retryStorage()
    /// Confirmed reset: moves the unreadable file aside and starts saving the current data.
    func resetStorage()
}
