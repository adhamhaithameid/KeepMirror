import AVFoundation
import AppKit
import Combine

// MARK: - CameraDevice / MicDevice

struct CameraDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct MicDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

// MARK: - CameraManager

/// Owns `AVCaptureSession`. NOT @MainActor.
/// All session ops run on `sessionQueue`. Published state is bridged to MainActor.
final class CameraManager: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: Published (MainActor)

    @MainActor @Published private(set) var availableCameras: [CameraDevice] = []
    @MainActor @Published private(set) var availableMics:   [MicDevice]   = []
    @MainActor @Published private(set) var micLevel:        Float          = 0
    @MainActor @Published private(set) var isRunning:       Bool           = false
    @MainActor @Published private(set) var permissionGranted:    Bool      = false
    @MainActor @Published private(set) var micPermissionGranted: Bool      = false

    // MARK: AV objects (sessionQueue only)

    nonisolated(unsafe) let session      = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer   // thread-safe for layer reads

    private let sessionQueue = DispatchQueue(
        label: "com.adhamhaithameid.keepmirror.session",
        qos: .userInitiated
    )

    private nonisolated(unsafe) var currentCameraInput:  AVCaptureDeviceInput?
    private nonisolated(unsafe) var currentMicInput:     AVCaptureDeviceInput?
    private nonisolated(unsafe) var currentAudioOutput:  AVCaptureAudioDataOutput?   // FRESH each session
    private nonisolated(unsafe) var currentAudioQueue:   DispatchQueue?
    private nonisolated(unsafe) var audioDelegate:       AudioLevelDelegate?

    // Photo delegates kept alive until capture completes (max 10)
    private nonisolated(unsafe) var photoDelegates: [PhotoCaptureDelegate] = []
    private nonisolated(unsafe) let photoOutput = AVCapturePhotoOutput()

    private nonisolated(unsafe) var deviceObservers: [NSObjectProtocol] = []

    // MARK: Init

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
        enumerateDevices()
        observeDeviceChanges()
    }

    deinit {
        deviceObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Device enumeration

    func enumerateDevices() {
        let cameras = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown, .deskViewCamera],
            mediaType: .video, position: .unspecified
        ).devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }

        let mics = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio, position: .unspecified
        ).devices.map { MicDevice(id: $0.uniqueID, name: $0.localizedName) }

        Task { @MainActor in
            self.availableCameras = cameras
            self.availableMics = mics
        }
    }

    private func observeDeviceChanges() {
        let center = NotificationCenter.default
        deviceObservers = [
            center.addObserver(forName: .AVCaptureDeviceWasConnected,    object: nil, queue: .main) { [weak self] _ in self?.enumerateDevices() },
            center.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: .main) { [weak self] _ in self?.enumerateDevices() }
        ]
    }

    // MARK: - System defaults

    func defaultCameraID() -> String {
        if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) { return dev.uniqueID }
        if let dev = AVCaptureDevice.default(for: .video) { return dev.uniqueID }
        return AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .externalUnknown, .deskViewCamera],
                                                mediaType: .video, position: .unspecified).devices.first?.uniqueID ?? ""
    }

    func defaultMicID() -> String {
        if let dev = AVCaptureDevice.default(for: .audio) { return dev.uniqueID }
        return AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone, .externalUnknown],
                                                mediaType: .audio, position: .unspecified).devices.first?.uniqueID ?? ""
    }

    // MARK: - Permissions

    func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await MainActor.run { permissionGranted = true }; return true
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run { permissionGranted = ok }; return ok
        default:
            await MainActor.run { permissionGranted = false }; return false
        }
    }

    func requestMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            await MainActor.run { micPermissionGranted = true }; return true
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run { micPermissionGranted = ok }; return ok
        default:
            await MainActor.run { micPermissionGranted = false }; return false
        }
    }

    // Re-check camera permission (poll after user returns from System Settings)
    func recheckCameraPermission() {
        let granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        Task { @MainActor in self.permissionGranted = granted }
    }

    // Re-check mic permission (poll after user returns from System Settings)
    func recheckMicPermission() {
        let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        Task { @MainActor in self.micPermissionGranted = granted }
    }

    // MARK: - Session control

    /// Start the full session. Stops any running session first, then reconfigures.
    func startSession(cameraID: String, micID: String, micEnabled: Bool,
                      flipped: Bool, quality: AVCaptureSession.Preset) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            self.tearDownAudioUnsafe()   // always start fresh
            self.configureSession(cameraID: cameraID, micID: micID,
                                  micEnabled: micEnabled, flipped: flipped, quality: quality)
            self.session.startRunning()
            Task { @MainActor in self.isRunning = true }
        }
    }

    /// Synchronous stop — blocks caller until session is fully stopped.
    /// Safe to call from main thread. Camera light turns off before returning.
    func stopSessionSync() {
        sessionQueue.sync { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            self.tearDownAudioUnsafe()
        }
        Task { @MainActor in self.isRunning = false; self.micLevel = 0 }
    }

    // MARK: - Configuration (sessionQueue only)

    private func configureSession(cameraID: String, micID: String, micEnabled: Bool,
                                   flipped: Bool, quality: AVCaptureSession.Preset) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(quality) { session.sessionPreset = quality }

        // Clear all inputs and outputs completely
        session.inputs.forEach  { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        currentCameraInput = nil
        currentMicInput    = nil

        // ── Camera input ──────────────────────────────────────────────────
        let cam = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown, .deskViewCamera],
            mediaType: .video, position: .unspecified
        ).devices.first(where: { $0.uniqueID == cameraID })
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)

        if let cam, let input = try? AVCaptureDeviceInput(device: cam),
           session.canAddInput(input) {
            session.addInput(input)
            currentCameraInput = input
        }

        // ── Photo output ──────────────────────────────────────────────────
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        // ── Mirroring ─────────────────────────────────────────────────────
        applyMirrorUnsafe(flipped: flipped)

        // ── Mic (always create fresh output/delegate/queue) ───────────────
        if micEnabled && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            addMicUnsafe(micID: micID)
        }
    }

    /// Must be called on sessionQueue. Creates FRESH audio output every time
    /// to avoid the `canAddOutput → false` bug with reused instances.
    private func addMicUnsafe(micID: String) {
        let mic = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio, position: .unspecified
        ).devices.first(where: { $0.uniqueID == micID })
            ?? AVCaptureDevice.default(for: .audio)

        guard let mic else { return }

        do {
            let micInput = try AVCaptureDeviceInput(device: mic)
            guard session.canAddInput(micInput) else { return }
            session.addInput(micInput)
            currentMicInput = micInput
        } catch {
            return   // no mic available or not authorised
        }

        // Fresh output + fresh queue + fresh delegate every single time
        let output   = AVCaptureAudioDataOutput()
        let queue    = DispatchQueue(label: "com.keepmirror.audio", qos: .utility)
        let delegate = AudioLevelDelegate { [weak self] level in
            Task { @MainActor in self?.micLevel = level }
        }

        output.setSampleBufferDelegate(delegate, queue: queue)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        // Retain all three so they are not GC'd during the session
        currentAudioOutput = output
        currentAudioQueue  = queue
        audioDelegate      = delegate
    }

    private func tearDownAudioUnsafe() {
        if let out = currentAudioOutput {
            out.setSampleBufferDelegate(nil, queue: nil)
            if session.outputs.contains(out) { session.removeOutput(out) }
        }
        currentAudioOutput = nil
        currentAudioQueue  = nil
        audioDelegate      = nil
        Task { @MainActor in self.micLevel = 0 }
    }

    private func applyMirrorUnsafe(flipped: Bool) {
        if let conn = previewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = flipped
        }
        if let conn = photoOutput.connection(with: .video), conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = flipped
        }
    }

    // MARK: - Live reconfiguration

    func setMirroring(flipped: Bool) {
        sessionQueue.async { [weak self] in self?.applyMirrorUnsafe(flipped: flipped) }
    }

    func switchCamera(to cameraID: String, flipped: Bool, quality: AVCaptureSession.Preset) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if let old = self.currentCameraInput { self.session.removeInput(old); self.currentCameraInput = nil }
            if let dev = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .externalUnknown, .deskViewCamera],
                mediaType: .video, position: .unspecified
            ).devices.first(where: { $0.uniqueID == cameraID }) ?? AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: dev),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.currentCameraInput = input
            }
            self.applyMirrorUnsafe(flipped: flipped)
            self.session.commitConfiguration()
        }
    }

    func reconfigureMic(micID: String, micEnabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if let old = self.currentMicInput { self.session.removeInput(old); self.currentMicInput = nil }
            self.tearDownAudioUnsafe()
            if micEnabled && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                self.addMicUnsafe(micID: micID)
            }
            self.session.commitConfiguration()
        }
    }

    // MARK: - Photo capture

    func capturePhoto(completion: @escaping @Sendable (NSImage?) -> Void) {
        guard session.isRunning else { completion(nil); return }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        let delegate = PhotoCaptureDelegate { image in completion(image) }
        let ref = delegate
        delegate.onDone = { [weak self] in
            self?.photoDelegates.removeAll(where: { $0 === ref })
        }
        // Cap to 10 pending captures to avoid memory growth
        if photoDelegates.count > 10 { photoDelegates.removeFirst() }
        photoDelegates.append(delegate)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
}

// MARK: - AudioLevelDelegate

private final class AudioLevelDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let onLevel: @Sendable (Float) -> Void
    // Exponential smoothing state — fast attack, slow decay
    private var smoothed: Float = 0

    init(onLevel: @escaping @Sendable (Float) -> Void) { self.onLevel = onLevel }

    func captureOutput(_ output: AVCaptureOutput, didOutput buf: CMSampleBuffer, from connection: AVCaptureConnection) {
        // ── Step 1: determine required buffer-list size (handles any channel count) ──
        var listSize: Int = 0
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buf,
            bufferListSizeNeededOut: &listSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: nil
        )
        guard sizeStatus == noErr, listSize > 0 else { return }

        // ── Step 2: allocate exactly the right size and fill ──
        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: 16)
        defer { rawPtr.deallocate() }
        let listPtr = rawPtr.bindMemory(to: AudioBufferList.self, capacity: 1)

        var block: CMBlockBuffer?
        let fillStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buf,
            bufferListSizeNeededOut: nil,
            bufferListOut: listPtr,
            bufferListSize: listSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &block
        )
        guard fillStatus == noErr else { return }

        // ── Step 3: RMS across all channels ──
        let abl = UnsafeMutableAudioBufferListPointer(listPtr)
        var sumSq: Float = 0
        var totalSamples = 0

        for buf in abl {
            guard let data = buf.mData else { continue }
            // AVCaptureAudioDataOutput typically delivers Int16 PCM
            let sampleCount = Int(buf.mDataByteSize) / MemoryLayout<Int16>.size
            guard sampleCount > 0 else { continue }
            let ptr = data.assumingMemoryBound(to: Int16.self)
            for i in 0..<sampleCount {
                let f = Float(ptr[i]) / 32768.0
                sumSq += f * f
            }
            totalSamples += sampleCount
        }
        guard totalSamples > 0 else { return }

        let rms = sqrt(sumSq / Float(totalSamples))
        // 40× matches StandaloneMicMonitor's baseGain so both show the same level.
        let raw = min(rms * 40.0, 1.0)

        // Smooth: fast attack, slow decay
        let alpha: Float = raw > smoothed ? 0.20 : 0.85
        smoothed = alpha * smoothed + (1.0 - alpha) * raw
        onLevel(min(smoothed, 1.0))
    }
}

// MARK: - PhotoCaptureDelegate

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: @Sendable (NSImage?) -> Void
    var onDone: (() -> Void)?
    init(completion: @escaping @Sendable (NSImage?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let img = photo.fileDataRepresentation().flatMap { NSImage(data: $0) }
        let c = completion; let d = onDone
        DispatchQueue.main.async { c(img); d?() }
    }
}
