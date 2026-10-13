import XCTest
@testable import BlottleKit

final class WinePathTests: XCTestCase {
    func testRoundTrip() {
        let bottle = Bottle(name: "b", engineID: "e", url: URL(fileURLWithPath: "/tmp/bottles/b"))
        let unix = WinePath.toUnix("C:\\Program Files\\App\\app.exe", bottle: bottle)
        XCTAssertEqual(unix?.path, "/tmp/bottles/b/drive_c/Program Files/App/app.exe")
        XCTAssertEqual(WinePath.toWindows(unix!, bottle: bottle), "C:\\Program Files\\App\\app.exe")
        XCTAssertEqual(WinePath.toWindows(bottle.driveC, bottle: bottle), "C:\\")
    }

    func testOtherDrivesGoThroughDosDevices() {
        let bottle = Bottle(name: "b", engineID: "e", url: URL(fileURLWithPath: "/tmp/bottles/b"))
        XCTAssertEqual(WinePath.toUnix("D:\\Games\\x.exe", bottle: bottle)?.path, "/tmp/bottles/b/dosdevices/d:/Games/x.exe")
        XCTAssertNil(WinePath.toUnix("relative\\path", bottle: bottle))
        XCTAssertNil(WinePath.toWindows(URL(fileURLWithPath: "/elsewhere/x.exe"), bottle: bottle))
    }
}
