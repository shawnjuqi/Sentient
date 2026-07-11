import XCTest
@testable import sentient

final class GrokErrorTests: XCTestCase {
    func testUserFacingMessageForUnauthorized() {
        XCTAssertEqual(
            GrokError.userFacingMessage(forStatusCode: 401),
            "API key rejected. Check your key in Settings."
        )
    }
    
    func testUserFacingMessageForRateLimit() {
        XCTAssertEqual(
            GrokError.userFacingMessage(forStatusCode: 429),
            "Rate limited by xAI. Try again in a moment."
        )
    }
    
    func testUserFacingMessageHidesRawBody() {
        let error = GrokError.httpError(statusCode: 500, message: "secret internal detail")
        XCTAssertEqual(error.localizedDescription, "Grok service is temporarily unavailable.")
        XCTAssertFalse(error.localizedDescription.contains("secret"))
    }
    
    func testSPKIWrapperLengthForP256() {
        let fakeKey = Data([0x04] + Array(repeating: UInt8(1), count: 64))
        let spki = GrokURLSessionDelegate.spkiForUncompressedP256(fakeKey)
        XCTAssertEqual(spki.count, 91) // 26 byte prefix + 65 byte key
    }
}
