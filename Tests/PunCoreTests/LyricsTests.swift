import XCTest
@testable import PunCore

final class LyricsTests: XCTestCase {

    private let sample = """
    [ti:My Song]
    [ar:Someone]
    [00:12.00]First line
    [00:17.50] Second line
    [01:02.25][01:30.00]Chorus
    """

    func testParsesTimedLinesInOrder() throws {
        let lyrics = try XCTUnwrap(SynchronizedLyrics(lrc: sample))
        XCTAssertEqual(lyrics.lines.map(\.timeMs), [12_000, 17_500, 62_250, 90_000])
        XCTAssertEqual(lyrics.lines.map(\.text), ["First line", "Second line", "Chorus", "Chorus"])
    }

    func testMetadataTagsAreNotLines() throws {
        let lyrics = try XCTUnwrap(SynchronizedLyrics(lrc: sample))
        XCTAssertFalse(lyrics.lines.contains { $0.text.contains("My Song") })
    }

    func testNoTimestampsReturnsNil() {
        XCTAssertNil(SynchronizedLyrics(lrc: "just plain text\nno timestamps"))
        XCTAssertNil(SynchronizedLyrics(lrc: ""))
    }

    func testLineLookupUsesHalfSecondLead() throws {
        let lyrics = try XCTUnwrap(SynchronizedLyrics(lrc: sample))
        XCTAssertEqual(lyrics.line(atPositionMs: 11_500), "First line")  // 500ms before it starts
        XCTAssertEqual(lyrics.line(atPositionMs: 17_000), "Second line")
        XCTAssertEqual(lyrics.line(atPositionMs: 17_499), "Second line")
    }

    func testBeforeFirstTimestampReturnsFirstLine() throws {
        let lyrics = try XCTUnwrap(SynchronizedLyrics(lrc: sample))
        XCTAssertEqual(lyrics.index(atPositionMs: 0), 0)
    }

    func testAfterLastTimestampReturnsLastLine() throws {
        let lyrics = try XCTUnwrap(SynchronizedLyrics(lrc: sample))
        XCTAssertEqual(lyrics.index(atPositionMs: 10_000_000), 3)
    }

    func testOffsetTag() throws {
        let lrc = "[offset:1000]\n[00:10.00]Hello"
        let lyrics = try XCTUnwrap(SynchronizedLyrics(lrc: lrc))
        XCTAssertEqual(lyrics.offsetMs, 1000)
        // 8500 + 1000 offset + 500 lead = 10000 → line becomes active
        XCTAssertEqual(lyrics.index(atPositionMs: 8_500), 0)
    }

    func testMillisecondRounding() throws {
        let lyrics = try XCTUnwrap(SynchronizedLyrics(lrc: "[00:12.29]x"))
        XCTAssertEqual(lyrics.lines.first?.timeMs, 12_290)
    }

    func testWindowsLineEndings() throws {
        let lyrics = try XCTUnwrap(SynchronizedLyrics(lrc: "[00:01.00]a\r\n[00:02.00]b\r\n"))
        XCTAssertEqual(lyrics.lines.map(\.text), ["a", "b"])
    }

    func testEmptyTextLinesAreKept() throws {
        let lyrics = try XCTUnwrap(SynchronizedLyrics(lrc: "[00:01.00]a\n[00:05.00]\n[00:09.00]b"))
        XCTAssertEqual(lyrics.lines.map(\.text), ["a", "", "b"])
    }

    func testPlainText() throws {
        let lyrics = try XCTUnwrap(SynchronizedLyrics(lrc: "[00:01.00]a\n[00:02.00]b"))
        XCTAssertEqual(lyrics.plainText, "a\nb")
    }

    func testUnicodeText() throws {
        let lyrics = try XCTUnwrap(SynchronizedLyrics(lrc: "[00:01.00]Привет, мир"))
        XCTAssertEqual(lyrics.lines.first?.text, "Привет, мир")
    }
}
