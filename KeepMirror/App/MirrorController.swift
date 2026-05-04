import AppKit
import AVFoundation
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - MirrorController

@MainActor
final class MirrorController: ObservableObject {

    let settings: MirrorSettings
    let cameraManager: CameraManager

    /// Injected after construction by AppEnvironment so settings can drive hotkey changes.
    weak var hotkeyManager: GlobalHotkeyManager?

    private let windowManager: SettingsWindowManaging
    private let launchAtLoginManager: LaunchAtLoginManaging
    private let linkOpener: LinkOpening
    private var cancellables: Set<AnyCancellable> = []

    @Published var selectedTab: AppTab = .settings

    // MARK: Init

    init(
        settings: MirrorSettings,
        cameraManager: CameraManager,
        windowManager: SettingsWindowManaging,
        launchAtLoginManager: LaunchAtLoginManaging,
        linkOpener: LinkOpening
    ) {
        self.settings = settings
        self.cameraManager = cameraManager
        self.windowManager = windowManager
        self.launchAtLoginManager = launchAtLoginManager
        self.linkOpener = linkOpener

        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cameraManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Launch

    func handleLaunch() async {
        if settings.startAtLogin != launchAtLoginManager.isEnabled {
            launchAtLoginManager.isEnabled = settings.startAtLogin
        }
        seedDefaultDevicesIfNeeded()
        _ = await cameraManager.requestCameraPermission()

        // Auto-enable mic check the first time mic permission is granted
        // (so users see the meter without manually finding the toggle)
        if !settings.hasAutoEnabledMic {
            let micGranted = await cameraManager.requestMicPermission()
            if micGranted {
                settings.micCheckEnabled  = true
                settings.hasAutoEnabledMic = true
            }
        }
    }

    private func seedDefaultDevicesIfNeeded() {
        cameraManager.enumerateDevices()
        if settings.selectedCameraID.isEmpty {
            settings.selectedCameraID = cameraManager.defaultCameraID()
        }
        if settings.selectedMicID.isEmpty {
            settings.selectedMicID = cameraManager.defaultMicID()
        }
    }

    // MARK: - Launch at login

    var startAtLoginEnabled: Bool {
        get { launchAtLoginManager.isEnabled }
        set {
            launchAtLoginManager.isEnabled = newValue
            settings.startAtLogin = newValue
            objectWillChange.send()
        }
    }

    // MARK: - Settings window

    func openSettings(tab: AppTab = .settings) {
        selectedTab = tab
        windowManager.show(selectedTab: tab)
    }

    // MARK: - Camera lifecycle

    func startCamera() {
        seedDefaultDevicesIfNeeded()
        cameraManager.startSession(
            cameraID: settings.selectedCameraID,
            micID: settings.selectedMicID,
            micEnabled: settings.micCheckEnabled,
            flipped: settings.isFlipped,
            quality: settings.sessionQuality.avPreset
        )
    }

    /// Synchronous stop — blocks until session is fully off.
    func stopCamera() {
        cameraManager.stopSessionSync()
    }

    // MARK: - Photo capture

    func capturePhoto() {
        cameraManager.capturePhoto { [weak self] image in
            guard let image else { return }
            Task { @MainActor [weak self] in
                await self?.handleCapturedImage(image)
            }
        }
    }

    /// Central handler: shows save panel on first capture (no bookmark saved yet),
    /// then writes directly to the bookmarked directory on subsequent captures.
    private func handleCapturedImage(_ image: NSImage) async {
        if settings.photoSaveBookmark == nil {
            await showSavePanelAndSave(image)
        } else {
            let dir = settings.resolvedPhotoSaveURL
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("mirror_\(filenameTimestamp()).\(settings.captureFormat.fileExtension)")
            writeImage(image, to: fileURL)
            postCaptureActions(image: image, savedTo: fileURL)
        }
    }

    /// Presents NSSavePanel. On confirmation, bookmarks the folder for future saves.
    private func showSavePanelAndSave(_ image: NSImage) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let panel = NSSavePanel()
            panel.title   = "Save Mirror Photo"
            panel.message = "Choose where to save this photo. KeepMirror will remember for next time."
            panel.nameFieldStringValue = "mirror_\(filenameTimestamp()).\(settings.captureFormat.fileExtension)"
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false

            panel.begin { [weak self] response in
                defer { continuation.resume() }
                guard let self, response == .OK, let url = panel.url else { return }

                // Persist the chosen folder as a security-scoped bookmark
                let dir = url.deletingLastPathComponent()
                if let bm = try? dir.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    Task { @MainActor in self.settings.photoSaveBookmark = bm }
                }
                self.writeImage(image, to: url)
                self.postCaptureActions(image: image, savedTo: url)
            }
        }
    }

    // MARK: - Save helpers

    private func filenameTimestamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: Date())
    }

    private func writeImage(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff) else { return }
        let data: Data?
        switch settings.captureFormat {
        case .png:  data = rep.representation(using: .png,  properties: [:])
        case .jpeg: data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        case .heif: data = encodeHEIF(rep: rep)
        }
        try? data?.write(to: url)
    }

    private func postCaptureActions(image: NSImage, savedTo url: URL) {
        if settings.copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
        if settings.revealInFinder {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }


    // MARK: - HEIF encoding (CGImageDestination — true HEIC, falls back to JPEG)

    private func encodeHEIF(rep: NSBitmapImageRep) -> Data? {
        guard let cgImage = rep.cgImage else { return rep.representation(using: .jpeg, properties: [:]) }
        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            buffer as CFMutableData,
            UTType.heic.identifier as CFString,
            1, nil
        ) else { return rep.representation(using: .jpeg, properties: [:]) }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return rep.representation(using: .jpeg, properties: [:]) }
        return buffer as Data
    }

    // MARK: - Live reconfiguration

    func applyFlipChange() {
        cameraManager.setMirroring(flipped: settings.isFlipped)
    }

    func applyCameraChange() {
        guard cameraManager.isRunning else { return }
        cameraManager.switchCamera(
            to: settings.selectedCameraID,
            flipped: settings.isFlipped,
            quality: settings.sessionQuality.avPreset
        )
    }

    func applyMicChange() {
        cameraManager.reconfigureMic(
            micID: settings.selectedMicID,
            micEnabled: settings.micCheckEnabled
        )
    }

    // MARK: - Links

    func open(_ link: ExternalLink) { linkOpener.open(link.url) }
}
