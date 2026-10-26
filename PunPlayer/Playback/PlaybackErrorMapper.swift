//
//  PunPlayer — Playback/PlaybackErrorMapper.swift
//  Turns AVFoundation / Foundation errors into a PlaybackFailureKind.
//  PunPlayer is licensed under GPLv3.
//

import Foundation
import AVFoundation

enum PlaybackErrorMapper {
    static func kind(for error: Error?) -> PlaybackFailureKind {
        guard let error else { return .other }

        // AVFoundation often wraps the real reason in NSUnderlyingError.
        var chain: [NSError] = []
        var current: NSError? = error as NSError
        while let next = current, chain.count < 6 {
            chain.append(next)
            current = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        var sawOSStatus = false
        for e in chain {
            if e.domain == NSCocoaErrorDomain,
               e.code == CocoaError.fileNoSuchFile.rawValue || e.code == CocoaError.fileReadNoSuchFile.rawValue {
                return .missingFile
            }
            if e.domain == NSURLErrorDomain, e.code == NSURLErrorFileDoesNotExist { return .missingFile }
            if e.domain == NSPOSIXErrorDomain, e.code == Int(ENOENT) { return .missingFile }

            if e.domain == AVFoundationErrorDomain, let code = AVError.Code(rawValue: e.code) {
                switch code {
                case .fileFormatNotRecognized, .decoderNotFound: return .unsupportedFormat
                case .fileFailedToParse: return .corruptedFile
                default: break
                }
            }
            if e.domain == NSOSStatusErrorDomain { sawOSStatus = true }
        }
        // CoreMedia / AudioToolbox status codes at the bottom of the chain mean the data is bad.
        return sawOSStatus ? .corruptedFile : .other
    }
}
