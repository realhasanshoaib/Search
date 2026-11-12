import AppKit
import WebKit
import XCTest
@testable import Search

@available(macOS 15.4, *)
@MainActor
final class ExtensionTabLocationTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "extension-location-\(getpid())", 1)
        super.setUp()
    }

    func testBlankTabsInOverlappingWindowsAreFoundByTheirWholeRow() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("location-ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try #"{"manifest_version":3,"name":"Location test","version":"1.0"}"#.write(
            to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: folder))
        let first = Browser(record: WindowRecord())
        let second = Browser(record: WindowRecord())
        let frame = NSRect(x: -20_000, y: -20_000, width: 800, height: 600)
        let windows = [first, second].map { browser in
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            browser.window = window
            Browsers.register(browser)
            return window
        }
        defer {
            Browsers.discard(first)
            Browsers.discard(second)
            windows.forEach { $0.close() }
        }
        let height = NSScreen.screens.first?.frame.height ?? 0
        let seen = CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
        let blank = try XCTUnwrap(second.tabs.first)
        XCTAssertNil(Extensions.shared.tab(windowFrame: seen, index: 0, address: "", windowTabs: [""], for: context),
                     "Two identical blank rows must not guess which window owns the tab")

        _ = first.open(try XCTUnwrap(URL(string: "https://example.com/")), foreground: false, mayWait: true)
        XCTAssertNil(Extensions.shared.tab(windowFrame: seen, index: 0, address: "", for: context))
        XCTAssertTrue(Extensions.shared.tab(windowFrame: seen, index: 0, address: "", windowTabs: [""], for: context) === blank,
                      "Claude groups the blank tab of the window it just created, not a blank tab in the old window")
        _ = second.open(try XCTUnwrap(URL(string: "https://example.org/")), foreground: false, mayWait: true)
        XCTAssertTrue(Extensions.shared.tab(windowFrame: seen, index: 0, address: "", windowTabs: ["", "https://example.org/"], for: context) === blank)
        XCTAssertNil(Extensions.shared.tab(windowFrame: seen, index: 0, address: "", windowTabs: ["", "https://example.net/"], for: context),
                     "A stale row must not select a different window")
        XCTAssertFalse(windows.contains { $0.isVisible })
    }
}
