import XCTest

@MainActor
final class MirrorSettingsTests: XCTestCase {

    private var sut: MirrorSettings!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        // Use a dedicated suite so tests don't pollute the real defaults
        defaults = UserDefaults(suiteName: "com.adhamhaithameid.keepmirror.tests")!
        defaults.removePersistentDomain(forName: "com.adhamhaithameid.keepmirror.tests")
        sut = MirrorSettings(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "com.adhamhaithameid.keepmirror.tests")
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Default values

    func testDefaultMirrorSizeIsMedium() {
        XCTAssertEqual(sut.mirrorSize, .medium)
    }

    func testDefaultFlipIsFalse() {
        XCTAssertFalse(sut.isFlipped)
    }

    func testDefaultMicCheckIsDisabled() {
        XCTAssertFalse(sut.micCheckEnabled)
    }

    func testDefaultNotchHoverIsDisabled() {
        XCTAssertFalse(sut.notchHoverEnabled)
    }

    func testDefaultHideMenuBarIconIsFalse() {
        XCTAssertFalse(sut.hideMenuBarIconWhenNotch)
    }

    func testDefaultStartAtLoginIsFalse() {
        XCTAssertFalse(sut.startAtLogin)
    }

    // MARK: - Persistence round-trips

    func testMirrorSizePersists() {
        sut.mirrorSize = .large
        let sut2 = MirrorSettings(defaults: defaults)
        XCTAssertEqual(sut2.mirrorSize, .large)
    }

    func testFlipPersists() {
        sut.isFlipped = true
        let sut2 = MirrorSettings(defaults: defaults)
        XCTAssertTrue(sut2.isFlipped)
    }

    func testMicCheckPersists() {
        sut.micCheckEnabled = true
        let sut2 = MirrorSettings(defaults: defaults)
        XCTAssertTrue(sut2.micCheckEnabled)
    }

    func testNotchHoverPersists() {
        sut.notchHoverEnabled = true
        let sut2 = MirrorSettings(defaults: defaults)
        XCTAssertTrue(sut2.notchHoverEnabled)
    }

    func testStartAtLoginPersists() {
        sut.startAtLogin = true
        let sut2 = MirrorSettings(defaults: defaults)
        XCTAssertTrue(sut2.startAtLogin)
    }

    func testSelectedCameraIDPersists() {
        sut.selectedCameraID = "cam-abc-123"
        let sut2 = MirrorSettings(defaults: defaults)
        XCTAssertEqual(sut2.selectedCameraID, "cam-abc-123")
    }

    func testSelectedMicIDPersists() {
        sut.selectedMicID = "mic-xyz-456"
        let sut2 = MirrorSettings(defaults: defaults)
        XCTAssertEqual(sut2.selectedMicID, "mic-xyz-456")
    }

    // MARK: - MirrorSize popover sizes

    func testMirrorSizeSmallPopoverSize() {
        let size = MirrorSize.small.popoverSize
        XCTAssertEqual(size.width, 280)
        XCTAssertEqual(size.height, 210)
    }

    func testMirrorSizeMediumPopoverSize() {
        let size = MirrorSize.medium.popoverSize
        XCTAssertEqual(size.width, 400)
        XCTAssertEqual(size.height, 300)
    }

    func testMirrorSizeLargePopoverSize() {
        let size = MirrorSize.large.popoverSize
        XCTAssertEqual(size.width, 560)
        XCTAssertEqual(size.height, 420)
    }

    // MARK: - Default save URL

    func testDefaultPhotoSaveURLIsInPictures() {
        let url = sut.resolvedPhotoSaveURL
        XCTAssertTrue(url.path.contains("Pictures"))
        XCTAssertTrue(url.lastPathComponent == "KeepMirror")
    }
}
