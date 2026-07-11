import Foundation
import CryptoKit
import Security

/// URLSession delegate that enforces TLS for api.x.ai and pins leaf SPKI hashes.
final class GrokURLSessionDelegate: NSObject, URLSessionDelegate {
    
    /// SHA-256 of SubjectPublicKeyInfo (base64), matching:
    /// `openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64`
    /// Update when xAI rotates the api.x.ai leaf (observed expiry ~Sep 2026).
    static let pinnedSPKIBase64: Set<String> = [
        "w0mNQ7FR7JYdy4YIcDli9Gaj+BQYD1WxTKjO9tuHB40="
    ]
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              challenge.protectionSpace.host == "api.x.ai" else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            Log.error("TLS trust evaluation failed: \(String(describing: error))", category: "GrokTLS")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        guard let pin = Self.leafSPKIPin(from: trust), Self.pinnedSPKIBase64.contains(pin) else {
            Log.error("TLS public key pin mismatch for api.x.ai", category: "GrokTLS")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    
    static func leafSPKIPin(from trust: SecTrust) -> String? {
        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = certificates.first,
              let key = SecCertificateCopyKey(leaf),
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return nil
        }
        
        let spki: Data
        if keyData.count == 65, keyData.first == 0x04 {
            spki = spkiForUncompressedP256(keyData)
        } else {
            spki = keyData
        }
        
        return Data(SHA256.hash(data: spki)).base64EncodedString()
    }
    
    /// DER-encoded SubjectPublicKeyInfo for an uncompressed P-256 public key.
    static func spkiForUncompressedP256(_ publicKey: Data) -> Data {
        let prefix = Data([
            0x30, 0x59,
            0x30, 0x13,
            0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
            0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
            0x03, 0x42, 0x00
        ])
        return prefix + publicKey
    }
}

enum GrokURLSessionFactory {
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(
            configuration: config,
            delegate: GrokURLSessionDelegate(),
            delegateQueue: nil
        )
    }
}
