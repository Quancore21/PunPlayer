import XCTest
@testable import PunCore

final class WaveformMathTests: XCTestCase {
    func testNormalizationIsDeterministicAndPreservesRelativeAmplitude() {
        let input: [Float] = [0.05, 0.20, 0.75, 1.0, 0.35]
        let first = WaveformMath.normalizedPeaks(input)
        let second = WaveformMath.normalizedPeaks(input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first[3], 1.0, accuracy: 0.000_001)
        XCTAssertGreaterThan(first[2], first[1])
        XCTAssertGreaterThan(first[1], first[0])
        XCTAssertEqual(first.count, input.count)
    }

    func testSilenceRemainsFlatInsteadOfInventingWaveform() {
        XCTAssertEqual(WaveformMath.normalizedPeaks([0, 0, 0, 0]), [0, 0, 0, 0])
    }

    func testInvalidAndOutOfRangeAmplitudesAreSanitized() {
        let result = WaveformMath.normalizedPeaks([.nan, -1, 0.25, .infinity, 5])
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result[0], 0)
        XCTAssertEqual(result[1], 0)
        XCTAssertGreaterThan(result[2], 0)
        XCTAssertLessThan(result[2], 1)
        XCTAssertEqual(result[3], 0)
        XCTAssertEqual(result[4], 1, accuracy: 0.000_001)
    }

    func testEmptyInputRemainsEmpty() {
        XCTAssertTrue(WaveformMath.normalizedPeaks([]).isEmpty)
    }
}
