import CoreNFC
import CryptoKit
import Foundation

final class NFCCardScanner: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
  @Published private(set) var isScanning = false
  @Published private(set) var lastErrorMessage: String?
  @Published private(set) var diagnosticLines: [String] = ["NFC idle."]

  var onKeyScanned: ((ScannedNFCKey) -> Void)?

  private var session: NFCTagReaderSession?

  var isAvailable: Bool {
    NFCTagReaderSession.readingAvailable
  }

  func beginScanning(reason: String = "Manual scan requested.") {
    guard NFCTagReaderSession.readingAvailable else {
      lastErrorMessage = "NFC scanning is not available on this device."
      diagnosticLines = ["NFC unavailable on this device."]
      return
    }

    lastErrorMessage = nil
    isScanning = true
    diagnosticLines = [
      reason,
      "Polling ISO 14443, ISO 15693, and ISO 18092."
    ]

    guard let session = NFCTagReaderSession(
      pollingOption: [.iso14443, .iso15693, .iso18092],
      delegate: self,
      queue: nil
    ) else {
      isScanning = false
      lastErrorMessage = "Unable to create an NFC reader session."
      diagnosticLines.append("Unable to create NFCTagReaderSession.")
      return
    }

    session.alertMessage = "Hold your iPhone near the Brick NFC card."
    session.begin()
    self.session = session
  }

  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    DispatchQueue.main.async {
      self.diagnosticLines.append("Reader session active.")
    }
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
    DispatchQueue.main.async {
      self.isScanning = false

      let nsError = error as NSError
      if nsError.domain == NFCReaderError.errorDomain,
         nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
        self.diagnosticLines.append("Reader session canceled.")
        return
      }

      self.lastErrorMessage = error.localizedDescription
      self.diagnosticLines.append("Reader invalidated: \(nsError.domain) \(nsError.code) \(error.localizedDescription)")
    }
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    guard let tag = tags.first else {
      DispatchQueue.main.async {
        self.diagnosticLines.append("Detected callback with no tags; restarting polling.")
      }
      session.restartPolling()
      return
    }

    DispatchQueue.main.async {
      self.diagnosticLines.append("Detected \(tags.count) tag(s).")
      self.diagnosticLines.append(NFCFingerprint.summary(from: tag))
    }

    session.connect(to: tag) { error in
      if let error {
        session.invalidate(errorMessage: error.localizedDescription)
        return
      }

      let scannedKey = NFCFingerprint.scannedKey(from: tag)
      session.alertMessage = "Card scanned."
      session.invalidate()

      DispatchQueue.main.async {
        self.isScanning = false
        self.diagnosticLines.append("Card fingerprint saved: \(scannedKey.id.prefix(12))...")
        self.onKeyScanned?(scannedKey)
      }
    }
  }
}

enum NFCFingerprint {
  static func cardID(from tag: NFCTag) -> String {
    fingerprint(bytes: identifierBytes(from: tag))
  }

  static func scannedKey(from tag: NFCTag) -> ScannedNFCKey {
    let summary = summary(from: tag)
    let kind = inferredKind(from: tag)

    return ScannedNFCKey(
      id: cardID(from: tag),
      defaultName: kind.displayName,
      kind: kind,
      detail: summary
    )
  }

  static func summary(from tag: NFCTag) -> String {
    let bytes = identifierBytes(from: tag)
    let byteSummary = bytes.isEmpty ? "no identifier bytes" : "\(bytes.count) identifier byte(s)"

    switch tag {
    case .miFare(let tag):
      return "Tag type: MiFare, \(byteSummary), family: \(tag.mifareFamily.rawValue)."
    case .iso15693:
      return "Tag type: ISO 15693, \(byteSummary)."
    case .iso7816(let tag):
      return "Tag type: ISO 7816, \(byteSummary), selected AID: \(tag.initialSelectedAID)."
    case .feliCa:
      return "Tag type: FeliCa, \(byteSummary)."
    @unknown default:
      return "Tag type: unknown, \(byteSummary)."
    }
  }

  private static func inferredKind(from tag: NFCTag) -> PairedNFCKeyKind {
    switch tag {
    case .iso7816(let tag):
      let aid = tag.initialSelectedAID.uppercased()
      if aid.hasPrefix("A000000527") {
        return .yubiKey
      }

      if aid == "A0000006472F0001" {
        return .titanKey
      }

      return .nfcKey
    case .miFare, .feliCa:
      return .easyCard
    case .iso15693:
      return .nfcKey
    @unknown default:
      return .nfcKey
    }
  }

  private static func identifierBytes(from tag: NFCTag) -> [UInt8] {
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

    return bytes
  }

  static func fingerprint(bytes: [UInt8]) -> String {
    let digest = SHA256.hash(data: Data(bytes))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
