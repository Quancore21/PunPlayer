//
//  PunPlayer — Services/ArtworkStore.swift
//
//  Cover art cache. Counterpart of Musicr's Glide pipeline (`glide/*`) and its
//  palette/colour extraction. Images are stored once per unique picture (content hash),
//  so an album with 12 tracks stores one file. PunPlayer is licensed under GPLv3.
//

import UIKit
import CryptoKit
import ImageIO
import os

final class ArtworkStore {
    static let shared = ArtworkStore()

    private let cache = NSCache<NSString, UIImage>()
    // The scanner uses ArtworkStore from a detached task while SwiftUI requests covers on the
    // main thread. NSCache is thread-safe, but these collections and file lifecycle are not.
    // A recursive lock allows tint() to call image() without creating a lock-order deadlock.
    private let stateLock = NSRecursiveLock()
    private var tints: [String: UIColor] = [:]
    private var missing = Set<String>()

    private let logger = Logger(subsystem: "com.quancore21.punplayer", category: "artwork")

    /// Saves raw image bytes and returns the key to store on the Song, or nil if the cover could not be
    /// written. The song is kept either way; it just has no cover (and no key pointing at a missing file).
    func save(_ data: Data) -> String? {
        // Reject invalid image payloads before creating a persistent key. Otherwise a bad file can
        // poison the cache and be treated as a valid cover on every later lookup.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 96
              ] as CFDictionary) != nil else {
            logger.error("Rejected invalid artwork payload (\(data.count) bytes)")
            return nil
        }

        let digest = SHA256.hash(data: data)
        let key = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        stateLock.lock()
        defer { stateLock.unlock() }
        guard ArtworkFiles.store(data, key: key, in: AppPaths.artworkDirectory) else {
            logger.error("Could not store cover \(key, privacy: .public) (\(data.count) bytes)")
            return nil
        }
        missing.remove(key)
        return key
    }

    /// Deletes cover files no song refers to any more (e.g. after a cover was replaced).
    /// Keys are content hashes, so cached images stay valid; only "missing" lookups are reset.
    func prune(keeping keys: Set<String>) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let directory = AppPaths.artworkDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where !keys.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        missing.removeAll(keepingCapacity: true)
        tints = tints.filter { keys.contains($0.key) }
    }

    /// Downsampled image, cached in memory.
    func image(forKey key: String, maxPixel: CGFloat) -> UIImage? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let pixel = max(32, min(maxPixel, 1600))
        let cacheKey = "\(key)-\(Int(pixel))" as NSString
        if let hit = cache.object(forKey: cacheKey) { return hit }
        if missing.contains(key) { return nil }

        // Keep prune/save from deleting or replacing the file while ImageIO is reading it.
        let url = AppPaths.artworkDirectory.appendingPathComponent(key)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            missing.insert(key)
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            missing.insert(key)
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: cacheKey)
        missing.remove(key)
        return image
    }

    /// Dominant-ish colour of the cover (average, then clamped to a pleasant range),
    /// used to tint backgrounds like Musicr does with the cover palette.
    func tint(forKey key: String?) -> UIColor? {
        guard let key else { return nil }
        stateLock.lock()
        defer { stateLock.unlock() }
        if let cached = tints[key] { return cached }
        guard let cgImage = image(forKey: key, maxPixel: 48)?.cgImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: space, bitmapInfo: info
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }

        let average = UIColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let tint = UIColor(
            hue: hue,
            saturation: max(saturation, 0.35),
            brightness: min(max(brightness, 0.35), 0.8),
            alpha: 1)
        tints[key] = tint
        return tint
    }
}
