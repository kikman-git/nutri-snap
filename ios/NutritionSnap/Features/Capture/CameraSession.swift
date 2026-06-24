import SwiftUI
@preconcurrency import AVFoundation   // AVFoundation types aren't Sendable-audited; silence cross-actor warnings
import UIKit
import Observation

/// Live rear-camera capture for the Snap tab (PRD §5.2 — capture is the hero action).
/// The viewfinder binds to `session`; the nav-bar shutter calls `capturePhoto()`.
///
/// Gentle by design: a missing camera (Simulator) or a denied permission isn't an error —
/// it resolves to `.unavailable` / `.denied`, and the screen falls back to the library picker.
@MainActor
@Observable
final class CameraSession {
    enum Status: Equatable {
        case configuring   // initial / requesting access
        case ready         // running, shutter is live
        case denied        // user said no — offer Settings + library
        case unavailable   // no capture device (e.g. Simulator) — offer library
    }

    private(set) var status: Status = .configuring

    /// The session the SwiftUI preview layer renders. Read-only to callers.
    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.kikman.nutrisnap.camera")
    private var configured = false
    /// `AVCapturePhotoOutput` doesn't retain its delegate — hold it across the async capture.
    private var activeShot: PhotoShot?

    /// Request access (if needed), configure once, and start running. Idempotent.
    func start() async {
        // No camera hardware (e.g. Simulator) → fall back to the library without a permission prompt.
        guard Self.hasCameraDevice else { status = .unavailable; return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { status = .denied; return }
        default:
            status = .denied; return
        }

        let ready = await configureIfNeeded()
        guard ready else { status = .unavailable; return }

        let session = session
        queue.async { if !session.isRunning { session.startRunning() } }
        status = .ready
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    /// Capture one still, oriented portrait. Throws if the camera isn't ready.
    func capturePhoto() async throws -> UIImage {
        guard status == .ready else { throw CameraError.unavailable }

        let settings = AVCapturePhotoSettings()
        let output = output
        return try await withCheckedThrowingContinuation { continuation in
            let shot = PhotoShot { [weak self] result in
                Task { @MainActor in self?.activeShot = nil }
                continuation.resume(with: result)
            }
            activeShot = shot
            queue.async {
                if let connection = output.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90        // portrait
                }
                output.capturePhoto(with: settings, delegate: shot)
            }
        }
    }

    // MARK: - One-time session wiring (off the main thread)

    private static var hasCameraDevice: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(for: .video) != nil
    }

    private func configureIfNeeded() async -> Bool {
        if configured { return true }
        let session = session, output = output
        let ok: Bool = await withCheckedContinuation { continuation in
            queue.async {
                session.beginConfiguration()
                session.sessionPreset = .photo
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video)
                guard let device,
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input), session.canAddOutput(output)
                else { session.commitConfiguration(); continuation.resume(returning: false); return }
                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
                continuation.resume(returning: true)
            }
        }
        configured = ok
        return ok
    }
}

enum CameraError: Error { case unavailable, capture }

/// Bridges `AVCapturePhotoOutput`'s delegate callback to a one-shot completion.
/// `@unchecked Sendable`: created on the main actor, used by exactly one capture, its
/// completion fired once on AVFoundation's queue — safe to hand to the session queue.
private final class PhotoShot: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (Result<UIImage, Error>) -> Void
    init(completion: @escaping (Result<UIImage, Error>) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error { completion(.failure(error)); return }
        // Downsample straight from the JPEG data — a full 12MP decode here is ~49MB and was the OOM.
        guard let data = photo.fileDataRepresentation(),
              let image = DownsampledImage.make(from: data, maxDimension: 1600) else {
            completion(.failure(CameraError.capture)); return
        }
        completion(.success(image))
    }
}

/// Hosts an `AVCaptureVideoPreviewLayer` so the live feed renders inside SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        if let connection = uiView.previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90                 // portrait
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
