import XCTest
@testable import BlottleKit

final class ArgumentSplitterTests: XCTestCase {
    func testSplitsQuotesAndEscapes() {
        XCTAssertEqual(ArgumentSplitter.split(#"-a "b c" 'd e' f\ g"#), ["-a", "b c", "d e", "f g"])
        XCTAssertEqual(ArgumentSplitter.split("   "), [])
        XCTAssertEqual(ArgumentSplitter.split(#""" x"#), ["", "x"])
    }

    func testJoinRoundTrips() {
        let arguments = ["-noverifyfiles", "path with spaces", "quote\"inside"]
        XCTAssertEqual(ArgumentSplitter.split(ArgumentSplitter.join(arguments)), arguments)
    }
}
