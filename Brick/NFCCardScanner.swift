import CoreNFC
import CryptoKit
import Foundation

final class NFCCardScanner: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
  @Published private(set) var isScanning = false
  @Published private(set) var lastErrorMessage: String?

  var onCardID: ((String) -> Void)?

  private var session: NFCTagReaderSession?

  var isAvailable: Bool {
    NFCTagReaderSession.readingAvailable
  }

  func beginScanning() {
    guard NFCTagReaderSession.readingAvailable else {
      lastErrorMessage = "NFC scanning is not available on this device."
      return
    }

    lastErrorMessage = nil
    isScanning = true

    guard let session = NFCTagReaderSession(
      pollingOption: [.iso14443, .iso15693],
      delegate: self,
      queue: nil
    ) else {
      isScanning = false
      lastErrorMessage = "Unable to create an NFC reader session."
      return
    }

    session.alertMessage = "Hold your iPhone near the Brick NFC card."
    session.begin()
    self.session = session
  }

  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

  func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
    DispatchQueue.main.async {
      self.isScanning = false

      let nsError = error as NSError
      if nsError.domain == NFCReaderError.errorDomain,
         nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
        return
      }

      self.lastErrorMessage = error.localizedDescription
    }
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    guard let tag = tags.first else {
      session.restartPolling()
      return
    }

    session.connect(to: tag) { error in
      if let error {
        session.invalidate(errorMessage: error.localizedDescription)
        return
      }

      let cardID = NFCFingerprint.cardID(from: tag)
      session.alertMessage = "Card scanned."
      session.invalidate()

      DispatchQueue.main.async {
        self.isScanning = false
        self.onCardID?(cardID)
      }
    }
  }
}

enum NFCFingerprint {
  static func cardID(from tag: NFCTag) -> String {
    let bytes: [UInt8]

    switch tag {
    case .miFare(let tag):
      bytes = Array(tag.identifier)
    case .iso15693(let tag):
      bytes = Array(tag.identifier)
    case .iso7816(let tag):
      bytes = Array(tag.identifier)
    case .feliCa(let tag):
      bytes = Array(tag.currentIDm)
    @unknown default:
      bytes = []
    }

    return fingerprint(bytes: bytes)
  }

  static func fingerprint(bytes: [UInt8]) -> String {
    let digest = SHA256.hash(data: Data(bytes))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
