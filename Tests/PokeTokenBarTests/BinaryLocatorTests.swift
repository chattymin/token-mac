import XCTest
@testable import PokeTokenBar

final class BinaryLocatorTests: XCTestCase {
    func testParsesCleanMarkedPath() {
        XCTAssertEqual(
            BinaryLocator.parseMarkedPath("<<<BIN:/opt/homebrew/bin/ccusage:BIN>>>"),
            "/opt/homebrew/bin/ccusage")
    }

    func testIgnoresProfileNoiseAroundMarker() {
        // 인터랙티브 셸이 neofetch 등 stdout noise 를 찍어도 마커만 추출
        let noisy = """
        ⠀⣴⣶⣷ neofetch art line 1
        OS: macOS / Shell: zsh
        <<<BIN:/Users/x/.local/share/mise/installs/node/22.14.0/bin/ccusage:BIN>>>
        """
        XCTAssertEqual(
            BinaryLocator.parseMarkedPath(noisy),
            "/Users/x/.local/share/mise/installs/node/22.14.0/bin/ccusage")
    }

    func testEmptyPathReturnsNil() {
        // command -v 가 못 찾으면 마커 사이가 비어 있음
        XCTAssertNil(BinaryLocator.parseMarkedPath("noise\n<<<BIN::BIN>>>\n"))
    }

    func testMissingMarkersReturnsNil() {
        XCTAssertNil(BinaryLocator.parseMarkedPath("just some neofetch output, no marker"))
        XCTAssertNil(BinaryLocator.parseMarkedPath("<<<BIN:/path/without/closing"))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(BinaryLocator.parseMarkedPath("<<<BIN:  /usr/local/bin/codex \n :BIN>>>"),
                       "/usr/local/bin/codex")
    }

    func testCommonPathsIncludeManagersForBinary() {
        let paths = BinaryLocator.commonNodeToolPaths("ccusage")
        XCTAssertTrue(paths.contains("/opt/homebrew/bin/ccusage"))
        XCTAssertTrue(paths.contains { $0.contains("/.local/share/mise/shims/ccusage") })
        XCTAssertTrue(paths.contains { $0.contains("/.asdf/shims/ccusage") })
        XCTAssertTrue(paths.contains { $0.contains("/.volta/bin/ccusage") })
    }
}
