//
//  PunPlayer — Core/ShuffleHelper.swift
//
//  Port of Musicr `helper/ShuffleHelper.java` by Karim Abou Zeid (kabouzeid), GPLv3.
//  Keeps the currently playing item first and shuffles the rest.
//
//  PunPlayer is licensed under GPLv3. See LICENSE and NOTICE.md.
//

import Foundation

enum ShuffleHelper {
    static func makeShuffleList<T, G: RandomNumberGenerator>(
        _ list: inout [T], current: Int, using generator: inout G
    ) {
        guard !list.isEmpty else { return }
        if current >= 0, current < list.count {
            let first = list.remove(at: current)
            list.shuffle(using: &generator)
            list.insert(first, at: 0)
        } else {
            list.shuffle(using: &generator)
        }
    }

    static func makeShuffleList<T>(_ list: inout [T], current: Int) {
        var generator = SystemRandomNumberGenerator()
        makeShuffleList(&list, current: current, using: &generator)
    }
}
